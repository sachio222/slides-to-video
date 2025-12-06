#!/usr/bin/env python3
"""
Parse slide content JSON once and export to shell-sourceable format
This avoids repeated Python invocations from bash
"""
import json
import sys
import re


def shell_escape(text):
    """Escape text for safe shell variable assignment"""
    if not text:
        return "''"
    # Escape single quotes
    text = text.replace("'", "'\"'\"'")
    return f"'{text}'"


def parse_slide_content(json_str):
    """
    Parse slide content JSON and export as shell variables
    """
    try:
        data = json.loads(json_str)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)
    
    result = []
    
    # Slide 2: definition - just English translation
    slide2_text = ""
    for slide in data:
        if slide.get("type") == "definition":
            slide2_text = slide.get("translation", "")
            break
    result.append(f"SLIDE_CONTENT_SLIDE2={shell_escape(slide2_text)}")
    
    # Slide 3: examples - store as array elements
    slide3_parts = []
    for slide in data:
        if slide.get("type") == "examples":
            examples = slide.get("examples", [])
            for ex in examples:
                slide3_parts.append(ex.get("english", ""))
                slide3_parts.append("PAUSE")
                slide3_parts.append(ex.get("french", ""))
            break
    
    # Export as pipe-delimited string for bash array splitting
    result.append(f"SLIDE_CONTENT_SLIDE3={shell_escape('|'.join(slide3_parts))}")
    
    # Slide 4: mnemonic or quiz - variable format
    slide4_text = ""
    slide4_language = "en"
    for slide in data:
        if slide.get("type") == "mnemonic":
            engagement = slide.get("engagement", {})
            hook = engagement.get("hook", "").replace("'", "")
            connection = engagement.get("connection", "").replace("'", "")
            reinforcement = engagement.get("reinforcement", "").replace("'", "").replace("=", " means ")
            parts = [p for p in [hook, connection, reinforcement] if p]
            slide4_text = ". ".join(parts)
            slide4_language = "en"
            break
        elif slide.get("type") == "quiz":
            engagement = slide.get("engagement", {})
            question = engagement.get("question", "")
            options = engagement.get("options", [])
            
            # Replace underscores with "Blank"
            question = re.sub(r'_+', ' Blank ', question)
            question = re.sub(r'\s+', ' ', question).strip()
            question = question.rstrip('.!?')
            
            parts = [question]
            option_labels = ["A", "B", "C", "D"]
            for i, option in enumerate(options):
                if i < len(option_labels):
                    parts.append(f"{option_labels[i]}): {option}")
            parts.append("Comment your response below!")
            
            slide4_text = ". ".join(parts)
            slide4_language = "fr"
            break
    
    result.append(f"SLIDE_CONTENT_SLIDE4={shell_escape(slide4_text)}")
    result.append(f"SLIDE_CONTENT_SLIDE4_LANG={shell_escape(slide4_language)}")
    
    # Slide 5: CTA
    slide5_text = "Merci beaucoup! Like, follow and share. Visit language academy dot io today!"
    result.append(f"SLIDE_CONTENT_SLIDE5={shell_escape(slide5_text)}")
    
    # Output all variables
    return '\n'.join(result)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: cache_slide_content.py JSON_STRING", file=sys.stderr)
        sys.exit(1)
    
    json_str = sys.argv[1]
    try:
        output = parse_slide_content(json_str)
        print(output)
    except Exception as e:
        print(f"Error parsing slide content: {e}", file=sys.stderr)
        sys.exit(1)


