#!/usr/bin/env bash
set -euo pipefail

# Create video from 5 slides with appropriate audio for each using Hume voices
# Usage: create_multi_slide_video_hume.sh DATE WORD SLIDE1_IMAGE SLIDE2_IMAGE SLIDE3_IMAGE SLIDE4_IMAGE SLIDE5_IMAGE SLIDE_CONTENT_JSON [--music MUSIC_FILE]
#
# Required Arguments:
#   DATE - Date string (e.g., "2025-11-28")
#   WORD - Word being taught (e.g., "première")
#   SLIDE1_IMAGE - Path to slide 1 image (word with waveform)
#   SLIDE2_IMAGE - Path to slide 2 image (definition)
#   SLIDE3_IMAGE - Path to slide 3 image (examples)
#   SLIDE4_IMAGE - Path to slide 4 image (mnemonic)
#   SLIDE5_IMAGE - Path to slide 5 image (CTA)
#   SLIDE_CONTENT_JSON - JSON array with slide content data
#
# Optional Arguments:
#   --music MUSIC_FILE - Add background music with audio ducking and fade-out
#     MUSIC_FILE: Path to audio file (mp3, wav, etc.). Can be absolute or relative.
#                 Relative paths are resolved from the script directory.
#     When used:
#       - Creates both original video and video with music
#       - Music is mixed at 25% volume with compression-based ducking
#       - Music fades out over the last 3 seconds
#       - Outputs both file paths (with-music first, then original)
#
# Output Files:
#   Without --music:
#     - Creates: ${DATE}-${WORD_SLUG}-complete-hume.mp4
#     - Outputs: Path to the video file
#
#   With --music:
#     - Creates: ${DATE}-${WORD_SLUG}-complete-hume.mp4 (original, no music)
#     - Creates: ${DATE}-${WORD_SLUG}-complete-hume-with-music.mp4 (with background music)
#     - Outputs: Both paths (with-music first, then original)
#
# Setup:
#   1. Get your Hume API key from https://dev.hume.ai
#   2. Browse available voices at https://dev.hume.ai/docs/voice/overview
#   3. Set environment variables before running (optional, defaults to "claire"):
#      export HUME_API_KEY="your-api-key-here"
#      export HUME_FRENCH_VOICE="claire"  # or another voice name
#      export HUME_ENGLISH_VOICE="claire"  # or another voice name
#   Note: Uses Octave 2 (version "2") for TTS generation
#   Note: EVI4 is a conversational/interactive model - this script uses TTS (Octave 2)
#
# Environment Variables:
#   HUME_API_KEY - Your Hume API key (required)
#   HUME_FRENCH_VOICE - Voice name for French text (default: "claire")
#   HUME_ENGLISH_VOICE - Voice name for English text (default: "claire")
#   Use "default" to use account default voice
#
# Examples:
#   # Basic usage without music:
#   create_multi_slide_video_hume.sh "2025-11-28" "première" "$SLIDE1" "$SLIDE2" "$SLIDE3" "$SLIDE4" "$SLIDE5" "$SLIDE_JSON"
#
#   # With background music (relative path):
#   create_multi_slide_video_hume.sh "2025-11-28" "première" "$SLIDE1" "$SLIDE2" "$SLIDE3" "$SLIDE4" "$SLIDE5" "$SLIDE_JSON" --music music.mp3
#
#   # With background music (absolute path):
#   create_multi_slide_video_hume.sh "2025-11-28" "première" "$SLIDE1" "$SLIDE2" "$SLIDE3" "$SLIDE4" "$SLIDE5" "$SLIDE_JSON" --music /path/to/music.mp3

