#!/usr/bin/env bash
set -euo pipefail

# Create video from slides with appropriate audio for each using Hume voices
# BACKWARDS COMPATIBLE: Supports both old (5 fixed slides) and new (variable slides) usage
#
# New Usage (recommended):
#   create_multi_slide_video_hume.sh DATE WORD --slides SLIDE1:type SLIDE2:type ... --content JSON [--music MUSIC_FILE] [--config CONFIG_FILE]
#
# Legacy Usage (still supported):
#   create_multi_slide_video_hume.sh DATE WORD SLIDE1 SLIDE2 SLIDE3 SLIDE4 SLIDE5 SLIDE_CONTENT_JSON [--music MUSIC_FILE]
#
# Required Arguments:
#   DATE - Date string (e.g., "2025-11-28")
#   WORD - Word being taught (e.g., "première")
#
# New Format:
#   --slides SLIDE_IMAGE:SLIDE_TYPE ...
#     SLIDE_IMAGE: Path to slide image
#     SLIDE_TYPE: waveform, definition, examples, mnemonic, quiz, cta, or static
#   --content JSON_STRING or --content-file JSON_FILE
#     JSON with slide content data
#
# Legacy Format (5 slides):
#   SLIDE1-SLIDE5: Paths to slide images (types inferred)
#   SLIDE_CONTENT_JSON: JSON array with slide content
#
# Optional Arguments:
#   --music MUSIC_FILE - Add background music with ducking and fade-out
#     MUSIC_FILE can be:
#       - "random" or "auto" : Automatically select from bg-music/ based on date seed
#       - Filename only: Search in bg-music/ directory (e.g., "la-vie-en-rose.mp3")
#       - Relative path: Resolve from script directory
#       - Absolute path: Use as-is
#   --config CONFIG_FILE - Load configuration from YAML file (defaults in config_manager.py)
#
# Environment Variables:
#   HUME_API_KEY - Your Hume API key (required)
#   HUME_FRENCH_VOICE - Voice name for French text (default: "claire")
#   HUME_ENGLISH_VOICE - Voice name for English text (default: "claire")
#
# Examples:
#   # Legacy (still works):
#   ./create_multi_slide_video_hume.sh "2025-11-28" "première" "$S1" "$S2" "$S3" "$S4" "$S5" "$JSON"
#
#   # New flexible format (3 slides):
#   ./create_multi_slide_video_hume.sh "2025-11-28" "première" \\
#     --slides "$S1:waveform" "$S2:definition" "$S3:cta" \\
#     --content "$JSON"
#
#   # With music and config:
#   ./create_multi_slide_video_hume.sh "2025-11-28" "première" \\
#     --slides "$S1:waveform" "$S2:definition" "$S3:examples" "$S4:cta" \\
#     --content "$JSON" --music random --config config.yaml
#
#   # With specific music file from bg-music directory:
#   ./create_multi_slide_video_hume.sh "2025-11-28" "première" \\
#     --slides "$S1:waveform" "$S2:definition" "$S3:cta" \\
#     --content "$JSON" --music la-vie-en-rose.mp3

# Detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/utils"

# Initialize configuration
CONFIG_FILE=""
if [ -f "${SCRIPT_DIR}/config.yaml" ]; then
  CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
fi

