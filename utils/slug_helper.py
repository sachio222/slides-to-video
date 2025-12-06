#!/usr/bin/env python3
"""
Convert strings to filesystem-safe slugs
Matches the toSlug function in html-to-image service
"""
import sys
import unicodedata
import re


def to_slug(text):
    """
    Convert text to a filesystem-safe slug
    - Normalizes Unicode characters (NFD)
    - Removes diacritics
    - Converts to lowercase
    - Removes special characters
    - Replaces spaces with hyphens
    """
    if not text:
        return "slide"
    
    # Normalize to NFD (decompose accented characters)
    text = unicodedata.normalize('NFD', text)
    # Remove diacritics
    text = ''.join(c for c in text if unicodedata.category(c) != 'Mn')
    # Lowercase
    text = text.lower()
    # Remove special characters except word chars, spaces, hyphens
    text = re.sub(r'[^\w\s-]', '', text)
    # Replace spaces with hyphens
    text = re.sub(r'\s+', '-', text)
    # Collapse multiple hyphens
    text = re.sub(r'-+', '-', text)
    # Remove leading/trailing hyphens
    text = text.strip('-')
    
    return text if text else "slide"


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: slug_helper.py TEXT", file=sys.stderr)
        sys.exit(1)
    
    text = sys.argv[1]
    print(to_slug(text))