if [ $# -lt 8 ]; then
  echo "Usage: create_multi_slide_video_hume.sh DATE WORD SLIDE1 SLIDE2 SLIDE3 SLIDE4 SLIDE5 SLIDE_CONTENT_JSON [--music MUSIC_FILE]" >&2
  exit 1
fi

DATE="$1"
WORD="$2"
SLIDE1="$3"
SLIDE2="$4"
SLIDE3="$5"
SLIDE4="$6"
SLIDE5="$7"
SLIDE_CONTENT_JSON="$8"

# Set PATH for homebrew binaries
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="/Users/jupiter/dev/woodshed/tts/slides-to-video"

# Convert word to slug for filesystem-safe directory names
# This matches the toSlug function in html-to-image service
# Uses Python for accurate Unicode normalization (NFD) and diacritic removal
to_slug() {
  local str="$1"
  if [ -z "$str" ]; then
    echo "slide"
    return
  fi
  python3 <<EOF
import sys
import unicodedata
import re

str_val = '''$str'''
if not str_val:
    print("slide")
    sys.exit(0)

# Normalize to NFD (decompose accented characters)
str_val = unicodedata.normalize('NFD', str_val)
# Remove diacritics
str_val = ''.join(c for c in str_val if unicodedata.category(c) != 'Mn')
# Lowercase
str_val = str_val.lower()
# Remove special characters except word chars, spaces, hyphens
str_val = re.sub(r'[^\w\s-]', '', str_val)
# Replace spaces with hyphens
str_val = re.sub(r'\s+', '-', str_val)
# Collapse multiple hyphens
str_val = re.sub(r'-+', '-', str_val)
# Remove leading/trailing hyphens
str_val = str_val.strip('-')
print(str_val if str_val else "slide")
EOF
}

WORD_SLUG=$(to_slug "$WORD")

# Parse optional music parameter
MUSIC_FILE=""
if [ $# -ge 9 ] && [ "$9" = "--music" ]; then
  if [ $# -lt 10 ]; then
    echo "Error: --music requires a music file path" >&2
    exit 1
  fi
  MUSIC_FILE="${10}"
  # If relative path, try relative to script directory first
  if [ ! -f "$MUSIC_FILE" ] && [ "${MUSIC_FILE#/}" = "$MUSIC_FILE" ]; then
    MUSIC_FILE="${SCRIPT_DIR}/${MUSIC_FILE}"
  fi
  if [ ! -f "$MUSIC_FILE" ]; then
    echo "Error: Music file not found: ${10}" >&2
    exit 1
  fi
fi

# Check for API key
if [ -z "${HUME_API_KEY:-}" ]; then
  echo "Error: HUME_API_KEY environment variable is required" >&2
  exit 1
fi

# Hume voice configuration
# Use Claire voice for all text (French and English)
HUME_FRENCH_VOICE="${HUME_FRENCH_VOICE:-claire}"  # French voice name - using Claire
HUME_ENGLISH_VOICE="${HUME_ENGLISH_VOICE:-claire}"  # English voice name - using Claire (same as French)

# Create directories - increment video folder name, not parent folder
# Use slugged word for directory name (filesystem-safe), but keep original WORD for filenames/content
BASE_DIR="/Users/jupiter/dev/woodshed/images/languageacademy/socials/${DATE}-${WORD_SLUG}"
VIDEO_BASE_DIR="${BASE_DIR}/video"
VIDEO_DIR="$VIDEO_BASE_DIR"
counter=1

# Check if video directory exists and increment if needed
if [ -d "$VIDEO_BASE_DIR" ] 2>/dev/null; then
  # Video directory exists, start incrementing from 1
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

# Auto-detect video dimensions from first slide image
# This ensures videos match the slide aspect ratio (e.g., 1080x1920 for YouTube Shorts)
VIDEO_WIDTH=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width -of csv=p=0 "$SLIDE1" 2>&1 | head -1)
VIDEO_HEIGHT=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=height -of csv=p=0 "$SLIDE1" 2>&1 | head -1)

if [ -z "$VIDEO_WIDTH" ] || [ -z "$VIDEO_HEIGHT" ] || [ "$VIDEO_WIDTH" = "N/A" ] || [ "$VIDEO_HEIGHT" = "N/A" ]; then
  echo "Warning: Could not detect dimensions from slide 1, defaulting to 1080x1920" >&2
  VIDEO_WIDTH=1080
  VIDEO_HEIGHT=1920
else
  echo "Detected video dimensions: ${VIDEO_WIDTH}x${VIDEO_HEIGHT}" >&2
fi

# Function to generate audio with Hume Python SDK
generate_audio() {
  local voice_id="$1"
  local text="$2"
  local output_file="$3"
  local language="${4:-en}"  # "en" for English, "fr" for French
  
  # Select voice ID based on language if not provided
  if [ -z "$voice_id" ]; then
    if [ "$language" = "fr" ]; then
      voice_id="$HUME_FRENCH_VOICE"
    else
      voice_id="$HUME_ENGLISH_VOICE"
    fi
  fi
  
  if [ -z "$voice_id" ]; then
    echo "Error: Voice ID not specified. Set HUME_FRENCH_VOICE_ID or HUME_ENGLISH_VOICE_ID" >&2
    return 1
  fi
  
  # Use Python SDK helper script (use venv Python to ensure hume package is available)
  "$SCRIPT_DIR/venv/bin/python3" "$SCRIPT_DIR/hume_tts.py" "$text" "$voice_id" "$output_file" || {
    echo "Failed to generate audio with Hume SDK" >&2
    return 1
  }
}

# Function to add silence padding
# add_silence_padding input_audio output_audio [add_leading_silence]
# add_leading_silence: "true" to add 0.15s leading silence, "false" or unset for no leading silence
# Always adds 1s trailing silence
add_silence_padding() {
  local input_audio="$1"
  local output_audio="$2"
  local add_leading="${3:-false}"
  
  # Get sample rate and channel layout from input audio to match silence padding
  local sample_rate=$(ffprobe -v quiet -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$input_audio" 2>&1 | head -1)
  if [ -z "$sample_rate" ] || [ "$sample_rate" = "N/A" ]; then
    sample_rate=48000  # Default to 48kHz (Hume's typical output)
  fi
  
  # Detect channel count from input audio (more reliable than channel_layout)
  local channels=$(ffprobe -v quiet -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$input_audio" 2>&1 | head -1)
  # Normalize channel count to integer
  channels=$(echo "$channels" | sed 's/[^0-9]//g')
  if [ -z "$channels" ] || [ "$channels" = "0" ]; then
    channels=1  # Default to mono
  fi
  
  # Set channel layout based on channel count (anullsrc accepts "mono" or "stereo")
  local channel_layout="mono"
  if [ "$channels" -ge 2 ]; then
    channel_layout="stereo"
  fi
  
  if [ "$add_leading" = "true" ]; then
    # Add 0.15s leading + 1s trailing (matching input sample rate and channel layout)
    # Put audio first to preserve its format, then trailing, then leading silence
    ffmpeg -y \
      -i "$input_audio" \
      -f lavfi -i "anullsrc=r=${sample_rate}:cl=${channel_layout}:d=1" \
      -f lavfi -i "anullsrc=r=${sample_rate}:cl=${channel_layout}:d=0.15" \
      -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1" \
      "$output_audio" 2>&1 || { echo "Failed to add silence padding" >&2; return 1; }
  else
    # Only add 1s trailing (matching input sample rate and channel layout)
    ffmpeg -y \
      -i "$input_audio" \
      -f lavfi -i "anullsrc=r=${sample_rate}:cl=${channel_layout}:d=1" \
      -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" \
      "$output_audio" 2>&1 || { echo "Failed to add silence padding" >&2; return 1; }
  fi
}

# Function to create waveform video (for slide 1)
# Uses same audio processing as other slides, only adds waveform visualization
create_waveform_video() {
  local image="$1"
  local audio="$2"
  local output="$3"
  
  # Auto-calculate contrasting color
  local color=$(python3 "$SCRIPT_DIR/calculate_contrast_color.py" "$image" 2>&1 | tail -1)
  if [ -z "$color" ]; then
    echo "Failed to calculate contrast color" >&2
    return 1
  fi
  
  # Create padded audio with unique name (same as other slides - no leading silence)
  local padded_audio="${TMP_DIR}/padded-audio-slide1.wav"
  add_silence_padding "$audio" "$padded_audio" "false" || { echo "Failed to add silence padding for slide 1" >&2; return 1; }
  
  # Get audio duration (same as static video)
  local duration=$(ffprobe -i "$padded_audio" -show_entries format=duration -v quiet -of csv="p=0" 2>&1 | head -1)
  if [ -z "$duration" ] || [ "$duration" = "N/A" ]; then
    echo "Failed to get audio duration for $padded_audio" >&2
    return 1
  fi
  
  # Generate waveform video - apply bass roll-off to waveform visualization only
  # Use detected dimensions, scale waveform height proportionally (30% of video height)
  # Position waveform at the bottom of the video
  WAVEFORM_HEIGHT=$((VIDEO_HEIGHT * 30 / 100))
  WAVEFORM_Y=$((VIDEO_HEIGHT - WAVEFORM_HEIGHT))
  ffmpeg -y -loop 1 -i "$image" -i "$padded_audio" \
    -filter_complex "[0:v]scale=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:force_original_aspect_ratio=decrease,pad=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=black[bg];[1:a]highpass=f=80[wave_audio];[wave_audio]showfreqs=s=${VIDEO_WIDTH}x${WAVEFORM_HEIGHT}:mode=bar:colors=${color}:ascale=log,format=yuva420p,colorchannelmixer=aa=0.65[wave];[bg][wave]overlay=0:${WAVEFORM_Y}[v];[1:a]pan=stereo|c0=c0|c1=c0[audio]" \
    -map "[v]" -map "[audio]" \
    -c:v libx264 -preset medium -b:v 4000k \
    -c:a aac -b:a 192k \
    -t "$duration" \
    -pix_fmt yuv420p \
    -movflags +faststart \
    "$output" 2>&1 || { echo "FFmpeg failed for waveform video" >&2; return 1; }
}

# Function to create static video (for slides 2-5)
create_static_video() {
  local image="$1"
  local audio="$2"
  local output="$3"
  
  # Create padded audio with unique name based on output filename
  # Slides 2-5 should NOT have leading silence
  local output_basename=$(basename "$output")
  local slide_num="${output_basename//[^0-9]/}"
  local padded_audio="${TMP_DIR}/padded-audio-${slide_num}.wav"
  add_silence_padding "$audio" "$padded_audio" "false" || { echo "Failed to add silence padding" >&2; return 1; }
  
  # Get EXACT audio duration (with higher precision)
  local duration=$(ffprobe -i "$padded_audio" -show_entries format=duration -v quiet -of csv="p=0" 2>&1 | head -1)
  if [ -z "$duration" ] || [ "$duration" = "N/A" ]; then
    echo "Failed to get audio duration for $padded_audio" >&2
    return 1
  fi
  
  echo "Audio duration: $duration seconds" >&2
  
  # Create static video - use exact duration to match audio precisely
  # Pan mono audio fully left and right in stereo
  # Use detected dimensions, scale and pad to maintain aspect ratio
  ffmpeg -y -loop 1 -i "$image" -i "$padded_audio" \
    -filter_complex "[0:v]scale=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:force_original_aspect_ratio=decrease,pad=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=black[bg];[1:a]pan=stereo|c0=c0|c1=c0[audio]" \
    -map "[bg]" -map "[audio]" \
    -c:v libx264 -preset medium -crf 23 \
    -c:a aac -b:a 192k \
    -t "$duration" \
    -pix_fmt yuv420p \
    -movflags +faststart \
    "$output" 2>&1 || { echo "FFmpeg failed for static video" >&2; return 1; }
  
  # Verify the output video duration matches audio
  local output_duration=$(ffprobe -i "$output" -show_entries format=duration -v quiet -of csv="p=0" 2>&1 | head -1)
  echo "Output video duration: $output_duration seconds (audio was: $duration)" >&2
}

# Parse slide content JSON (using python for JSON parsing)
parse_slide_content() {
  python3 <<EOF
import json
import sys

json_str = '''$SLIDE_CONTENT_JSON'''
data = json.loads(json_str)

# Slide 2: definition - just English translation
slide2_text = ""
for slide in data:
    if slide.get("type") == "definition":
        slide2_text = slide.get("translation", "")
        break

# Slide 3: examples - English first, pause, then French, repeat
slide3_parts = []
for slide in data:
    if slide.get("type") == "examples":
        examples = slide.get("examples", [])
        for ex in examples:
            slide3_parts.append(ex.get("english", ""))
            slide3_parts.append("PAUSE")
            slide3_parts.append(ex.get("french", ""))
        break

# Slide 4: mnemonic or quiz - variable format
# Mnemonic: hook + connection + reinforcement (English)
# Quiz: question text (French)
slide4_text = ""
slide4_language = "en"  # Default to English
for slide in data:
    if slide.get("type") == "mnemonic":
        engagement = slide.get("engagement", {})
        hook = engagement.get("hook", "").replace("'", "")
        connection = engagement.get("connection", "").replace("'", "")
        reinforcement = engagement.get("reinforcement", "").replace("'", "").replace("=", " means ")
        parts = [p for p in [hook, connection, reinforcement] if p]
        slide4_text = ". ".join(parts)
        slide4_language = "en"  # Mnemonic is English
        break
    elif slide.get("type") == "quiz":
        engagement = slide.get("engagement", {})
        question = engagement.get("question", "")
        options = engagement.get("options", [])
        
        # Replace underscores (blank) of variable length with "Blank" (English)
        import re
        question = re.sub(r'_+', ' Blank ', question)
        question = re.sub(r'\s+', ' ', question).strip()  # Normalize whitespace
        # Remove trailing punctuation to avoid double periods when joining
        question = question.rstrip('.!?')
        
        # Build quiz text: question (French) + options (labeled A/B/C/D, options in French) + prompt (English)
        parts = [question]
        
        # Add each option with label (A, B, C, D) - options read in French
        option_labels = ["A", "B", "C", "D"]
        for i, option in enumerate(options):
            if i < len(option_labels):
                parts.append(f"{option_labels[i]}): {option}")
        
        # Add "Comment your response below!" at the end (English)
        parts.append("Comment your response below!")
        
        slide4_text = ". ".join(parts)
        slide4_language = "fr"  # Quiz is primarily French (options are French words)
        break

# Slide 5: CTA - merci beaucoup! like, follow and share. Visit language academy dot io today!
slide5_text = "Merci beaucoup! Like, follow and share. Visit language academy dot io today!"

# Output as JSON for bash to parse
output = {
    "slide2": slide2_text,
    "slide3": slide3_parts,
    "slide4": slide4_text,
    "slide4_language": slide4_language,
    "slide5": slide5_text
}
print(json.dumps(output))
EOF
}

# Generate audio and videos for each slide

echo "Processing slide 1 (word with waveform)..." >&2
# Slide 1: Word pronunciation (French, with waveform) - capitalize first letter with periods
WORD_CAPITALIZED=$(echo "$WORD" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
SLIDE1_AUDIO="${AUDIO_DIR}/${DATE}-${WORD_SLUG}-slide1.wav"
generate_audio "" "${WORD_CAPITALIZED}. ${WORD_CAPITALIZED}." "$SLIDE1_AUDIO" "fr" || { echo "Failed to generate slide 1 audio" >&2; exit 1; }
SLIDE1_VIDEO="${SLIDES_DIR}/${DATE}-${WORD_SLUG}-slide1.mp4"
create_waveform_video "$SLIDE1" "$SLIDE1_AUDIO" "$SLIDE1_VIDEO" || { echo "Failed to create slide 1 video" >&2; exit 1; }

echo "Processing slide 2 (definition)..." >&2
# Slide 2: Definition - English only
SLIDE_CONTENT=$(parse_slide_content) || { echo "Failed to parse slide content" >&2; exit 1; }
SLIDE2_TEXT=$(echo "$SLIDE_CONTENT" | python3 -c "import sys, json; print(json.load(sys.stdin)['slide2'])") || { echo "Failed to extract slide 2 text" >&2; exit 1; }
echo "Slide 2 text: $SLIDE2_TEXT" >&2
SLIDE2_AUDIO="${TMP_DIR}/slide2-audio.wav"
echo "Generating slide 2 audio..." >&2
generate_audio "" "$SLIDE2_TEXT" "$SLIDE2_AUDIO" "en" || { echo "Failed to generate slide 2 audio" >&2; exit 1; }
echo "Creating slide 2 video..." >&2
SLIDE2_VIDEO="${SLIDES_DIR}/${DATE}-${WORD_SLUG}-slide2.mp4"
create_static_video "$SLIDE2" "$SLIDE2_AUDIO" "$SLIDE2_VIDEO" || { echo "Failed to create slide 2 video" >&2; exit 1; }
echo "Slide 2 complete" >&2

echo "Processing slide 3 (examples)..." >&2
# Slide 3: French sentence, then English, then French again, then pause, then example 2, then pause
SLIDE3_EXAMPLES=$(echo "$SLIDE_CONTENT" | python3 -c "import sys, json; examples = json.load(sys.stdin)['slide3']; print('|'.join(examples))") || { echo "Failed to extract slide 3 examples" >&2; exit 1; }
SLIDE3_AUDIO="${TMP_DIR}/slide3-audio.wav"
SLIDE3_TEMP_DIR="${TMP_DIR}/slide3"
mkdir -p "$SLIDE3_TEMP_DIR"

AUDIO_SEGMENTS=()
counter=0

# Parse parts: format is "ENGLISH|PAUSE|FRENCH|ENGLISH|PAUSE|FRENCH"
IFS='|' read -ra PARTS <<< "$SLIDE3_EXAMPLES"

# Example 1: "Exemple 1" -> French (index 2) -> English (index 0) -> French again (index 2) -> PAUSE
if [ ${#PARTS[@]} -ge 3 ]; then
  # "Exemple 1" label
  generate_audio "" "Exemple 1:" "${SLIDE3_TEMP_DIR}/example1-label-${counter}.wav" "fr" || { echo "Failed to generate Example 1 label" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/example1-label-${counter}.wav")
  ((counter++))
  # French first
  generate_audio "" "${PARTS[2]}" "${SLIDE3_TEMP_DIR}/fr1-${counter}.wav" "fr" || { echo "Failed to generate French audio for example 1" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/fr1-${counter}.wav")
  ((counter++))
  # English
  generate_audio "" "${PARTS[0]}" "${SLIDE3_TEMP_DIR}/en1-${counter}.wav" "en" || { echo "Failed to generate English audio for example 1" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/en1-${counter}.wav")
  ((counter++))
  # French again
  generate_audio "" "${PARTS[2]}" "${SLIDE3_TEMP_DIR}/fr1-repeat-${counter}.wav" "fr" || { echo "Failed to generate French repeat audio for example 1" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/fr1-repeat-${counter}.wav")
  ((counter++))
  # PAUSE (matching Hume audio sample rate: 48kHz)
  ffmpeg -y -f lavfi -i anullsrc=r=48000:cl=mono:d=1 "${SLIDE3_TEMP_DIR}/pause1-${counter}.wav" 2>&1 || { echo "Failed to create pause audio" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/pause1-${counter}.wav")
  ((counter++))
fi

# Example 2: "Exemple 2" -> French (index 5) -> English (index 3) -> French again (index 5) -> PAUSE
if [ ${#PARTS[@]} -ge 6 ]; then
  # "Exemple 2" label
  generate_audio "" "Exemple 2:" "${SLIDE3_TEMP_DIR}/example2-label-${counter}.wav" "fr" || { echo "Failed to generate Example 2 label" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/example2-label-${counter}.wav")
  ((counter++))
  # French first
  generate_audio "" "${PARTS[5]}" "${SLIDE3_TEMP_DIR}/fr2-${counter}.wav" "fr" || { echo "Failed to generate French audio for example 2" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/fr2-${counter}.wav")
  ((counter++))
  # English
  generate_audio "" "${PARTS[3]}" "${SLIDE3_TEMP_DIR}/en2-${counter}.wav" "en" || { echo "Failed to generate English audio for example 2" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/en2-${counter}.wav")
  ((counter++))
  # French again
  generate_audio "" "${PARTS[5]}" "${SLIDE3_TEMP_DIR}/fr2-repeat-${counter}.wav" "fr" || { echo "Failed to generate French repeat audio for example 2" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/fr2-repeat-${counter}.wav")
  ((counter++))
  # PAUSE (matching Hume audio sample rate: 48kHz)
  ffmpeg -y -f lavfi -i anullsrc=r=48000:cl=mono:d=1 "${SLIDE3_TEMP_DIR}/pause2-${counter}.wav" 2>&1 || { echo "Failed to create pause audio" >&2; exit 1; }
  AUDIO_SEGMENTS+=("${SLIDE3_TEMP_DIR}/pause2-${counter}.wav")
fi

# Concatenate all audio segments (re-encode to smooth transitions and prevent artifacts)
if [ ${#AUDIO_SEGMENTS[@]} -gt 0 ]; then
  > "${TMP_DIR}/concat-list.txt"  # Create/clear file
  for segment in "${AUDIO_SEGMENTS[@]}"; do
    echo "file '$segment'" >> "${TMP_DIR}/concat-list.txt"
  done
  # Re-encode instead of copy to smooth transitions
  ffmpeg -y -f concat -safe 0 -i "${TMP_DIR}/concat-list.txt" \
    -c:a pcm_s16le \
    "$SLIDE3_AUDIO" 2>&1 || { echo "Failed to concatenate slide 3 audio" >&2; exit 1; }
else
  # Fallback: create empty audio if no segments (matching Hume audio sample rate: 48kHz)
  ffmpeg -y -f lavfi -i anullsrc=r=48000:cl=mono:d=1 "$SLIDE3_AUDIO" 2>&1 || { echo "Failed to create fallback audio" >&2; exit 1; }
fi
SLIDE3_VIDEO="${SLIDES_DIR}/${DATE}-${WORD_SLUG}-slide3.mp4"
create_static_video "$SLIDE3" "$SLIDE3_AUDIO" "$SLIDE3_VIDEO" || { echo "Failed to create slide 3 video" >&2; exit 1; }

# Always generate slides 4 and 5 with Hume voices (don't use existing Piper-generated videos)
SLIDE4_VIDEO="${SLIDES_DIR}/${DATE}-${WORD_SLUG}-slide4.mp4"
SLIDE5_VIDEO="${SLIDES_DIR}/${DATE}-${WORD_SLUG}-slide5.mp4"

echo "Processing slide 4 (mnemonic/quiz)..." >&2
# Slide 4: Mnemonic (English) or Quiz (French) - variable format
SLIDE4_TEXT=$(echo "$SLIDE_CONTENT" | python3 -c "import sys, json; print(json.load(sys.stdin)['slide4'])") || { echo "Failed to extract slide 4 text" >&2; exit 1; }
SLIDE4_LANGUAGE=$(echo "$SLIDE_CONTENT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('slide4_language', 'en'))") || { echo "Failed to extract slide 4 language" >&2; exit 1; }
if [ -z "$SLIDE4_TEXT" ]; then
  echo "Warning: Slide 4 text is empty, skipping audio generation" >&2
  # Create empty audio file as fallback
  SLIDE4_AUDIO="${TMP_DIR}/slide4-audio.wav"
  ffmpeg -y -f lavfi -i anullsrc=r=48000:cl=mono:d=1 "$SLIDE4_AUDIO" 2>&1 || { echo "Failed to create fallback audio" >&2; exit 1; }
else
  SLIDE4_AUDIO="${TMP_DIR}/slide4-audio.wav"
  generate_audio "" "$SLIDE4_TEXT" "$SLIDE4_AUDIO" "$SLIDE4_LANGUAGE" || { echo "Failed to generate slide 4 audio" >&2; exit 1; }
fi
create_static_video "$SLIDE4" "$SLIDE4_AUDIO" "$SLIDE4_VIDEO" || { echo "Failed to create slide 4 video" >&2; exit 1; }

echo "Processing slide 5 (CTA)..." >&2
# Slide 5: CTA - English
SLIDE5_TEXT=$(echo "$SLIDE_CONTENT" | python3 -c "import sys, json; print(json.load(sys.stdin)['slide5'])") || { echo "Failed to extract slide 5 text" >&2; exit 1; }
SLIDE5_AUDIO="${TMP_DIR}/slide5-audio.wav"
generate_audio "" "$SLIDE5_TEXT" "$SLIDE5_AUDIO" "en" || { echo "Failed to generate slide 5 audio" >&2; exit 1; }
create_static_video "$SLIDE5" "$SLIDE5_AUDIO" "$SLIDE5_VIDEO" || { echo "Failed to create slide 5 video" >&2; exit 1; }

echo "Concatenating all slides into final video..." >&2
# Final video filename (no incrementing needed since video folder is already incremented)
FINAL_VIDEO="${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume.mp4"

# Simple concat: get duration, add slide, add next at offset
# Build concat list file
echo "file '${SLIDE1_VIDEO}'" > "${TMP_DIR}/video-concat-list.txt"
echo "file '${SLIDE2_VIDEO}'" >> "${TMP_DIR}/video-concat-list.txt"
echo "file '${SLIDE3_VIDEO}'" >> "${TMP_DIR}/video-concat-list.txt"
echo "file '${SLIDE4_VIDEO}'" >> "${TMP_DIR}/video-concat-list.txt"
echo "file '${SLIDE5_VIDEO}'" >> "${TMP_DIR}/video-concat-list.txt"

# Use concat demuxer with copy - all slides now have same audio bitrate (192k)
ffmpeg -y -f concat -safe 0 -i "${TMP_DIR}/video-concat-list.txt" \
  -c copy \
  -movflags +faststart \
  "$FINAL_VIDEO" 2>&1 || { echo "Failed to concatenate videos" >&2; exit 1; }

# Add background music if requested
if [ -n "$MUSIC_FILE" ]; then
  echo "Adding background music with ducking and fade-out..." >&2
  FINAL_VIDEO_WITH_MUSIC="${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume-with-music.mp4"
  
  # Get video duration
  DURATION=$(ffprobe -i "$FINAL_VIDEO" -show_entries format=duration -v quiet -of csv="p=0" 2>&1 | head -1)
  if [ -z "$DURATION" ] || [ "$DURATION" = "N/A" ]; then
    echo "Failed to get video duration" >&2
    exit 1
  fi
  
  # Calculate fade start (3 seconds before end)
  FADE_START=$(echo "$DURATION - 3" | bc)
  
  # Add music with ducking and fade-out
  ffmpeg -y -i "$FINAL_VIDEO" -stream_loop -1 -i "$MUSIC_FILE" \
    -filter_complex "[1:a]volume=0.25,aloop=loop=-1:size=2e+09,afade=t=out:st=${FADE_START}:d=3[music_faded];[0:a][music_faded]amix=inputs=2:duration=first:dropout_transition=2,acompressor=threshold=0.089:ratio=4:attack=100:release=500[audio]" \
    -map 0:v -map "[audio]" \
    -c:v copy \
    -c:a aac -b:a 192k \
    -shortest \
    "$FINAL_VIDEO_WITH_MUSIC" 2>&1 || { echo "Failed to add background music" >&2; exit 1; }
  
  echo "Video with music created: $FINAL_VIDEO_WITH_MUSIC" >&2
  echo "Original video (without music): $FINAL_VIDEO" >&2
fi

# Cleanup
rm -rf "$TMP_DIR"

# Print output path(s) for n8n
# If music was added, print both files (with music first, then original)
# Otherwise, just print the original
if [ -n "$MUSIC_FILE" ] && [ -f "${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume-with-music.mp4" ]; then
  echo "${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume-with-music.mp4"
  echo "${VIDEO_DIR}/${DATE}-${WORD_SLUG}-complete-hume.mp4"
else
  echo "$FINAL_VIDEO"
fi
