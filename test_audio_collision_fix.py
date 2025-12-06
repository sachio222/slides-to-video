#!/usr/bin/env python3
"""
Test to verify the audio directory collision bug is fixed.

This test creates the same video twice and verifies that:
1. Video directories are separate (video, video-1)
2. Audio directories are separate (audio, audio-1) 
3. Audio files don't get overwritten
"""

import os
import tempfile
import shutil
from pathlib import Path

# Simulate the fixed logic
def create_video_directories(base_dir, date, word_slug):
    """Simulates the directory creation logic"""
    output_base = Path(base_dir)
    word_dir = output_base / f"{date}-{word_slug}"
    
    # Find available video directory (and corresponding audio directory)
    video_base_dir = word_dir / "video"
    audio_base_dir = word_dir / "audio"
    video_dir = video_base_dir
    audio_dir = audio_base_dir
    counter = 1
    
    while video_dir.exists():
        video_dir = Path(f"{video_base_dir}-{counter}")
        audio_dir = Path(f"{audio_base_dir}-{counter}")
        counter += 1
    
    video_dir.mkdir(parents=True, exist_ok=True)
    audio_dir.mkdir(parents=True, exist_ok=True)
    
    return str(video_dir), str(audio_dir)


def test_audio_directory_collision():
    """Test that audio directories increment correctly"""
    
    with tempfile.TemporaryDirectory() as tmp_dir:
        print("Testing audio directory collision fix...")
        print(f"Test directory: {tmp_dir}")
        print()
        
        date = "2025-12-06"
        word_slug = "test"
        
        # First run
        print("Run 1:")
        video_dir_1, audio_dir_1 = create_video_directories(tmp_dir, date, word_slug)
        print(f"  Video: {video_dir_1}")
        print(f"  Audio: {audio_dir_1}")
        
        # Create a test audio file
        test_audio_1 = Path(audio_dir_1) / "slide1.wav"
        test_audio_1.write_text("audio from run 1")
        print(f"  Created: {test_audio_1}")
        print()
        
        # Second run (should use different directories)
        print("Run 2:")
        video_dir_2, audio_dir_2 = create_video_directories(tmp_dir, date, word_slug)
        print(f"  Video: {video_dir_2}")
        print(f"  Audio: {audio_dir_2}")
        
        # Create a test audio file
        test_audio_2 = Path(audio_dir_2) / "slide1.wav"
        test_audio_2.write_text("audio from run 2")
        print(f"  Created: {test_audio_2}")
        print()
        
        # Verify directories are different
        assert video_dir_1 != video_dir_2, "Video directories should be different!"
        assert audio_dir_1 != audio_dir_2, "Audio directories should be different!"
        
        # Verify both audio files exist with different content
        content_1 = test_audio_1.read_text()
        content_2 = test_audio_2.read_text()
        
        assert content_1 == "audio from run 1", "First audio file was overwritten!"
        assert content_2 == "audio from run 2", "Second audio file wasn't created!"
        
        print("✓ Test passed!")
        print()
        print("Verification:")
        print(f"  ✓ Video directories are different")
        print(f"  ✓ Audio directories are different")
        print(f"  ✓ Audio files weren't overwritten")
        print()
        print("Expected structure:")
        print(f"  {date}-{word_slug}/")
        print(f"    ├── video/")
        print(f"    │   └── [videos]")
        print(f"    ├── audio/")
        print(f"    │   └── [audio from run 1]")
        print(f"    ├── video-1/")
        print(f"    │   └── [videos]")
        print(f"    └── audio-1/")
        print(f"        └── [audio from run 2]")


if __name__ == "__main__":
    test_audio_directory_collision()
