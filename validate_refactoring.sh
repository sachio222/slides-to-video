#!/usr/bin/env bash
# Quick validation script for refactored slides-to-video
# Tests that all utilities are in place and working

set -uo pipefail  # Don't use -e, we want to test all items

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/utils"

echo "=== Slides-to-Video Refactoring Validation ==="
echo ""

# Track results
PASSED=0
FAILED=0

test_result() {
  local name="$1"
  local result="$2"
  if [ "$result" = "0" ]; then
    echo "✅ $name"
    ((PASSED++))
  else
    echo "❌ $name"
    ((FAILED++))
  fi
}

# Test 1: File structure
echo "1. Checking file structure..."
[ -f "${SCRIPT_DIR}/create_multi_slide_video_hume.sh" ] && \
[ -f "${SCRIPT_DIR}/create_multi_slide_video_hume_v2.sh" ] && \
[ -f "${UTILS_DIR}/slug_helper.py" ] && \
[ -f "${UTILS_DIR}/parse_slide_content.py" ] && \
[ -f "${UTILS_DIR}/config_manager.py" ] && \
[ -f "${SCRIPT_DIR}/config.yaml.example" ]
test_result "File structure" $?

# Test 2: Scripts are executable
echo "2. Checking executability..."
[ -x "${SCRIPT_DIR}/create_multi_slide_video_hume_v2.sh" ] && \
[ -x "${UTILS_DIR}/slug_helper.py" ] && \
[ -x "${UTILS_DIR}/parse_slide_content.py" ] && \
[ -x "${UTILS_DIR}/config_manager.py" ]
test_result "Executable permissions" $?

# Test 3: Python utilities syntax check
echo "3. Validating Python syntax..."
python3 -m py_compile "${UTILS_DIR}/slug_helper.py" 2>/dev/null && \
python3 -m py_compile "${UTILS_DIR}/parse_slide_content.py" 2>/dev/null && \
python3 -m py_compile "${UTILS_DIR}/config_manager.py" 2>/dev/null
test_result "Python syntax" $?

# Test 4: Slug helper functionality
echo "4. Testing slug helper..."
SLUG_RESULT=$(python3 "${UTILS_DIR}/slug_helper.py" "première" 2>/dev/null)
[ "$SLUG_RESULT" = "premiere" ]
test_result "Slug helper" $?

# Test 5: Config manager defaults
echo "5. Testing config manager..."
CONFIG_OUTPUT=$(python3 "${UTILS_DIR}/config_manager.py" - "video.default_width" 2>/dev/null)
[ "$CONFIG_OUTPUT" = "1080" ]
test_result "Config manager" $?

# Test 6: JSON parser with sample data
echo "6. Testing JSON parser..."
SAMPLE_JSON='[{"type":"definition","translation":"first"}]'
PARSE_RESULT=$(python3 "${UTILS_DIR}/parse_slide_content.py" "$SAMPLE_JSON" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['slide2'])" 2>/dev/null)
[ "$PARSE_RESULT" = "first" ]
test_result "JSON parser" $?

# Test 7: Bash script syntax
echo "7. Validating bash syntax..."
bash -n "${SCRIPT_DIR}/create_multi_slide_video_hume_v2.sh" 2>/dev/null
test_result "Bash syntax" $?

# Test 8: Documentation exists
echo "8. Checking documentation..."
[ -f "${SCRIPT_DIR}/README.md" ] && \
[ -f "${SCRIPT_DIR}/MIGRATION.md" ] && \
[ -f "${SCRIPT_DIR}/REFACTORING_SUMMARY.md" ]
test_result "Documentation" $?

# Test 9: Config YAML is valid
echo "9. Validating config YAML..."
if python3 -c "import yaml" 2>/dev/null; then
  python3 <<EOF 2>/dev/null
import yaml
with open("${SCRIPT_DIR}/config.yaml.example", 'r') as f:
    yaml.safe_load(f)
EOF
  test_result "Config YAML" $?
else
  echo "⚠️  Config YAML (PyYAML not installed, skipping)"
fi

# Test 10: Dependencies check function
echo "10. Testing dependency validation..."
grep -q "validate_dependencies()" "${SCRIPT_DIR}/create_multi_slide_video_hume_v2.sh"
test_result "Dependency validation function" $?

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
  echo "🎉 All validation tests passed!"
  echo ""
  echo "Next steps:"
  echo "  1. Test with actual slide images and content"
  echo "  2. Compare output with original script"
  echo "  3. Try variable slide counts"
  echo "  4. Create custom config.yaml if needed"
  exit 0
else
  echo "⚠️  Some tests failed. Please review the errors above."
  exit 1
fi

