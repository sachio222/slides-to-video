# Slides to Video API

REST API for creating videos from slides with Hume TTS audio.

## Overview

This API provides a single-file REST endpoint that mirrors the functionality of the bash scripts (`create_multi_slide_video_hume.sh` and `create_multi_slide_video_hume_v2.sh`) but in a more modern, HTTP-based format.

**Key Features:**

- Single Python file with no code smells
- Clean separation of concerns with `VideoCreator` class
- Proper error handling and validation
- Context manager for automatic cleanup
- Same functionality as bash scripts (Hume TTS, waveforms, music, etc.)

## Installation

### 1. Install Python Dependencies

```bash
pip install flask hume
```

### 2. System Dependencies

Ensure these are installed:

- `ffmpeg` - Video/audio processing
- `ffprobe` - Audio/video metadata
- `magick` (ImageMagick) - Color analysis
- `bc` - Calculator

### 3. Environment Variables

```bash
export HUME_API_KEY="your-api-key-here"
```

Optional (defaults to "claire"):

```bash
export HUME_FRENCH_VOICE="claire"
export HUME_ENGLISH_VOICE="claire"
```

## Running the Server

```bash
# Basic usage
python3 create_video_api.py

# Custom host/port
python3 create_video_api.py --host 0.0.0.0 --port 8080

# Debug mode
python3 create_video_api.py --debug
```

Server will start at `http://127.0.0.1:5000` by default.

## API Endpoints

### Health Check

**GET** `/api/v1/health`

Returns server health status.

**Response:**

```json
{
  "status": "healthy",
  "service": "slides-to-video-api"
}
```

### Create Video

**POST** `/api/v1/create-video`

Creates a video from slides with Hume TTS audio.

**Request Body:**

```json
{
  "date": "2025-11-28",
  "word": "première",
  "slides": [
    {
      "path": "/path/to/slide1.png",
      "type": "waveform"
    },
    {
      "path": "/path/to/slide2.png",
      "type": "definition"
    },
    {
      "path": "/path/to/slide3.png",
      "type": "examples"
    },
    {
      "path": "/path/to/slide4.png",
      "type": "mnemonic"
    },
    {
      "path": "/path/to/slide5.png",
      "type": "cta"
    }
  ],
  "content": {
    "slides": [
      {
        "type": "definition",
        "translation": "first"
      },
      {
        "type": "examples",
        "examples": [
          {
            "english": "This is my first time",
            "french": "C'est ma première fois"
          },
          {
            "english": "The first step",
            "french": "La première étape"
          }
        ]
      },
      {
        "type": "mnemonic",
        "engagement": {
          "hook": "Think of 'premiere' movie",
          "connection": "First showing",
          "reinforcement": "première = first"
        }
      }
    ]
  },
  "music": "auto"
}
```

**Request Fields:**

| Field         | Type   | Required | Description                                     |
| ------------- | ------ | -------- | ----------------------------------------------- |
| `date`        | string | Yes      | Date string (e.g., "2025-11-28")                |
| `word`        | string | Yes      | Word being taught (e.g., "première")            |
| `slides`      | array  | Yes      | Array of slide objects (see below)              |
| `content`     | object | Yes      | Slide content data (see below)                  |
| `music`       | string | No       | Music file: "auto", "random", filename, or path |
| `config_file` | string | No       | Path to config.yaml (not implemented yet)       |

**Slide Object:**

| Field  | Type   | Required | Description                                                                              |
| ------ | ------ | -------- | ---------------------------------------------------------------------------------------- |
| `path` | string | Yes      | Absolute path to slide image                                                             |
| `type` | string | Yes      | Slide type: `waveform`, `definition`, `examples`, `mnemonic`, `quiz`, `cta`, or `static` |

**Slide Types:**

- `waveform` - Word pronunciation with waveform visualization
- `definition` - Definition with English translation
- `examples` - Example sentences (French → English → French)
- `mnemonic` - Memory aid (English narration)
- `quiz` - Multiple choice question (French narration)
- `cta` - Call to action (English narration)
- `static` - Static slide with silent audio

