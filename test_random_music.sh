#!/usr/bin/env bash
# Test random music selection feature

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the select_random_music function from main script
# Extract and test it standalone

select_random_music() {
  local date="$1"
  local music_dir="${SCRIPT_DIR}/bg-music"
  
  if [ ! -d "$music_dir" ]; then
    echo ""
    return
  fi
  
  local -a music_files=()
  while IFS= read -r -d '' file; do
    music_files+=("$file")
  done < <(find "$music_dir" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.m4a" -o -name "*.ogg" \) -print0 2>/dev/null | sort -z)
  
  if [ ${#music_files[@]} -eq 0 ]; then
    echo ""
    return
  fi
  
  local seed="${date//-/}"
  seed=$(echo "$seed" | sed 's/[^0-9]//g')
  
  if [ -z "$seed" ]; then
    seed=1
  fi
  
  local index=$((seed % ${#music_files[@]}))
  
  echo "${music_files[$index]}"
}

echo "=== Testing Random Music Selection ==="
echo ""

# Test different dates
test_dates=("2025-11-28" "2025-11-29" "2025-11-30" "2025-12-01" "2025-12-05")

echo "Available music files:"
find "${SCRIPT_DIR}/bg-music" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.wav" \) 2>/dev/null | sort | while read -r file; do
  echo "  - $(basename "$file")"
done
echo ""

echo "Testing date-based selection:"
for date in "${test_dates[@]}"; do
  selected=$(select_random_music "$date")
  if [ -n "$selected" ]; then
    echo "  $date -> $(basename "$selected")"
  else
    echo "  $date -> (no music found)"
  fi
done

echo ""
echo "✅ Random music selection test complete"


