#!/usr/bin/env python3
"""
Slides to Video API Server

A Flask-based REST API that creates videos from slides with Hume TTS audio.
This is the API version of the create_multi_slide_video_hume scripts.

Usage:
    python3 create_video_api.py [--port PORT] [--host HOST]

API Endpoint:
    POST /api/v1/create-video
    
    Request body (JSON):
    {
        "date": "2025-11-28",
        "word": "première",
        "slides": [
            {"path": "/path/to/slide1.png", "type": "waveform"},
            {"path": "/path/to/slide2.png", "type": "definition"},
            {"path": "/path/to/slide3.png", "type": "examples"},
            {"path": "/path/to/slide4.png", "type": "mnemonic"},
            {"path": "/path/to/slide5.png", "type": "cta"}
        ],
        "content": {
            "slides": [
                {"type": "definition", "translation": "first"},
                {"type": "examples", "examples": [
                    {"english": "This is my first time", "french": "C'est ma première fois"},
                    {"english": "The first step", "french": "La première étape"}
                ]},
                {"type": "mnemonic", "engagement": {
                    "hook": "Think of 'premiere' movie",
                    "connection": "First showing",
                    "reinforcement": "première = first"
                }}
            ]
        },
        "music": "auto",  // optional: "auto", "random", filename, or absolute path
        "config_file": null  // optional: path to config.yaml
    }
    
    Response:
    {
        "success": true,
        "videos": [
            "/path/to/video-with-music.mp4",
            "/path/to/video-without-music.mp4"
        ],
        "message": "Video created successfully"
    }

Requirements:
    - Flask
    - hume (Python SDK)
    - ffmpeg, ffprobe, ImageMagick (magick), bc
"""

import os
import sys
import json
import subprocess
import tempfile
import shutil
import argparse
import base64
import re
import unicodedata
from pathlib import Path
from flask import Flask, request, jsonify, send_file
from hume import HumeClient

# Initialize Flask app
app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 100 * 1024 * 1024  # 100MB max request size

# Default configuration
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


class VideoCreationError(Exception):
    """Custom exception for video creation errors"""
    pass