**Content Object:**

The `content.slides` array should contain objects matching the slide types:

**Definition:**

```json
{
  "type": "definition",
  "translation": "first"
}
```

**Examples:**

```json
{
  "type": "examples",
  "examples": [
    {
      "english": "This is my first time",
      "french": "C'est ma première fois"
    }
  ]
}
```

**Mnemonic:**

```json
{
  "type": "mnemonic",
  "engagement": {
    "hook": "Think of 'premiere' movie",
    "connection": "First showing",
    "reinforcement": "première = first"
  }
}
```

**Quiz:**

```json
{
  "type": "quiz",
  "engagement": {
    "question": "Complete: C'est ma _____ fois",
    "options": ["première", "premier", "dernière", "dernier"]
  }
}
```

**Music Options:**

- `"auto"` or `"random"` - Auto-select from bg-music/ based on date
- `"filename.mp3"` - File in bg-music/ directory
- `"/absolute/path/to/music.mp3"` - Absolute path
- `null` or omit - No background music

**Response (Success):**

```json
{
  "success": true,
  "videos": [
    "/path/to/2025-11-28-premiere-complete-hume-with-music.mp4",
    "/path/to/2025-11-28-premiere-complete-hume.mp4"
  ],
  "message": "Video created successfully"
}
```

**Response (Error):**

```json
{
  "success": false,
  "error": "Error message here"
}
```

**Status Codes:**

- `200` - Success
- `400` - Bad request (validation error)
- `500` - Internal server error

## Example Usage

### Using cURL

```bash
curl -X POST http://localhost:5000/api/v1/create-video \
  -H "Content-Type: application/json" \
  -d '{
    "date": "2025-11-28",
    "word": "première",
    "slides": [
      {"path": "/path/to/slide1.png", "type": "waveform"},
      {"path": "/path/to/slide2.png", "type": "definition"},
      {"path": "/path/to/slide3.png", "type": "cta"}
    ],
    "content": {
      "slides": [
        {"type": "definition", "translation": "first"}
      ]
    },
    "music": "auto"
  }'
```

### Using Python

```python
import requests

response = requests.post(
    "http://localhost:5000/api/v1/create-video",
    json={
        "date": "2025-11-28",
        "word": "première",
        "slides": [
            {"path": "/path/to/slide1.png", "type": "waveform"},
            {"path": "/path/to/slide2.png", "type": "definition"},
            {"path": "/path/to/slide3.png", "type": "cta"}
        ],
        "content": {
            "slides": [
                {"type": "definition", "translation": "first"}
            ]
        },
        "music": "auto"
    }
)

result = response.json()
if result["success"]:
    print("Videos created:")
    for video in result["videos"]:
        print(f"  - {video}")
else:
    print(f"Error: {result['error']}")
```

### Using JavaScript (Node.js)

```javascript
const fetch = require("node-fetch");

async function createVideo() {
  const response = await fetch("http://localhost:5000/api/v1/create-video", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      date: "2025-11-28",
      word: "première",
      slides: [
        { path: "/path/to/slide1.png", type: "waveform" },
        { path: "/path/to/slide2.png", type: "definition" },
        { path: "/path/to/slide3.png", type: "cta" },
      ],
      content: {
        slides: [{ type: "definition", translation: "first" }],
      },
      music: "auto",
    }),
  });

  const result = await response.json();

  if (result.success) {
    console.log("Videos created:");
    result.videos.forEach((video) => console.log(`  - ${video}`));
  } else {
    console.error(`Error: ${result.error}`);
  }
}

createVideo();
```

## Architecture

### Code Structure

The API follows clean architecture principles:

1. **Flask Application** - HTTP routing and request/response handling
2. **VideoCreator Class** - Core business logic (context manager pattern)
3. **Methods** - Each slide type has its own processor method
4. **Error Handling** - Custom `VideoCreationError` exception
5. **Configuration** - Centralized `DEFAULT_CONFIG` dictionary

