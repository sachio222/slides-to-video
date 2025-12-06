#!/usr/bin/env python3
"""
Quick test script for the API
Replace the slide paths with your actual slide images
"""

import requests
import json
import sys

# Update these paths to your actual slide images!
SLIDE_PATHS = {
    "slide1": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-11-28-premiere/slide-1-word-sound.png",
    "slide2": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-11-28-premiere/slide-2-definition.png",
    "slide5": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-11-28-premiere/slide-5-cta.png"
}

API_URL = "http://localhost:5000"


def test_health():
    """Test health endpoint"""
    print("Testing health endpoint...")
    try:
        response = requests.get(f"{API_URL}/api/v1/health", timeout=5)
        result = response.json()
        if result.get("status") == "healthy":
            print("✓ Health check passed")
            return True
        else:
            print("✗ Health check failed")
            return False
    except Exception as e:
        print(f"✗ Cannot connect to API: {e}")
        print("Make sure the server is running: python3 create_video_api.py")
        return False


def test_create_video():
    """Test video creation endpoint"""
    print("\nTesting video creation...")

    # Check if slide files exist
    import os
    for name, path in SLIDE_PATHS.items():
        if not os.path.exists(path):
            print(f"✗ Slide not found: {path}")
            print(
                f"  Update the SLIDE_PATHS in this script to point to real slide images")
            return False

    payload = {
        "date": "2025-12-06",
        "word": "test",
        "slides": [
            {"path": SLIDE_PATHS["slide1"], "type": "waveform"},
            {"path": SLIDE_PATHS["slide2"], "type": "definition"},
            {"path": SLIDE_PATHS["slide5"], "type": "cta"}
        ],
        "content": {
            "slides": [
                {"type": "definition", "translation": "test"}
            ]
        },
        "music": None  # Set to "auto" to test music
    }

    print(f"Request payload:")
    print(json.dumps(payload, indent=2))
    print("\nSending request (this may take a while)...")

    try:
        response = requests.post(
            f"{API_URL}/api/v1/create-video",
            json=payload,
            timeout=300  # 5 minutes timeout
        )

        print(f"\nStatus: {response.status_code}")
        result = response.json()

        if result.get("success"):
            print("✓ Video created successfully!")
            print("\nVideos:")
            for video in result.get("videos", []):
                print(f"  - {video}")
            return True
        else:
            print(f"✗ Error: {result.get('error')}")
            return False

    except requests.exceptions.Timeout:
        print("✗ Request timed out (video creation takes time)")
        return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False


def main():
    print("=" * 60)
    print("API Quick Test")
    print("=" * 60)
    print()

    # Test health
    if not test_health():
        sys.exit(1)

    # Ask before creating video
    print("\nReady to test video creation?")
    print("This will:")
    print("  1. Generate audio with Hume TTS")
    print("  2. Create video clips")
    print("  3. Concatenate into final video")
    print("  4. Take 30-60 seconds")
    print()

    response = input("Continue? (y/n): ")
    if response.lower() != 'y':
        print("Skipping video creation test")
        sys.exit(0)

    # Test video creation
    success = test_create_video()

    print()
    print("=" * 60)
    if success:
        print("✓ All tests passed!")
    else:
        print("✗ Some tests failed")
    print("=" * 60)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

