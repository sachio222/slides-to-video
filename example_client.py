#!/usr/bin/env python3
"""
Example client for the Slides to Video API

This demonstrates how to use the API from Python code.
"""

import requests
import json
import sys


def create_video_example():
    """Example: Create a video with 3 slides"""

    # API endpoint
    api_url = "http://localhost:3002/api/v1/create-video"

    # Request payload
    payload = {
        "date": "2025-12-06",
        "word": "première",
        "slides": [
            {
                "path": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-11-28-premiere/slide-1-word-sound.png",
                "type": "waveform"
            },
            {
                "path": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-11-28-premiere/slide-2-definition.png",
                "type": "definition"
            },
            {
                "path": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-11-28-premiere/slide-5-cta.png",
                "type": "cta"
            }
        ],
        "content": {
            "slides": [
                {
                    "type": "definition",
                    "translation": "first"
                }
            ]
        },
        "music": "auto"
    }

    print("Sending request to API...")
    print(f"URL: {api_url}")
    print(f"Payload: {json.dumps(payload, indent=2)}")
    print()

    try:
        response = requests.post(api_url, json=payload)

        print(f"Status Code: {response.status_code}")
        print()

        result = response.json()

        if result.get("success"):
            print("✓ Success!")
            print(f"Message: {result.get('message')}")
            print()
            print("Videos created:")
            for video in result.get("videos", []):
                print(f"  - {video}")
        else:
            print("✗ Error!")
            print(f"Error: {result.get('error')}")
            sys.exit(1)

    except requests.exceptions.ConnectionError:
        print("✗ Connection Error!")
        print("Make sure the API server is running:")
        print("  python3 create_video_api.py")
        sys.exit(1)

    except Exception as e:
        print(f"✗ Unexpected error: {e}")
        sys.exit(1)


def health_check():
    """Check if the API server is healthy"""

    api_url = "http://localhost:3002/api/v1/health"

    print("Checking API health...")

    try:
        response = requests.get(api_url)
        result = response.json()

        if result.get("status") == "healthy":
            print(f"✓ API is healthy: {result.get('service')}")
            return True
        else:
            print("✗ API is not healthy")
            return False

    except requests.exceptions.ConnectionError:
        print("✗ Cannot connect to API")
        print("Make sure the API server is running:")
        print("  python3 create_video_api.py")
        return False

    except Exception as e:
        print(f"✗ Error checking health: {e}")
        return False


def main():
    """Main entry point"""

    print("=" * 60)
    print("Slides to Video API - Example Client")
    print("=" * 60)
    print()

    # Check health first
    if not health_check():
        sys.exit(1)

    print()
    print("=" * 60)
    print()

    # Create video
    create_video_example()

    print()
    print("=" * 60)
    print("Done!")
    print("=" * 60)


if __name__ == "__main__":
    main()
