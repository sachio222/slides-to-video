#!/usr/bin/env python3
"""
Calculate the best contrasting color for a waveform based on image's dominant color
"""
import sys
import subprocess
import colorsys


def get_dominant_color(image_path):
    """Extract dominant RGB and calculate color variance"""
    # Get dominant color
    result = subprocess.run(
        ['magick', image_path, '-resize', '1x1', '-format',
            '%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]', 'info:-'],
        capture_output=True, text=True
    )
    r, g, b = map(int, result.stdout.strip().split(','))

    # Get standard deviation to measure color consistency
    result_std = subprocess.run(
        ['magick', image_path, '-format',
            '%[fx:standard_deviation.r*100],%[fx:standard_deviation.g*100],%[fx:standard_deviation.b*100]', 'info:-'],
        capture_output=True, text=True
    )
    std_r, std_g, std_b = map(float, result_std.stdout.strip().split(','))
    avg_variance = (std_r + std_g + std_b) / 3

    return r, g, b, avg_variance


def rgb_to_hsl(r, g, b):
    """Convert RGB (0-255) to HSL (0-1)"""
    return colorsys.rgb_to_hls(r/255, g/255, b/255)


def hsl_to_rgb(h, l, s):
    """Convert HSL (0-1) to RGB (0-255)"""
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return int(r*255), int(g*255), int(b*255)


def get_contrasting_color(r, g, b, variance):
    """Calculate color based on image consistency"""
    h, l, s = rgb_to_hsl(r, g, b)

    # Target: bright and saturated
    target_lightness = 0.65
    target_saturation = 0.95

    # If variance is low (<15), image is consistent → use analogous harmony
    # If variance is high (>15), image is varied → use complementary contrast

    if variance < 15:
        # Consistent color image → analogous (stay in same family)
        print(
            f"  → Low variance ({variance:.1f}) - using analogous harmony", file=sys.stderr)

        if s < 0.15:  # Gray
            # Warm gray → warm accent
            contrast_hue = 0.08  # Orange
        elif h < 0.17:  # Red/brown tones
            # Stay warm → orange/gold
            contrast_hue = 0.08  # Orange
        elif h < 0.42:  # Yellow/green
            # Stay warm → yellow
            contrast_hue = 0.15
        elif h < 0.75:  # Blue/cyan
            # Stay cool → bright cyan
            contrast_hue = 0.52
        else:  # Purple/magenta
            # Stay cool → bright magenta
            contrast_hue = 0.85
    else:
        # Varied color image → complementary (opposite on wheel)
        print(
            f"  → High variance ({variance:.1f}) - using complementary contrast", file=sys.stderr)
        contrast_hue = (h + 0.5) % 1.0

    # Generate contrasting color
    cr, cg, cb = hsl_to_rgb(contrast_hue, target_lightness, target_saturation)

    return f"#{cr:02X}{cg:02X}{cb:02X}"


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: calculate_contrast_color.py IMAGE_PATH", file=sys.stderr)
        sys.exit(1)

    image_path = sys.argv[1]
    r, g, b, variance = get_dominant_color(image_path)
    color = get_contrasting_color(r, g, b, variance)

    print(color)
