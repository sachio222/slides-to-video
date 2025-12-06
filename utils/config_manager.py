#!/usr/bin/env python3
"""
Configuration management for slides-to-video
Provides default configuration with optional YAML override
"""
import os
import sys
import json

# Try to import yaml, but make it optional
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False


DEFAULT_CONFIG = {
    "paths": {
        "script_dir": "/Users/jupiter/dev/woodshed/tts/slides-to-video",
        "output_base": "/Users/jupiter/dev/woodshed/images/languageacademy/socials",
        "homebrew_bin": "/opt/homebrew/bin",
        "local_bin": "/usr/local/bin"
    },
    "video": {
        "default_width": 1080,
        "default_height": 1920,
        "format": "mp4",
        "video_bitrate": "4000k",
        "audio_bitrate": "192k",
        "preset": "medium",
        "crf": 23
    },
    "audio": {
        "sample_rate": 48000,
        "channels": "mono",
        "trailing_silence": 1.0,
        "leading_silence": 0.15,
        "pause_duration": 1.0
    },
    "tts": {
        "provider": "hume",
        "french_voice": "claire",
        "english_voice": "claire",
        "version": "2",
        "retry_attempts": 3,
        "retry_delay": 1.0
    },
    "music": {
        "volume": 0.15,
        "fade_duration": 3.0,
        "compressor_threshold": 0.02,
        "compressor_ratio": 8,
        "compressor_attack": 20,
        "compressor_release": 200
    },
    "waveform": {
        "height_percent": 30,
        "mode": "bar",
        "ascale": "log",
        "alpha": 0.65,
        "bass_rolloff": 80
    }
}


def load_config(config_file=None):
    """
    Load configuration from file if provided, otherwise use defaults
    Environment variables override config file values
    """
    config = DEFAULT_CONFIG.copy()
    
    # Load from file if provided and exists
    if config_file and os.path.exists(config_file):
        if not HAS_YAML:
            print("Warning: PyYAML not installed, ignoring config file", file=sys.stderr)
        else:
            try:
                with open(config_file, 'r') as f:
                    file_config = yaml.safe_load(f)
                    if file_config:
                        # Deep merge
                        for section, values in file_config.items():
                            if section in config and isinstance(values, dict):
                                config[section].update(values)
                            else:
                                config[section] = values
            except Exception as e:
                print(f"Warning: Failed to load config file: {e}", file=sys.stderr)
    
    # Environment variables override everything
    if os.environ.get("HUME_FRENCH_VOICE"):
        config["tts"]["french_voice"] = os.environ["HUME_FRENCH_VOICE"]
    if os.environ.get("HUME_ENGLISH_VOICE"):
        config["tts"]["english_voice"] = os.environ["HUME_ENGLISH_VOICE"]
    
    return config


def get_config_value(config, *keys):
    """
    Get nested config value by key path
    Example: get_config_value(config, "video", "default_width")
    """
    value = config
    for key in keys:
        if isinstance(value, dict):
            value = value.get(key)
        else:
            return None
    return value


if __name__ == '__main__':
    # Usage: config_manager.py [config_file] [key.path]
    config_file = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != "-" else None
    key_path = sys.argv[2] if len(sys.argv) > 2 else None
    
    config = load_config(config_file)
    
    if key_path:
        # Get specific value
        keys = key_path.split('.')
        value = get_config_value(config, *keys)
        if value is not None:
            print(json.dumps(value) if isinstance(value, (dict, list)) else value)
        else:
            print(f"Error: Key '{key_path}' not found", file=sys.stderr)
            sys.exit(1)
    else:
        # Print entire config as JSON
        print(json.dumps(config, indent=2))