class VideoCreator:
    """Handles all video creation logic"""

    def __init__(self, config=None):
        self.config = {**DEFAULT_CONFIG, **(config or {})}
        self.hume_client = None
        self.temp_dir = None
        self.script_dir = Path(__file__).parent.absolute()

    def __enter__(self):
        self.temp_dir = tempfile.mkdtemp(prefix="video-api-")
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.temp_dir and os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def validate_dependencies(self):
        """Validate that all required system dependencies are available"""
        missing = []
        for cmd in ["ffmpeg", "ffprobe", "magick", "bc"]:
            if not shutil.which(cmd):
                missing.append(cmd)

        if missing:
            raise VideoCreationError(
                f"Missing required dependencies: {', '.join(missing)}\n"
                "Please install: ffmpeg, ffprobe, ImageMagick (magick), bc"
            )

    def to_slug(self, text):
        """Convert text to URL-safe slug"""
        if not text:
            return "slide"

        # Normalize to NFD (decompose accented characters)
        text = unicodedata.normalize('NFD', text)
        # Remove diacritics
        text = ''.join(c for c in text if unicodedata.category(c) != 'Mn')
        # Lowercase and clean
        text = text.lower()
        text = re.sub(r'[^\w\s-]', '', text)
        text = re.sub(r'\s+', '-', text)
        text = re.sub(r'-+', '-', text)
        text = text.strip('-')

        return text if text else "slide"

    def resolve_music_file(self, music_spec, date):
        """Resolve music file path from specification"""
        if not music_spec:
            return None

        music_dir = self.script_dir / "bg-music"

        # Handle special keywords
        if music_spec in ["random", "auto"]:
            if not music_dir.exists():
                return None

            music_files = sorted(
                music_dir.glob("*.mp3") +
                list(music_dir.glob("*.wav")) +
                list(music_dir.glob("*.m4a")) +
                list(music_dir.glob("*.ogg"))
            )

            if not music_files:
                return None

            # Use date as seed for consistent random selection
            seed = int(re.sub(r'[^0-9]', '', date) or '1')
            index = seed % len(music_files)
            return str(music_files[index])

        # Try as absolute path
        music_path = Path(music_spec)
        if music_path.is_absolute() and music_path.exists():
            return str(music_path)

        # Try relative to script directory
        music_path = self.script_dir / music_spec
        if music_path.exists():
            return str(music_path)

        # Try in bg-music directory
        music_path = music_dir / music_spec
        if music_path.exists():
            return str(music_path)

        raise VideoCreationError(f"Music file not found: {music_spec}")

    def get_video_dimensions(self, image_path):
        """Get video dimensions from image"""
        try:
            width = subprocess.check_output(
                ["ffprobe", "-v", "quiet", "-select_streams", "v:0",
                 "-show_entries", "stream=width", "-of", "csv=p=0", image_path],
                text=True
            ).strip()

            height = subprocess.check_output(
                ["ffprobe", "-v", "quiet", "-select_streams", "v:0",
                 "-show_entries", "stream=height", "-of", "csv=p=0", image_path],
                text=True
            ).strip()

            if width and height and width != "N/A" and height != "N/A":
                return int(width), int(height)
        except (subprocess.CalledProcessError, ValueError):
            pass

        # Fallback to defaults
        return (
            self.config["video"]["default_width"],
            self.config["video"]["default_height"]
        )

    def generate_audio_with_hume(self, text, voice_name, output_path, language="en"):
        """Generate audio using Hume TTS SDK"""
        api_key = os.environ.get("HUME_API_KEY")
        if not api_key:
            raise VideoCreationError(
                "HUME_API_KEY environment variable is required")

        if not self.hume_client:
            self.hume_client = HumeClient(api_key=api_key)

        # Build utterance with voice specification
        utterance = {"text": text}
        if voice_name and voice_name.lower() != "default":
            utterance["voice"] = {
                "name": voice_name,
                "provider": "HUME_AI"
            }

        try:
            response = self.hume_client.tts.synthesize_json(
                utterances=[utterance],
                format={"type": "wav"},
                version="2"  # Octave 2
            )

            if not response.generations:
                raise VideoCreationError(
                    "No audio generations returned from Hume")

            audio_b64 = response.generations[0].audio
            audio_bytes = base64.b64decode(audio_b64)

            with open(output_path, "wb") as f:
                f.write(audio_bytes)

        except Exception as e:
            raise VideoCreationError(
                f"Failed to generate audio with Hume: {e}")

    def add_silence_padding(self, input_audio, output_audio, add_leading=False):
        """Add silence padding to audio"""
        # Get sample rate and channels from input
        try:
            sample_rate = subprocess.check_output(
                ["ffprobe", "-v", "quiet", "-show_entries", "stream=sample_rate",
                 "-of", "default=noprint_wrappers=1:nokey=1", input_audio],
                text=True
            ).strip()

            if not sample_rate or sample_rate == "N/A":
                sample_rate = str(self.config["audio"]["sample_rate"])

            channels = subprocess.check_output(
                ["ffprobe", "-v", "quiet", "-show_entries", "stream=channels",
                 "-of", "default=noprint_wrappers=1:nokey=1", input_audio],
                text=True
            ).strip()

            channels = re.sub(r'[^0-9]', '', channels)
            channels = int(channels) if channels else 1
            channel_layout = "stereo" if channels >= 2 else "mono"

        except (subprocess.CalledProcessError, ValueError):
            sample_rate = str(self.config["audio"]["sample_rate"])
            channel_layout = "mono"

        trailing = self.config["audio"]["trailing_silence"]
        leading = self.config["audio"]["leading_silence"]

        if add_leading:
            cmd = [
                "ffmpeg", "-y",
                "-i", input_audio,
                "-f", "lavfi", "-i", f"anullsrc=r={sample_rate}:cl={channel_layout}:d={trailing}",
                "-f", "lavfi", "-i", f"anullsrc=r={sample_rate}:cl={channel_layout}:d={leading}",
                "-filter_complex", "[0:a][1:a][2:a]concat=n=3:v=0:a=1",
                output_audio
            ]
        else:
            cmd = [
                "ffmpeg", "-y",
                "-i", input_audio,
                "-f", "lavfi", "-i", f"anullsrc=r={sample_rate}:cl={channel_layout}:d={trailing}",
                "-filter_complex", "[0:a][1:a]concat=n=2:v=0:a=1",
                output_audio
            ]

        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            raise VideoCreationError(
                f"Failed to add silence padding: {e.stderr}")

    def calculate_contrast_color(self, image_path):
        """Calculate contrasting color for waveform"""
        script_path = self.script_dir / "calculate_contrast_color.py"
        if not script_path.exists():
            return "#00FFFF"  # Default cyan

        try:
            result = subprocess.check_output(
                ["python3", str(script_path), image_path],
                text=True
            )
            color = result.strip().split('\n')[-1]
            return color if color else "#00FFFF"
        except subprocess.CalledProcessError:
            return "#00FFFF"

    def get_audio_duration(self, audio_path):
        """Get duration of audio file"""
        try:
            duration = subprocess.check_output(
                ["ffprobe", "-i", audio_path, "-show_entries", "format=duration",
                 "-v", "quiet", "-of", "csv=p=0"],
                text=True
            ).strip()

            if duration and duration != "N/A":
                return float(duration)
        except (subprocess.CalledProcessError, ValueError):
            pass

        raise VideoCreationError(
            f"Failed to get audio duration for {audio_path}")

    def create_waveform_video(self, image_path, audio_path, output_path, width, height):
        """Create video with waveform visualization"""
        color = self.calculate_contrast_color(image_path)

        padded_audio = os.path.join(self.temp_dir, "padded-waveform.wav")
        self.add_silence_padding(audio_path, padded_audio, add_leading=False)

        duration = self.get_audio_duration(padded_audio)

        waveform_height = height * \
            self.config["waveform"]["height_percent"] // 100
        waveform_y = height - waveform_height
        bass_rolloff = self.config["waveform"]["bass_rolloff"]
        alpha = self.config["waveform"]["alpha"]

        cmd = [
            "ffmpeg", "-y", "-loop", "1", "-i", image_path, "-i", padded_audio,
            "-filter_complex",
            f"[0:v]scale={width}:{height}:force_original_aspect_ratio=decrease,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=black[bg];"
            f"[1:a]highpass=f={bass_rolloff}[wave_audio];"
            f"[wave_audio]showfreqs=s={width}x{waveform_height}:mode=bar:colors={color}:ascale=log,"
            f"format=yuva420p,colorchannelmixer=aa={alpha}[wave];"
            f"[bg][wave]overlay=0:{waveform_y}[v];"
            f"[1:a]pan=stereo|c0=c0|c1=c0[audio]",
            "-map", "[v]", "-map", "[audio]",
            "-c:v", "libx264", "-preset", self.config["video"]["preset"],
            "-b:v", self.config["video"]["video_bitrate"],
            "-c:a", "aac", "-b:a", self.config["video"]["audio_bitrate"],
            "-t", str(duration),
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            output_path
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            raise VideoCreationError(
                f"Failed to create waveform video: {e.stderr}")

    def create_static_video(self, image_path, audio_path, output_path, width, height):
        """Create static video with audio"""
        padded_audio = os.path.join(
            self.temp_dir,
            f"padded-{os.path.basename(output_path)}.wav"
        )
        self.add_silence_padding(audio_path, padded_audio, add_leading=False)

        duration = self.get_audio_duration(padded_audio)

        cmd = [
            "ffmpeg", "-y", "-loop", "1", "-i", image_path, "-i", padded_audio,
            "-filter_complex",
            f"[0:v]scale={width}:{height}:force_original_aspect_ratio=decrease,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=black[bg];"
            f"[1:a]pan=stereo|c0=c0|c1=c0[audio]",
            "-map", "[bg]", "-map", "[audio]",
            "-c:v", "libx264", "-preset", self.config["video"]["preset"],
            "-crf", str(self.config["video"]["crf"]),
            "-c:a", "aac", "-b:a", self.config["video"]["audio_bitrate"],
            "-t", str(duration),
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            output_path
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            raise VideoCreationError(
                f"Failed to create static video: {e.stderr}")

    def process_waveform_slide(self, slide_num, image_path, word, audio_dir, width, height):
        """Process waveform slide (slide 1)"""
        word_cap = word[0].upper() + word[1:] if word else word
        audio_path = os.path.join(audio_dir, f"slide{slide_num}.wav")

        voice = self.config["tts"]["french_voice"]
        self.generate_audio_with_hume(
            f"{word_cap}. {word_cap}.",
            voice,
            audio_path,
            language="fr"
        )

        video_path = os.path.join(self.temp_dir, f"slide{slide_num}.mp4")
        self.create_waveform_video(
            image_path, audio_path, video_path, width, height)

        return video_path

    def process_definition_slide(self, slide_num, image_path, content, audio_dir, width, height):
        """Process definition slide"""
        text = ""
        for slide in content.get("slides", []):
            if slide.get("type") == "definition":
                text = slide.get("translation", "")
                break

        if not text:
            text = "Definition"

        audio_path = os.path.join(audio_dir, f"slide{slide_num}.wav")
        voice = self.config["tts"]["english_voice"]
        self.generate_audio_with_hume(text, voice, audio_path, language="en")

        video_path = os.path.join(self.temp_dir, f"slide{slide_num}.mp4")
        self.create_static_video(
            image_path, audio_path, video_path, width, height)

        return video_path

    def process_examples_slide(self, slide_num, image_path, content, audio_dir, width, height):
        """Process examples slide"""
        examples = []
        for slide in content.get("slides", []):
            if slide.get("type") == "examples":
                examples = slide.get("examples", [])
                break

        segments = []
        sample_rate = self.config["audio"]["sample_rate"]
        pause_duration = self.config["audio"]["pause_duration"]

        for idx, example in enumerate(examples, 1):
            english = example.get("english", "")
            french = example.get("french", "")

            if not english or not french:
                continue

            # Label
            label_audio = os.path.join(self.temp_dir, f"ex{idx}-label.wav")
            self.generate_audio_with_hume(
                f"Exemple {idx}:",
                self.config["tts"]["french_voice"],
                label_audio,
                language="fr"
            )
            segments.append(label_audio)

            # French first
            fr1_audio = os.path.join(self.temp_dir, f"ex{idx}-fr1.wav")
            self.generate_audio_with_hume(
                french,
                self.config["tts"]["french_voice"],
                fr1_audio,
                language="fr"
            )
            segments.append(fr1_audio)

            # English
            en_audio = os.path.join(self.temp_dir, f"ex{idx}-en.wav")
            self.generate_audio_with_hume(
                english,
                self.config["tts"]["english_voice"],
                en_audio,
                language="en"
            )
            segments.append(en_audio)

            # French repeat
            fr2_audio = os.path.join(self.temp_dir, f"ex{idx}-fr2.wav")
            self.generate_audio_with_hume(
                french,
                self.config["tts"]["french_voice"],
                fr2_audio,
                language="fr"
            )
            segments.append(fr2_audio)

            # Pause
            pause_audio = os.path.join(self.temp_dir, f"ex{idx}-pause.wav")
            subprocess.run([
                "ffmpeg", "-y", "-f", "lavfi",
                "-i", f"anullsrc=r={sample_rate}:cl=mono:d={pause_duration}",
                pause_audio
            ], check=True, capture_output=True)
            segments.append(pause_audio)

        # Concatenate segments
        final_audio = os.path.join(audio_dir, f"slide{slide_num}.wav")

        if segments:
            concat_file = os.path.join(self.temp_dir, "concat-list.txt")
            with open(concat_file, "w") as f:
                for seg in segments:
                    f.write(f"file '{seg}'\n")

            subprocess.run([
                "ffmpeg", "-y", "-f", "concat", "-safe", "0",
                "-i", concat_file,
                "-c:a", "pcm_s16le",
                final_audio
            ], check=True, capture_output=True)
        else:
            # Empty audio fallback
            subprocess.run([
                "ffmpeg", "-y", "-f", "lavfi",
                "-i", f"anullsrc=r={sample_rate}:cl=mono:d=1",
                final_audio
            ], check=True, capture_output=True)

        video_path = os.path.join(self.temp_dir, f"slide{slide_num}.mp4")
        self.create_static_video(
            image_path, final_audio, video_path, width, height)

        return video_path

    def process_mnemonic_or_quiz_slide(self, slide_num, image_path, content, audio_dir, width, height):
        """Process mnemonic or quiz slide"""
        text = ""
        language = "en"

        for slide in content.get("slides", []):
            slide_type = slide.get("type")

            if slide_type == "mnemonic":
                engagement = slide.get("engagement", {})
                hook = engagement.get("hook", "").replace("'", "")
                connection = engagement.get("connection", "").replace("'", "")
                reinforcement = engagement.get("reinforcement", "").replace(
                    "'", "").replace("=", " means ")

                parts = [p for p in [hook, connection, reinforcement] if p]
                text = ". ".join(parts)
                language = "en"
                break

            elif slide_type == "quiz":
                engagement = slide.get("engagement", {})
                question = engagement.get("question", "")
                options = engagement.get("options", [])

                # Replace blanks
                question = re.sub(r'_+', ' Blank ', question)
                question = re.sub(r'\s+', ' ', question).strip()
                question = question.rstrip('.!?')

                parts = [question]

                # Add options
                labels = ["A", "B", "C", "D"]
                for i, option in enumerate(options):
                    if i < len(labels):
                        parts.append(f"{labels[i]}): {option}")

                parts.append("Comment your response below!")
                text = ". ".join(parts)
                language = "fr"
                break

        audio_path = os.path.join(audio_dir, f"slide{slide_num}.wav")

        if not text:
            # Empty audio fallback
            sample_rate = self.config["audio"]["sample_rate"]
            subprocess.run([
                "ffmpeg", "-y", "-f", "lavfi",
                "-i", f"anullsrc=r={sample_rate}:cl=mono:d=1",
                audio_path
            ], check=True, capture_output=True)
        else:
            voice = (self.config["tts"]["french_voice"] if language == "fr"
                     else self.config["tts"]["english_voice"])
            self.generate_audio_with_hume(
                text, voice, audio_path, language=language)

        video_path = os.path.join(self.temp_dir, f"slide{slide_num}.mp4")
        self.create_static_video(
            image_path, audio_path, video_path, width, height)

        return video_path

    def process_cta_slide(self, slide_num, image_path, audio_dir, width, height):
        """Process CTA slide"""
        text = "Merci beaucoup! Like, follow and share. Visit language academy dot io today!"

        audio_path = os.path.join(audio_dir, f"slide{slide_num}.wav")
        voice = self.config["tts"]["english_voice"]
        self.generate_audio_with_hume(text, voice, audio_path, language="en")

        video_path = os.path.join(self.temp_dir, f"slide{slide_num}.mp4")
        self.create_static_video(
            image_path, audio_path, video_path, width, height)

        return video_path

    def process_static_slide(self, slide_num, image_path, audio_dir, width, height):
        """Process static/unknown slide type"""
        audio_path = os.path.join(audio_dir, f"slide{slide_num}.wav")

        # Create silent audio
        sample_rate = self.config["audio"]["sample_rate"]
        subprocess.run([
            "ffmpeg", "-y", "-f", "lavfi",
            "-i", f"anullsrc=r={sample_rate}:cl=mono:d=2",
            audio_path
        ], check=True, capture_output=True)

        video_path = os.path.join(self.temp_dir, f"slide{slide_num}.mp4")
        self.create_static_video(
            image_path, audio_path, video_path, width, height)

        return video_path

    def concatenate_videos(self, video_paths, output_path):
        """Concatenate multiple videos into one"""
        concat_file = os.path.join(self.temp_dir, "video-concat-list.txt")
        with open(concat_file, "w") as f:
            for video in video_paths:
                f.write(f"file '{video}'\n")

        cmd = [
            "ffmpeg", "-y", "-f", "concat", "-safe", "0",
            "-i", concat_file,
            "-c", "copy",
            "-movflags", "+faststart",
            output_path
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            raise VideoCreationError(
                f"Failed to concatenate videos: {e.stderr}")

    def add_background_music(self, video_path, music_path, output_path):
        """Add background music with ducking and fade-out"""
        duration = self.get_audio_duration(video_path)

        fade_duration = self.config["music"]["fade_duration"]
        fade_start = duration - fade_duration
        volume = self.config["music"]["volume"]

        cmd = [
            "ffmpeg", "-y",
            "-i", video_path,
            "-stream_loop", "-1", "-i", music_path,
            "-filter_complex",
            f"[1:a]volume={volume},aloop=loop=-1:size=2e+09,"
            f"afade=t=out:st={fade_start}:d={fade_duration}[music];"
            f"[music][0:a]sidechaincompress=threshold=0.02:ratio=8:attack=20:release=200[ducked];"
            f"[0:a][ducked]amix=inputs=2:duration=first:dropout_transition=0[audio]",
            "-map", "0:v", "-map", "[audio]",
            "-c:v", "copy",
            "-c:a", "aac", "-b:a", self.config["video"]["audio_bitrate"],
            "-shortest",
            output_path
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            raise VideoCreationError(
                f"Failed to add background music: {e.stderr}")

    def create_video(self, date, word, slides, content, music=None):
        """Main video creation orchestrator"""
        self.validate_dependencies()

        # Setup paths
        word_slug = self.to_slug(word)
        output_base = Path(self.config["paths"]["output_base"])
        base_dir = output_base / f"{date}-{word_slug}"

        # Find available video directory
        video_base_dir = base_dir / "video"
        video_dir = video_base_dir
        counter = 1

        while video_dir.exists():
            video_dir = Path(f"{video_base_dir}-{counter}")
            counter += 1

        audio_dir = base_dir / "audio"
        video_dir.mkdir(parents=True, exist_ok=True)
        audio_dir.mkdir(parents=True, exist_ok=True)

        # Get video dimensions from first slide
        width, height = self.get_video_dimensions(slides[0]["path"])

        # Process each slide
        slide_videos = []

        for idx, slide in enumerate(slides, 1):
            slide_path = slide["path"]
            slide_type = slide["type"]

            if not os.path.exists(slide_path):
                raise VideoCreationError(
                    f"Slide image not found: {slide_path}")

            if slide_type == "waveform":
                video = self.process_waveform_slide(
                    idx, slide_path, word, str(audio_dir), width, height
                )
            elif slide_type == "definition":
                video = self.process_definition_slide(
                    idx, slide_path, content, str(audio_dir), width, height
                )
            elif slide_type == "examples":
                video = self.process_examples_slide(
                    idx, slide_path, content, str(audio_dir), width, height
                )
            elif slide_type in ["mnemonic", "quiz"]:
                video = self.process_mnemonic_or_quiz_slide(
                    idx, slide_path, content, str(audio_dir), width, height
                )
            elif slide_type == "cta":
                video = self.process_cta_slide(
                    idx, slide_path, str(audio_dir), width, height
                )
            else:
                video = self.process_static_slide(
                    idx, slide_path, str(audio_dir), width, height
                )

            slide_videos.append(video)

        # Concatenate all slides
        final_video = video_dir / f"{date}-{word_slug}-complete-hume.mp4"
        self.concatenate_videos(slide_videos, str(final_video))

        result_videos = [str(final_video)]

        # Add music if requested
        if music:
            music_path = self.resolve_music_file(music, date)
            if music_path:
                final_video_with_music = video_dir / \
                    f"{date}-{word_slug}-complete-hume-with-music.mp4"
                self.add_background_music(
                    str(final_video),
                    music_path,
                    str(final_video_with_music)
                )
                result_videos.insert(0, str(final_video_with_music))

        return result_videos


@app.route('/api/v1/create-video', methods=['POST'])
def create_video():
    """API endpoint to create video from slides"""
    try:
        data = request.get_json()

        # Validate required fields
        if not data:
            return jsonify({
                "success": False,
                "error": "No JSON data provided"
            }), 400

        required_fields = ["date", "word", "slides", "content"]
        missing_fields = [f for f in required_fields if f not in data]

        if missing_fields:
            return jsonify({
                "success": False,
                "error": f"Missing required fields: {', '.join(missing_fields)}"
            }), 400

        if not data["slides"]:
            return jsonify({
                "success": False,
                "error": "At least one slide is required"
            }), 400

        # Create video
        with VideoCreator() as creator:
            videos = creator.create_video(
                date=data["date"],
                word=data["word"],
                slides=data["slides"],
                content=data["content"],
                music=data.get("music")
            )

        return jsonify({
            "success": True,
            "videos": videos,
            "message": "Video created successfully"
        })

    except VideoCreationError as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 400

    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Internal server error: {str(e)}"
        }), 500


@app.route('/api/v1/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "service": "slides-to-video-api"
    })


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Slides to Video API Server"
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host to bind to (default: 127.0.0.1)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=5000,
        help="Port to bind to (default: 5000)"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug mode"
    )

    args = parser.parse_args()

    print(f"Starting Slides to Video API Server on {args.host}:{args.port}")
    print(f"API endpoint: http://{args.host}:{args.port}/api/v1/create-video")

    app.run(
        host=args.host,
        port=args.port,
        debug=args.debug
    )


if __name__ == "__main__":
    main()