# Parse configuration helper
get_config() {
  local key="$1"
  local default="${2:-}"
  if [ -f "${UTILS_DIR}/config_manager.py" ] && [ -n "$CONFIG_FILE" ]; then
    python3 "${UTILS_DIR}/config_manager.py" "$CONFIG_FILE" "$key" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

# Trap for cleanup on exit
TMP_DIR=""
cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

# Dependency validation
validate_dependencies() {
  local missing=()
  for cmd in ffmpeg ffprobe python3 magick bc; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo "Error: Missing required dependencies: ${missing[*]}" >&2
    echo "Please install: ffmpeg, ffprobe, python3, ImageMagick (magick), bc" >&2
    exit 1
  fi
  
  # Check Python packages
  if ! python3 -c "import hume" 2>/dev/null; then
    echo "Error: Python 'hume' package not found" >&2
    echo "Install with: pip install hume" >&2
    exit 1
  fi
}

# Validate dependencies early
validate_dependencies

# Initialize arrays for slide data
declare -a SLIDE_IMAGES
declare -a SLIDE_TYPES
SLIDE_CONTENT_JSON=""
MUSIC_FILE=""
LEGACY_MODE=false

# Parse arguments
if [ $# -lt 2 ]; then
  echo "Usage: $(basename "$0") DATE WORD [--slides ...] [--content JSON | --content-file FILE] [--music FILE] [--config FILE]" >&2
  echo "   or: $(basename "$0") DATE WORD SLIDE1 SLIDE2 SLIDE3 SLIDE4 SLIDE5 CONTENT_JSON [--music FILE]" >&2
  exit 1
fi

DATE="$1"
WORD="$2"
shift 2

# Detect legacy vs new mode
if [ $# -ge 6 ] && [ "${1:0:2}" != "--" ]; then
  # Legacy mode: DATE WORD SLIDE1 SLIDE2 SLIDE3 SLIDE4 SLIDE5 JSON [--music FILE]
  LEGACY_MODE=true
  SLIDE_IMAGES=("$1" "$2" "$3" "$4" "$5")
  SLIDE_TYPES=("waveform" "definition" "examples" "mnemonic" "cta")
  SLIDE_CONTENT_JSON="$6"
  shift 6
  
  # Parse optional --music flag
  while [ $# -gt 0 ]; do
    case "$1" in
      --music)
        MUSIC_FILE="$2"
        shift 2
        ;;
      *)
        echo "Error: Unknown argument in legacy mode: $1" >&2
        exit 1
        ;;
    esac
  done
else
  # New mode: parse --slides, --content, etc.
  while [ $# -gt 0 ]; do
    case "$1" in
      --slides)
        shift
        while [ $# -gt 0 ] && [ "${1:0:2}" != "--" ]; do
          # Parse SLIDE_PATH:TYPE
          if [[ "$1" == *":"* ]]; then
            SLIDE_IMAGES+=("${1%%:*}")
            SLIDE_TYPES+=("${1##*:}")
          else
            # No type specified, default to static
            SLIDE_IMAGES+=("$1")
            SLIDE_TYPES+=("static")
          fi
          shift
        done
        ;;
      --content)
        SLIDE_CONTENT_JSON="$2"
        shift 2
        ;;
      --content-file)
        if [ ! -f "$2" ]; then
          echo "Error: Content file not found: $2" >&2
          exit 1
        fi
        SLIDE_CONTENT_JSON=$(cat "$2")
        shift 2
        ;;
      --music)
        MUSIC_FILE="$2"
        shift 2
        ;;
      --config)
        CONFIG_FILE="$2"
        if [ ! -f "$CONFIG_FILE" ]; then
          echo "Error: Config file not found: $CONFIG_FILE" >&2
          exit 1
        fi
        shift 2
        ;;
      *)
        echo "Error: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done
fi

