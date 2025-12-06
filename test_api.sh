#!/usr/bin/env bash
# Example: Test the Slides to Video API using curl

set -euo pipefail

API_URL="${API_URL:-http://localhost:5000}"

echo "=========================================="
echo "Slides to Video API - cURL Examples"
echo "=========================================="
echo ""

# Health check
echo "1. Health Check"
echo "----------------------------------------"
echo "GET $API_URL/api/v1/health"
echo ""
curl -s "$API_URL/api/v1/health" | python3 -m json.tool
echo ""
echo ""

# Create video (you'll need to update paths to actual slide images)
echo "2. Create Video"
echo "----------------------------------------"
echo "POST $API_URL/api/v1/create-video"
echo ""

cat > /tmp/video-request.json <<'EOF'
{
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
EOF

echo "Request body:"
cat /tmp/video-request.json | python3 -m json.tool
echo ""
echo "Sending request..."
echo ""

curl -s -X POST "$API_URL/api/v1/create-video" \
  -H "Content-Type: application/json" \
  -d @/tmp/video-request.json | python3 -m json.tool

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="

# Cleanup
rm -f /tmp/video-request.json

