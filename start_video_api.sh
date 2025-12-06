#!/usr/bin/env bash
# Start the Slides to Video API server
# Save as: start_video_api.sh

set -euo pipefail

cd /Users/jupiter/dev/woodshed/tts/slides-to-video

# Set environment variables
export HUME_API_KEY="GLDTVVEXsavYLcXsciY0x8ArzI7HccGwyhJ2ge6bClWb1GPl"
export HUME_FRENCH_VOICE="9e1f9e4f-691a-4bb0-b87c-e306a4c838ef"
export HUME_ENGLISH_VOICE="c7aa10be-57c1-4647-9306-7ac48dde3536"

# Start server (accessible from network)
echo "Starting Slides to Video API..."
echo "Accessible at: http://0.0.0.0:5000"
echo "From Docker: http://host.docker.internal:5000"
echo ""

python3 create_video_api.py --host 0.0.0.0 --port 5000
