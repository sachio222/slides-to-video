#!/usr/bin/env python3
"""
Hume TTS helper script for generating audio using the Hume Python SDK
Usage: hume_tts.py TEXT VOICE_NAME OUTPUT_FILE [LANGUAGE]

VOICE_NAME: Name of the voice (e.g., "claire") or "default" for account default
LANGUAGE: "en" for English, "fr" for French (optional, defaults to "en")
"""
import sys
import os
import base64
from hume import HumeClient


def main():
    if len(sys.argv) < 4:
        print(
            "Usage: hume_tts.py TEXT VOICE_NAME OUTPUT_FILE [LANGUAGE]", file=sys.stderr)
        sys.exit(1)

    text = sys.argv[1]
    voice_name = sys.argv[2]
    output_file = sys.argv[3]
    language = sys.argv[4] if len(sys.argv) > 4 else "en"

    # Get API key from environment
    api_key = os.environ.get("HUME_API_KEY")
    if not api_key:
        print("Error: HUME_API_KEY environment variable is required", file=sys.stderr)
        sys.exit(1)

    try:
        # Initialize client
        client = HumeClient(api_key=api_key)

        # Build utterance with voice specification if not "default"
        utterance = {"text": text}
        if voice_name and voice_name.lower() != "default":
            utterance["voice"] = {
                "name": voice_name,
                "provider": "HUME_AI"
            }

        # Generate speech using synthesize_json with octave2 (version "2")
        response = client.tts.synthesize_json(
            utterances=[utterance],
            format={"type": "wav"},
            version="2"  # Use octave2
        )

        # Get audio from first generation (base64 encoded)
        if not response.generations:
            print("Error: No audio generations returned", file=sys.stderr)
            sys.exit(1)

        gen = response.generations[0]
        audio_b64 = gen.audio

        # Decode base64 to bytes
        audio_bytes = base64.b64decode(audio_b64)

        # Save to file
        with open(output_file, "wb") as f:
            f.write(audio_bytes)

        print(
            f"Generated audio: {output_file} ({len(audio_bytes)} bytes)", file=sys.stderr)

    except Exception as e:
        print(f"Error generating audio: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
