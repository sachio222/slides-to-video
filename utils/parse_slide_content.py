#!/usr/bin/env python3
"""
Parse slide content JSON into slide-specific text and audio instructions
"""
import json
import sys
import re


def parse_slide_content(json_str):
    """
    Parse slide content JSON and extract text for each slide
    Returns a dictionary with slide2, slide3 (parts), slide4, slide4_language, slide5
    """
    data = json.loads(json_str)
    
    # Slide 2: definition - just English translation
    slide2_text = ""
    for slide in data:
        if slide.get("type") == "definition":
            slide2_text = slide.get("translation", "")
            break
    
    # Slide 3: examples - English first, pause, then French, repeat
    slide3_parts = []
    for slide in data:
        if slide.get("type") == "examples":
            examples = slide.get("examples", [])
            for ex in examples:
                slide3_parts.append(ex.get("english", ""))
                slide3_parts.append("PAUSE")
                slide3_parts.append(ex.get("french", ""))
            break
    
    # Slide 4: mnemonic or quiz - variable format
    # Mnemonic: hook + connection + reinforcement (English)
    # Quiz: question text (French)
    slide4_text = ""
    slide4_language = "en"  # Default to English
    for slide in data:
        if slide.get("type") == "mnemonic":
            engagement = slide.get("engagement", {})
            hook = engagement.get("hook", "").replace("'", "")
            connection = engagement.get("connection", "").replace("'", "")
            reinforcement = engagement.get("reinforcement", "").replace("'", "").replace("=", " means ")
            parts = [p for p in [hook, connection, reinforcement] if p]
            slide4_text = ". ".join(parts)
            slide4_language = "en"  # Mnemonic is English
            break
        elif slide.get("type") == "quiz":
            engagement = slide.get("engagement", {})
            question = engagement.get("question", "")
            options = engagement.get("options", [])
            
            # Replace underscores (blank) of variable length with "Blank" (English)
            question = re.sub(r'_+', ' Blank ', question)
            question = re.sub(r'\s+', ' ', question).strip()  # Normalize whitespace
            # Remove trailing punctuation to avoid double periods when joining
            question = question.rstrip('.!?')
            
            # Build quiz text: question (French) + options (labeled A/B/C/D, options in French) + prompt (English)
            parts = [question]
            
            # Add each option with label (A, B, C, D) - options read in French
            option_labels = ["A", "B", "C", "D"]
            for i, option in enumerate(options):
                if i < len(option_labels):
                    parts.append(f"{option_labels[i]}): {option}")
            
            # Add "Comment your response below!" at the end (English)
            parts.append("Comment your response below!")
            
            slide4_text = ". ".join(parts)
            slide4_language = "fr"  # Quiz is primarily French (options are French words)
            break
    
    # Slide 5: CTA - merci beaucoup! like, follow and share. Visit language academy dot io today!
    slide5_text = "Merci beaucoup! Like, follow and share. Visit language academy dot io today!"
    
    # Output as JSON for bash to parse
    output = {
        "slide2": slide2_text,
        "slide3": slide3_parts,
        "slide4": slide4_text,
        "slide4_language": slide4_language,
        "slide5": slide5_text
    }
    return output


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: parse_slide_content.py JSON_STRING", file=sys.stderr)
        sys.exit(1)
    
    json_str = sys.argv[1]
    try:
        result = parse_slide_content(json_str)
        print(json.dumps(result))
    except Exception as e:
        print(f"Error parsing slide content: {e}", file=sys.stderr)
        sys.exit(1)


