# Slides to Video

Create videos from slides with Hume TTS audio and optional background music.

**New**: REST API version available! See `API_USAGE.md` for details.

**Also new**: Refactored version with flexible slide count! See `MIGRATION.md` for details.

## Quick Start

### Option 1: Command Line (Bash Scripts)

Use the refactored v2 script (backwards compatible):

```bash
# Legacy format (still works):
./create_multi_slide_video_hume_v2.sh "2025-11-28" "première" \
  "$S1" "$S2" "$S3" "$S4" "$S5" "$JSON"

# New flexible format (any number of slides):
./create_multi_slide_video_hume_v2.sh "2025-11-28" "première" \
  --slides "$S1:waveform" "$S2:definition" "$S3:cta" \
  --content "$JSON"
```

### Option 2: REST API (Python)

Start the API server:

```bash
python3 create_video_api.py
```

Make API requests (see `API_USAGE.md` for full documentation):

```bash
curl -X POST http://localhost:5000/api/v1/create-video \
  -H "Content-Type: application/json" \
  -d @request.json
```

Or use the example client:

```bash
python3 example_client.py
```

## Setup

### 1. Install Python Dependencies

For the bash scripts:

```bash
cd /Users/jupiter/dev/woodshed/tts/slides_to_video
python3 -m venv venv
source venv/bin/activate
pip install hume
```

For the REST API (additional dependency):

```bash
pip install flask hume
```

### 2. Set Environment Variables

```bash
export HUME_API_KEY="your-api-key-here"
export HUME_FRENCH_VOICE="claire"  # optional, defaults to "claire"
export HUME_ENGLISH_VOICE="claire"  # optional, defaults to "claire"
```

Get your API key from: https://dev.hume.ai

### 3. System Dependencies

Ensure these are installed and in your PATH:

- `ffmpeg` - Video/audio processing
- `ffprobe` - Audio/video metadata
- `python3` - Python interpreter
- `magick` (ImageMagick) - Color analysis
- `bc` - Calculator

## Usage

```bash
./create_multi_slide_video_hume.sh DATE WORD SLIDE1 SLIDE2 SLIDE3 SLIDE4 SLIDE5 SLIDE_CONTENT_JSON [--music MUSIC_FILE]
```

### Arguments

- `DATE` - Date string (e.g., "2025-11-28")
- `WORD` - Word being taught (e.g., "première")
- `SLIDE1` - Path to slide 1 image (word with waveform)
- `SLIDE2` - Path to slide 2 image (definition)
- `SLIDE3` - Path to slide 3 image (examples)
- `SLIDE4` - Path to slide 4 image (mnemonic/quiz)
- `SLIDE5` - Path to slide 5 image (CTA)
- `SLIDE_CONTENT_JSON` - JSON array with slide content
- `--music MUSIC_FILE` - (Optional) Background music file

### Example

```bash
./create_multi_slide_video_hume.sh \
  "2025-11-28" \
  "première" \
  "$SLIDE1" "$SLIDE2" "$SLIDE3" "$SLIDE4" "$SLIDE5" \
  "$SLIDE_JSON" \
  --music music.mp3
```

## Output

Videos are created in:
`/Users/jupiter/dev/woodshed/images/languageacademy/socials/${DATE}-${WORD_SLUG}/video/`

- Without `--music`: Creates `${DATE}-${WORD_SLUG}-complete-hume.mp4`
- With `--music`: Creates both:
  - `${DATE}-${WORD_SLUG}-complete-hume-with-music.mp4` (with music)
  - `${DATE}-${WORD_SLUG}-complete-hume.mp4` (original)

## Files

### Bash Scripts

- `create_multi_slide_video_hume.sh` - Original script (5 slides fixed)
- `create_multi_slide_video_hume_v2.sh` - Refactored script (flexible slide count)
- `hume_tts.py` - Hume TTS helper
- `calculate_contrast_color.py` - Waveform color calculator

### REST API

- `create_video_api.py` - REST API server (single file)
- `API_USAGE.md` - Full API documentation
- `example_client.py` - Example Python client
- `test_api.sh` - Example bash/curl client

### Utilities

- `utils/` - Helper utilities (config, parsing, caching)
- `venv/` - Python virtual environment (create with setup steps above)

## Choosing Between Bash Scripts and REST API

**Use Bash Scripts when:**

- Running locally from command line
- Integrating with shell scripts or cron jobs
- You prefer command-line tools
- Single-machine execution

**Use REST API when:**

- Building web services or microservices
- Need remote access over HTTP
- Integrating with n8n or other workflow tools
- Want to call from any programming language
- Need concurrent request handling

Both implementations provide identical video output and functionality.