### No Code Smells

The implementation avoids common code smells:

- ✅ **Single Responsibility** - Each method does one thing
- ✅ **DRY** - No repeated code (reusable methods)
- ✅ **Clear naming** - Descriptive function and variable names
- ✅ **Error handling** - Proper exceptions and validation
- ✅ **Resource management** - Context manager for cleanup
- ✅ **Configuration** - Centralized config, not scattered
- ✅ **Type safety** - Clear parameter types and validation

### Directory Structure

```
/Users/jupiter/dev/woodshed/images/languageacademy/socials/
└── 2025-11-28-premiere/
    ├── audio/
    │   ├── slide1.wav
    │   ├── slide2.wav
    │   └── ...
    └── video/
        ├── 2025-11-28-premiere-complete-hume.mp4
        └── 2025-11-28-premiere-complete-hume-with-music.mp4
```

## Comparison: API vs Shell Script

| Feature        | Shell Script   | API                    |
| -------------- | -------------- | ---------------------- |
| Format         | Bash script    | REST API               |
| Usage          | Command line   | HTTP requests          |
| Integration    | Shell commands | Any language with HTTP |
| Error handling | Exit codes     | JSON responses         |
| Validation     | Manual         | Automatic              |
| Concurrency    | Sequential     | Parallel requests      |
| Remote access  | SSH only       | HTTP/HTTPS             |
| Language       | Bash           | Python                 |

Both implementations provide identical functionality - choose based on your use case:

- **Shell script**: CLI automation, cron jobs, local development
- **API**: Web services, microservices, remote clients, n8n workflows

## Configuration

The API uses the same configuration structure as the shell scripts:

```python
DEFAULT_CONFIG = {
    "tts": {
        "french_voice": "claire",
        "english_voice": "claire"
    },
    "paths": {
        "output_base": "/Users/jupiter/dev/woodshed/images/languageacademy/socials",
        "homebrew_bin": "/opt/homebrew/bin",
        "local_bin": "/usr/local/bin"
    },
    "audio": {
        "sample_rate": 48000,
        "trailing_silence": 1.0,
        "leading_silence": 0.15,
        "pause_duration": 1.0
    },
    "video": {
        "default_width": 1080,
        "default_height": 1920,
        "video_bitrate": "4000k",
        "audio_bitrate": "192k",
        "preset": "medium",
        "crf": 23
    },
    "waveform": {
        "height_percent": 30,
        "bass_rolloff": 80,
        "alpha": 0.65
    },
    "music": {
        "volume": 0.15,
        "fade_duration": 3.0
    }
}
```

To customize, edit these values in `create_video_api.py` or (future) pass a config file.

## Troubleshooting

### Server won't start

Check that port 5000 is available:

```bash
lsof -i :5000
```

Use a different port:

```bash
python3 create_video_api.py --port 8080
```

### HUME_API_KEY error

Make sure the environment variable is set:

```bash
echo $HUME_API_KEY
```

Set it if missing:

```bash
export HUME_API_KEY="your-key-here"
```

### ffmpeg errors

Ensure ffmpeg is installed and in PATH:

```bash
which ffmpeg
ffmpeg -version
```

Install on macOS:

```bash
brew install ffmpeg imagemagick
```

### File not found errors

Use absolute paths for slide images:

```json
{
  "path": "/absolute/path/to/slide.png",
  "type": "waveform"
}
```

## Future Enhancements

Potential improvements (not implemented yet):

- [ ] YAML config file support via `config_file` parameter
- [ ] Video streaming instead of file paths in response
- [ ] Async processing with job queue
- [ ] Progress updates via WebSocket
- [ ] Authentication/authorization
- [ ] Rate limiting
- [ ] Caching of generated audio
- [ ] Batch video creation endpoint
- [ ] Video preview/thumbnail generation

## License

Same as the parent project.