# Validation
if [ ${#SLIDE_IMAGES[@]} -eq 0 ]; then
  echo "Error: No slides specified" >&2
  exit 1
fi

if [ ${#SLIDE_IMAGES[@]} -ne ${#SLIDE_TYPES[@]} ]; then
  echo "Error: Slide count mismatch (${#SLIDE_IMAGES[@]} images, ${#SLIDE_TYPES[@]} types)" >&2
  exit 1
fi

for i in "${!SLIDE_IMAGES[@]}"; do
  if [ ! -f "${SLIDE_IMAGES[$i]}" ]; then
    echo "Error: Slide image not found: ${SLIDE_IMAGES[$i]}" >&2
    exit 1
  fi
done

if [ -z "$SLIDE_CONTENT_JSON" ]; then
  echo "Error: No slide content provided" >&2
  exit 1
fi

# Check for API key
if [ -z "${HUME_API_KEY:-}" ]; then
  echo "Error: HUME_API_KEY environment variable is required" >&2
  exit 1
fi

# Load configuration or use defaults
HUME_FRENCH_VOICE="${HUME_FRENCH_VOICE:-$(get_config 'tts.french_voice' 'claire')}"
HUME_ENGLISH_VOICE="${HUME_ENGLISH_VOICE:-$(get_config 'tts.english_voice' 'claire')}"
OUTPUT_BASE="$(get_config 'paths.output_base' '/Users/jupiter/dev/woodshed/images/languageacademy/socials')"

# Set PATH for homebrew binaries
HOMEBREW_BIN="$(get_config 'paths.homebrew_bin' '/opt/homebrew/bin')"
LOCAL_BIN="$(get_config 'paths.local_bin' '/usr/local/bin')"
export PATH="${HOMEBREW_BIN}:${LOCAL_BIN}:$PATH"

# Convert word to slug using helper
to_slug() {
  local str="$1"
  if [ -f "${UTILS_DIR}/slug_helper.py" ]; then
    python3 "${UTILS_DIR}/slug_helper.py" "$str" 2>/dev/null || echo "slide"
  else
    # Fallback to basic slug
    echo "$str" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/-\+/-/g' | sed 's/^-\|-$//g' || echo "slide"
  fi
}

WORD_SLUG=$(to_slug "$WORD")

# Function to select random music based on date seed
select_random_music() {
  local date="$1"
  local music_dir="${SCRIPT_DIR}/bg-music"
  
  if [ ! -d "$music_dir" ]; then
    echo "" # No music directory, return empty
    return
  fi
  
  # Get list of music files
  local -a music_files=()
  while IFS= read -r -d '' file; do
    music_files+=("$file")
  done < <(find "$music_dir" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.m4a" -o -name "*.ogg" \) -print0 2>/dev/null | sort -z)
  
  if [ ${#music_files[@]} -eq 0 ]; then
    echo "" # No music files found
    return
  fi
  
  # Convert date to seed (e.g., "2025-11-28" -> numeric seed)
  # Remove hyphens and use as seed
  local seed="${date//-/}"
  seed=$(echo "$seed" | sed 's/[^0-9]//g') # Keep only numbers
  
  if [ -z "$seed" ]; then
    seed=1
  fi
  
  # Select index based on seed
  local index=$((seed % ${#music_files[@]}))
  
  echo "${music_files[$index]}"
}

# Resolve music file path
if [ -n "$MUSIC_FILE" ]; then
  # Check for special keywords
  if [ "$MUSIC_FILE" = "random" ] || [ "$MUSIC_FILE" = "auto" ]; then
    # Auto-select based on date
    MUSIC_FILE=$(select_random_music "$DATE")
    if [ -n "$MUSIC_FILE" ]; then
      echo "Auto-selected music: $(basename "$MUSIC_FILE")" >&2
    else
      echo "Warning: No music files found in bg-music directory" >&2
      MUSIC_FILE=""
    fi
  else
    # Explicit file specified
    if [ ! -f "$MUSIC_FILE" ] && [ "${MUSIC_FILE#/}" = "$MUSIC_FILE" ]; then
      # Try relative to script directory
      MUSIC_FILE="${SCRIPT_DIR}/${MUSIC_FILE}"
    fi
    if [ ! -f "$MUSIC_FILE" ]; then
      # Try in bg-music directory
      if [ -f "${SCRIPT_DIR}/bg-music/${MUSIC_FILE}" ]; then
        MUSIC_FILE="${SCRIPT_DIR}/bg-music/${MUSIC_FILE}"
      else
        echo "Error: Music file not found: $MUSIC_FILE" >&2
        exit 1
      fi
    fi
  fi
fi

# Create directories with incremental naming
BASE_DIR="${OUTPUT_BASE}/${DATE}-${WORD_SLUG}"
VIDEO_BASE_DIR="${BASE_DIR}/video"
VIDEO_DIR="$VIDEO_BASE_DIR"
counter=1

if [ -d "$VIDEO_BASE_DIR" ] 2>/dev/null; then
  while [ -d "${VIDEO_BASE_DIR}-${counter}" ] 2>/dev/null; do
    ((counter++))
  done
  VIDEO_DIR="${VIDEO_BASE_DIR}-${counter}"
fi

SLIDES_DIR="${VIDEO_DIR}/slides"
AUDIO_DIR="${BASE_DIR}/audio"
mkdir -p "$VIDEO_DIR" "$SLIDES_DIR" "$AUDIO_DIR"

TMP_DIR="/tmp/multi-slide-hume-$$"
mkdir -p "$TMP_DIR"

# Auto-detect video dimensions from first slide
VIDEO_WIDTH=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width -of csv=p=0 "${SLIDE_IMAGES[0]}" 2>&1 | head -1)
VIDEO_HEIGHT=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=height -of csv=p=0 "${SLIDE_IMAGES[0]}" 2>&1 | head -1)

if [ -z "$VIDEO_WIDTH" ] || [ -z "$VIDEO_HEIGHT" ] || [ "$VIDEO_WIDTH" = "N/A" ] || [ "$VIDEO_HEIGHT" = "N/A" ]; then
  VIDEO_WIDTH=$(get_config 'video.default_width' '1080')
  VIDEO_HEIGHT=$(get_config 'video.default_height' '1920')
  echo "Warning: Could not detect dimensions, using ${VIDEO_WIDTH}x${VIDEO_HEIGHT}" >&2
else
  echo "Detected video dimensions: ${VIDEO_WIDTH}x${VIDEO_HEIGHT}" >&2
fi

# Function to generate audio with Hume Python SDK
generate_audio() {
  local voice_id="$1"
  local text="$2"
  local output_file="$3"
  local language="${4:-en}"
  
  if [ -z "$voice_id" ]; then
    if [ "$language" = "fr" ]; then
      voice_id="$HUME_FRENCH_VOICE"
    else
      voice_id="$HUME_ENGLISH_VOICE"
    fi
  fi
  
  if [ -z "$voice_id" ]; then
    echo "Error: Voice ID not specified" >&2
    return 1
  fi
  
  # Use Python SDK helper script
  if [ -f "$SCRIPT_DIR/venv/bin/python3" ]; then
    "$SCRIPT_DIR/venv/bin/python3" "$SCRIPT_DIR/hume_tts.py" "$text" "$voice_id" "$output_file" || {
      echo "Failed to generate audio with Hume SDK" >&2
      return 1
    }
  else
    python3 "$SCRIPT_DIR/hume_tts.py" "$text" "$voice_id" "$output_file" || {
      echo "Failed to generate audio with Hume SDK" >&2
      return 1
    }
  fi
}

# Function to add silence padding
add_silence_padding() {
  local input_audio="$1"
  local output_audio="$2"
  local add_leading="${3:-false}"
  
  local sample_rate=$(ffprobe -v quiet -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$input_audio" 2>&1 | head -1)
  if [ -z "$sample_rate" ] || [ "$sample_rate" = "N/A" ]; then
    sample_rate=$(get_config 'audio.sample_rate' '48000')
  fi
  
  local channels=$(ffprobe -v quiet -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$input_audio" 2>&1 | head -1)
  channels=$(echo "$channels" | sed 's/[^0-9]//g')
  if [ -z "$channels" ] || [ "$channels" = "0" ]; then
    channels=1
  fi
  
  local channel_layout="mono"
  if [ "$channels" -ge 2 ]; then
    channel_layout="stereo"
  fi
  
  local trailing_silence=$(get_config 'audio.trailing_silence' '1.0')
  local leading_silence=$(get_config 'audio.leading_silence' '0.15')
  
  if [ "$add_leading" = "true" ]; then
    ffmpeg -y \
      -i "$input_audio" \
      -f lavfi -i "anullsrc=r=${sample_rate}:cl=${channel_layout}:d=${trailing_silence}" \
      -f lavfi -i "anullsrc=r=${sample_rate}:cl=${channel_layout}:d=${leading_silence}" \
      -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1" \
      "$output_audio" 2>&1 || { echo "Failed to add silence padding" >&2; return 1; }
  else
    ffmpeg -y \
      -i "$input_audio" \
      -f lavfi -i "anullsrc=r=${sample_rate}:cl=${channel_layout}:d=${trailing_silence}" \
      -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" \
      "$output_audio" 2>&1 || { echo "Failed to add silence padding" >&2; return 1; }
  fi
}

# Function to create waveform video
create_waveform_video() {
  local image="$1"
  local audio="$2"
  local output="$3"
  
  local color=$(python3 "$SCRIPT_DIR/calculate_contrast_color.py" "$image" 2>&1 | tail -1)
  if [ -z "$color" ]; then
    echo "Failed to calculate contrast color, using default" >&2
    color="#00FFFF"
  fi
  
  local padded_audio="${TMP_DIR}/padded-audio-waveform-$(basename "$output").wav"
  add_silence_padding "$audio" "$padded_audio" "false" || { echo "Failed to add silence padding" >&2; return 1; }
  
  local duration=$(ffprobe -i "$padded_audio" -show_entries format=duration -v quiet -of csv="p=0" 2>&1 | head -1)
  if [ -z "$duration" ] || [ "$duration" = "N/A" ]; then
    echo "Failed to get audio duration" >&2
    return 1
  fi
  
  local waveform_height_pct=$(get_config 'waveform.height_percent' '30')
  local bass_rolloff=$(get_config 'waveform.bass_rolloff' '80')
  local waveform_alpha=$(get_config 'waveform.alpha' '0.65')
  local video_bitrate=$(get_config 'video.video_bitrate' '4000k')
  local audio_bitrate=$(get_config 'video.audio_bitrate' '192k')
  local preset=$(get_config 'video.preset' 'medium')
  
  local waveform_height=$((VIDEO_HEIGHT * waveform_height_pct / 100))
  local waveform_y=$((VIDEO_HEIGHT - waveform_height))
  
  ffmpeg -y -loop 1 -i "$image" -i "$padded_audio" \
    -filter_complex "[0:v]scale=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:force_original_aspect_ratio=decrease,pad=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=black[bg];[1:a]highpass=f=${bass_rolloff}[wave_audio];[wave_audio]showfreqs=s=${VIDEO_WIDTH}x${waveform_height}:mode=bar:colors=${color}:ascale=log,format=yuva420p,colorchannelmixer=aa=${waveform_alpha}[wave];[bg][wave]overlay=0:${waveform_y}[v];[1:a]pan=stereo|c0=c0|c1=c0[audio]" \
    -map "[v]" -map "[audio]" \
    -c:v libx264 -preset "$preset" -b:v "$video_bitrate" \
    -c:a aac -b:a "$audio_bitrate" \
    -t "$duration" \
    -pix_fmt yuv420p \
    -movflags +faststart \
    "$output" 2>&1 || { echo "FFmpeg failed for waveform video" >&2; return 1; }
}

# Function to create static video
create_static_video() {
  local image="$1"
  local audio="$2"
  local output="$3"
  
  local padded_audio="${TMP_DIR}/padded-audio-$(basename "$output").wav"
  add_silence_padding "$audio" "$padded_audio" "false" || { echo "Failed to add silence padding" >&2; return 1; }
  
  local duration=$(ffprobe -i "$padded_audio" -show_entries format=duration -v quiet -of csv="p=0" 2>&1 | head -1)
  if [ -z "$duration" ] || [ "$duration" = "N/A" ]; then
    echo "Failed to get audio duration" >&2
    return 1
  fi
  
  echo "Audio duration: $duration seconds" >&2
  
  local video_bitrate=$(get_config 'video.video_bitrate' '4000k')
  local audio_bitrate=$(get_config 'video.audio_bitrate' '192k')
  local preset=$(get_config 'video.preset' 'medium')
  local crf=$(get_config 'video.crf' '23')
  
  ffmpeg -y -loop 1 -i "$image" -i "$padded_audio" \
    -filter_complex "[0:v]scale=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:force_original_aspect_ratio=decrease,pad=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=black[bg];[1:a]pan=stereo|c0=c0|c1=c0[audio]" \
    -map "[bg]" -map "[audio]" \
    -c:v libx264 -preset "$preset" -crf "$crf" \
    -c:a aac -b:a "$audio_bitrate" \
    -t "$duration" \
    -pix_fmt yuv420p \
    -movflags +faststart \
    "$output" 2>&1 || { echo "FFmpeg failed for static video" >&2; return 1; }
}

# Slide processor functions
process_waveform_slide() {
  local slide_num="$1"
  local slide_image="$2"
  local slide_video="$3"
  
  local word_capitalized=$(echo "$WORD" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
  local slide_audio="${AUDIO_DIR}/${DATE}-${WORD_SLUG}-slide${slide_num}.wav"
  
  generate_audio "" "${word_capitalized}. ${word_capitalized}." "$slide_audio" "fr" || return 1
  create_waveform_video "$slide_image" "$slide_audio" "$slide_video" || return 1
}

process_definition_slide() {
  local slide_num="$1"
  local slide_image="$2"
  local slide_video="$3"
  
  # Use cached variable instead of parsing JSON again
  local slide_text="${SLIDE_CONTENT_SLIDE2:-}"
  
  if [ -z "$slide_text" ]; then
    echo "Warning: No definition text found" >&2
    slide_text="Definition"
  fi
  
  local slide_audio="${AUDIO_DIR}/${DATE}-${WORD_SLUG}-slide${slide_num}.wav"
  generate_audio "" "$slide_text" "$slide_audio" "en" || return 1
  create_static_video "$slide_image" "$slide_audio" "$slide_video" || return 1
}

process_examples_slide() {
  local slide_num="$1"
  local slide_image="$2"
  local slide_video="$3"
  
  local slide_audio="${AUDIO_DIR}/${DATE}-${WORD_SLUG}-slide${slide_num}.wav"
  local slide_temp_dir="${TMP_DIR}/slide${slide_num}"
  mkdir -p "$slide_temp_dir"
  
  local -a audio_segments=()
  local seg_counter=0
  local sample_rate=$(get_config 'audio.sample_rate' '48000')
  local pause_duration=$(get_config 'audio.pause_duration' '1.0')
  
  # Use cached variable instead of parsing JSON again
  if [ -n "${SLIDE_CONTENT_SLIDE3:-}" ]; then
    IFS='|' read -ra PARTS <<< "$SLIDE_CONTENT_SLIDE3"
    
    # Process examples dynamically (groups of 3: english, PAUSE, french)
    local example_num=0
    local i=0
    while [ $i -lt ${#PARTS[@]} ]; do
      if [ "${PARTS[$i]}" = "PAUSE" ]; then
        ((i++))
        continue
      fi
      
      # We have an example group: english, PAUSE, french
      if [ $((i + 2)) -lt ${#PARTS[@]} ]; then
        ((example_num++))
        local english="${PARTS[$i]}"
        local french="${PARTS[$((i + 2))]}"
        
        # Label
        generate_audio "" "Exemple ${example_num}:" "${slide_temp_dir}/ex${example_num}-label-${seg_counter}.wav" "fr" || return 1
        audio_segments+=("${slide_temp_dir}/ex${example_num}-label-${seg_counter}.wav")
        ((seg_counter++))
        
        # French first
        generate_audio "" "$french" "${slide_temp_dir}/fr${example_num}-${seg_counter}.wav" "fr" || return 1
        audio_segments+=("${slide_temp_dir}/fr${example_num}-${seg_counter}.wav")
        ((seg_counter++))
        
        # English
        generate_audio "" "$english" "${slide_temp_dir}/en${example_num}-${seg_counter}.wav" "en" || return 1
        audio_segments+=("${slide_temp_dir}/en${example_num}-${seg_counter}.wav")
        ((seg_counter++))
        
        # French repeat
        generate_audio "" "$french" "${slide_temp_dir}/fr${example_num}-repeat-${seg_counter}.wav" "fr" || return 1
        audio_segments+=("${slide_temp_dir}/fr${example_num}-repeat-${seg_counter}.wav")
        ((seg_counter++))
        
        # Pause
        ffmpeg -y -f lavfi -i "anullsrc=r=${sample_rate}:cl=mono:d=${pause_duration}" "${slide_temp_dir}/pause${example_num}-${seg_counter}.wav" 2>&1 || return 1
        audio_segments+=("${slide_temp_dir}/pause${example_num}-${seg_counter}.wav")
        ((seg_counter++))
        
        i=$((i + 3))
      else
        break
      fi
    done
  fi
  
  # Concatenate all audio segments
  if [ ${#audio_segments[@]} -gt 0 ]; then
    > "${TMP_DIR}/concat-list.txt"
    for segment in "${audio_segments[@]}"; do
      echo "file '$segment'" >> "${TMP_DIR}/concat-list.txt"
    done
    ffmpeg -y -f concat -safe 0 -i "${TMP_DIR}/concat-list.txt" -c:a pcm_s16le "$slide_audio" 2>&1 || return 1
  else
    ffmpeg -y -f lavfi -i "anullsrc=r=${sample_rate}:cl=mono:d=1" "$slide_audio" 2>&1 || return 1
  fi
  
  create_static_video "$slide_image" "$slide_audio" "$slide_video" || return 1
}

process_mnemonic_or_quiz_slide() {
  local slide_num="$1"
  local slide_image="$2"
  local slide_video="$3"
  
  # Use cached variables instead of parsing JSON again
  local slide_text="${SLIDE_CONTENT_SLIDE4:-}"
  local slide_lang="${SLIDE_CONTENT_SLIDE4_LANG:-en}"
  
  local slide_audio="${AUDIO_DIR}/${DATE}-${WORD_SLUG}-slide${slide_num}.wav"
  if [ -z "$slide_text" ]; then
    echo "Warning: No mnemonic/quiz text found" >&2
    local sample_rate=$(get_config 'audio.sample_rate' '48000')
    ffmpeg -y -f lavfi -i "anullsrc=r=${sample_rate}:cl=mono:d=1" "$slide_audio" 2>&1 || return 1
  else
    generate_audio "" "$slide_text" "$slide_audio" "$slide_lang" || return 1
  fi
  
  create_static_video "$slide_image" "$slide_audio" "$slide_video" || return 1
}

process_cta_slide() {
  local slide_num="$1"
  local slide_image="$2"
  local slide_video="$3"
  
  # Use cached variable instead of parsing JSON again
  local slide_text="${SLIDE_CONTENT_SLIDE5:-Merci beaucoup! Like, follow and share. Visit language academy dot io today!}"
  
  local slide_audio="${AUDIO_DIR}/${DATE}-${WORD_SLUG}-slide${slide_num}.wav"
  generate_audio "" "$slide_text" "$slide_audio" "en" || return 1
  create_static_video "$slide_image" "$slide_audio" "$slide_video" || return 1
}

process_static_slide() {
  local slide_num="$1"
  local slide_image="$2"
  local slide_video="$3"
  local slide_type="$4"
  
  echo "Warning: Static/unknown slide type '${slide_type}', creating silent video" >&2
  local slide_audio="${AUDIO_DIR}/${DATE}-${WORD_SLUG}-slide${slide_num}.wav"
  local sample_rate=$(get_config 'audio.sample_rate' '48000')
  ffmpeg -y -f lavfi -i "anullsrc=r=${sample_rate}:cl=mono:d=2" "$slide_audio" 2>&1 || return 1
  create_static_video "$slide_image" "$slide_audio" "$slide_video" || return 1
}

# Parse slide content once and cache to variables
if [ -f "${UTILS_DIR}/cache_slide_content.py" ]; then
  # Use new caching utility that exports shell variables
  eval "$(python3 "${UTILS_DIR}/cache_slide_content.py" "$SLIDE_CONTENT_JSON" 2>/dev/null)" || {
    echo "Warning: Failed to parse slide content with cache utility" >&2
    # Set empty defaults if parsing fails
    SLIDE_CONTENT_SLIDE2=""
    SLIDE_CONTENT_SLIDE3=""
    SLIDE_CONTENT_SLIDE4=""
    SLIDE_CONTENT_SLIDE4_LANG="en"
    SLIDE_CONTENT_SLIDE5="Merci beaucoup! Like, follow and share. Visit language academy dot io today!"
  }
elif [ -f "${UTILS_DIR}/parse_slide_content.py" ]; then
  # Fallback to old parsing method
  SLIDE_CONTENT_PARSED=$(python3 "${UTILS_DIR}/parse_slide_content.py" "$SLIDE_CONTENT_JSON" 2>/dev/null) || {
    echo "Warning: Failed to parse slide content with helper" >&2
    SLIDE_CONTENT_PARSED=""
  }
else
  echo "Warning: No slide content parser found, using defaults" >&2
  SLIDE_CONTENT_SLIDE2=""
  SLIDE_CONTENT_SLIDE3=""
  SLIDE_CONTENT_SLIDE4=""
  SLIDE_CONTENT_SLIDE4_LANG="en"
  SLIDE_CONTENT_SLIDE5="Merci beaucoup! Like, follow and share. Visit language academy dot io today!"
fi

# Process each slide
declare -a SLIDE_VIDEOS

for i in "${!SLIDE_IMAGES[@]}"; do
  slide_num=$((i + 1))
  slide_image="${SLIDE_IMAGES[$i]}"
  slide_type="${SLIDE_TYPES[$i]}"
  slide_video="${SLIDES_DIR}/${DATE}-${WORD_SLUG}-slide${slide_num}.mp4"
  
  echo "Processing slide ${slide_num} (${slide_type})..." >&2
  
  # Route to appropriate processor function
  case "$slide_type" in
    waveform)
      process_waveform_slide "$slide_num" "$slide_image" "$slide_video" || {
        echo "Failed to process slide ${slide_num}" >&2
        exit 1
      }
      ;;
    definition)
      process_definition_slide "$slide_num" "$slide_image" "$slide_video" || {
        echo "Failed to process slide ${slide_num}" >&2
        exit 1
      }
      ;;
    examples)
      process_examples_slide "$slide_num" "$slide_image" "$slide_video" || {
        echo "Failed to process slide ${slide_num}" >&2
        exit 1
      }
      ;;
    mnemonic|quiz)
      process_mnemonic_or_quiz_slide "$slide_num" "$slide_image" "$slide_video" || {
        echo "Failed to process slide ${slide_num}" >&2
        exit 1
      }
      ;;
    cta)
      process_cta_slide "$slide_num" "$slide_image" "$slide_video" || {
        echo "Failed to process slide ${slide_num}" >&2
        exit 1
      }
      ;;
    static|*)
      process_static_slide "$slide_num" "$slide_image" "$slide_video" "$slide_type" || {
        echo "Failed to process slide ${slide_num}" >&2
        exit 1
      }
      ;;
  esac
  
  SLIDE_VIDEOS+=("$slide_video")
  echo "Slide ${slide_num} complete" >&2
done

# Concatenate all slides
echo "Concatenating ${#SLIDE_VIDEOS[@]} slides into final video..." >&2
FINAL_VIDEO="${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume.mp4"

> "${TMP_DIR}/video-concat-list.txt"
for video in "${SLIDE_VIDEOS[@]}"; do
  echo "file '$video'" >> "${TMP_DIR}/video-concat-list.txt"
done

ffmpeg -y -f concat -safe 0 -i "${TMP_DIR}/video-concat-list.txt" \
  -c copy \
  -movflags +faststart \
  "$FINAL_VIDEO" 2>&1 || { echo "Failed to concatenate videos" >&2; exit 1; }

# Add background music if requested
if [ -n "$MUSIC_FILE" ]; then
  echo "Adding background music with ducking and fade-out..." >&2
  FINAL_VIDEO_WITH_MUSIC="${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume-with-music.mp4"
  
  DURATION=$(ffprobe -i "$FINAL_VIDEO" -show_entries format=duration -v quiet -of csv="p=0" 2>&1 | head -1)
  if [ -z "$DURATION" ] || [ "$DURATION" = "N/A" ]; then
    echo "Failed to get video duration" >&2
    exit 1
  fi
  
  music_volume=$(get_config 'music.volume' '0.15')
  fade_duration=$(get_config 'music.fade_duration' '3.0')
  FADE_START=$(echo "$DURATION - $fade_duration" | bc)
  
  # Sidechain compression: voice (0:a) ducks music, not compress the output
  # Music is sidechained by voice - when voice plays, music volume drops
  ffmpeg -y -i "$FINAL_VIDEO" -stream_loop -1 -i "$MUSIC_FILE" \
    -filter_complex "[1:a]volume=${music_volume},aloop=loop=-1:size=2e+09,afade=t=out:st=${FADE_START}:d=${fade_duration}[music];[music][0:a]sidechaincompress=threshold=0.02:ratio=8:attack=20:release=200[ducked];[0:a][ducked]amix=inputs=2:duration=first:dropout_transition=0[audio]" \
    -map 0:v -map "[audio]" \
    -c:v copy \
    -c:a aac -b:a 192k \
    -shortest \
    "$FINAL_VIDEO_WITH_MUSIC" 2>&1 || { echo "Failed to add background music" >&2; exit 1; }
  
  echo "Video with music created: $FINAL_VIDEO_WITH_MUSIC" >&2
  echo "Original video (without music): $FINAL_VIDEO" >&2
fi

# Output paths for n8n
if [ -n "$MUSIC_FILE" ] && [ -f "${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume-with-music.mp4" ]; then
  echo "${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume-with-music.mp4"
  echo "${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume.mp4"
else
  echo "$FINAL_VIDEO"
fi

# Save script for reproducibility
cp "${BASH_SOURCE[0]}" "${VIDEO_DIR}/script-used.sh"
echo "Script saved to: ${VIDEO_DIR}/script-used.sh" >&2

echo "Processing complete" >&2

