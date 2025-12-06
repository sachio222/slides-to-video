#!/usr/bin/env python3
"""
Example: Call the API with your actual offrir data
This replaces the SSH + bash script command

NOTE: Make sure the API server is running first with your credentials:
  cd /Users/jupiter/dev/docker/n8n-plus
  docker-compose up -d video-api
"""

import requests
import json

# API endpoint (update host if needed)
API_URL = "http://host.docker.internal:5000/api/v1/create-video"

# Your data from the original command
payload = {
    "date": "2025-12-06",
    "word": "offrir",
    "slides": [
        {
            "path": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-12-06-offrir/youtube-shorts/2025-12-06-offrir-youtube-shorts-slide-1.png",
            "type": "waveform"
        },
        {
            "path": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-12-06-offrir/youtube-shorts/2025-12-06-offrir-youtube-shorts-slide-2.png",
            "type": "definition"
        },
        {
            "path": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-12-06-offrir/youtube-shorts/2025-12-06-offrir-youtube-shorts-slide-3.png",
            "type": "examples"
        },
        {
            "path": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-12-06-offrir/youtube-shorts/2025-12-06-offrir-youtube-shorts-slide-4.png",
            "type": "mnemonic"
        },
        {
            "path": "/Users/jupiter/dev/woodshed/images/languageacademy/socials/2025-12-06-offrir/youtube-shorts/2025-12-06-offrir-youtube-shorts-slide-5.png",
            "type": "cta"
        }
    ],
    "content": {
        "slides": [
            {
                "type": "definition",
                "word": "offrir",
                "translation": "to offer",
                "pos": "verb",
                "level": "A2"
            },
            {
                "type": "examples",
                "examples": [
                    {
                        "note": "Basic transitive usage with indirect object",
                        "french": "J'offre une pomme à ma sœur.",
                        "context": "Giving a small gift · A1",
                        "english": "I give/offer an apple to my sister."
                    },
                    {
                        "note": "Passé composé with auxiliary avoir and past participle offert",
                        "french": "Il m'a offert un livre pour mon anniversaire.",
                        "context": "Past action / gift · A2",
                        "english": "He gave me a book for my birthday."
                    }
                ]
            },
            {
                "type": "mnemonic",
                "engagement": {
                    "hook": "'Offrir' looks like English 'offer'.",
                    "connection": "Both come from the same Latin root and mean nearly the same thing (to present/give).",
                    "reinforcement": "offrir = to offer (past: il a offert = he offered)"
                },
                "word": "offrir"
            }
        ]
    },
    "music": "camillesaentsaens-aquarium.mp3"
}

print("Sending request to create video...")
print(f"API: {API_URL}")
print(f"Word: {payload['word']}")
print(f"Date: {payload['date']}")
print(f"Slides: {len(payload['slides'])}")
print()

try:
    response = requests.post(API_URL, json=payload, timeout=300)
    result = response.json()

    if result.get("success"):
        print("✓ Video created successfully!")
        print("\nVideo files:")
        for video in result.get("videos", []):
            print(f"  {video}")
    else:
        print(f"✗ Error: {result.get('error')}")

except requests.exceptions.ConnectionError:
    print("✗ Cannot connect to API")
    print("Make sure the API server is running on the host")
except Exception as e:
    print(f"✗ Error: {e}")
