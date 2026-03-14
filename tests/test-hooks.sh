#!/bin/bash
# Test suite for TTS hook scripts
# Usage: bash tests/test-hooks.sh

set -euo pipefail

PASS=0
FAIL=0
HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)/hooks"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() {
  echo -e "  ${GREEN}PASS${NC} $1"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "  ${RED}FAIL${NC} $1: $2"
  FAIL=$((FAIL + 1))
}

# ============================================================
echo "=== Stop Hook ==="
# ============================================================

# --- Non-blocking ---
elapsed=$( {
  time echo '{"session_id":"test","transcript_path":"/tmp/nonexistent.jsonl","cwd":"/tmp","hook_event_name":"Stop"}' \
    | bash "$HOOK_DIR/tts-stop-hook.sh" 2>/dev/null
} 2>&1 | grep real | awk '{print $2}' )
seconds=$(echo "$elapsed" | sed 's/.*m//' | sed 's/s//')
if (( $(echo "$seconds < 1.0" | bc -l) )); then
  pass "non-blocking: returns within 1s (${seconds}s)"
else
  fail "non-blocking" "took ${seconds}s"
fi

# --- Mute check ---
touch /tmp/kokoro-mute
echo '{}' | bash "$HOOK_DIR/tts-stop-hook.sh" 2>/dev/null
exit_code=$?
rm -f /tmp/kokoro-mute
if [ $exit_code -eq 0 ]; then
  pass "mute: exits 0 when muted"
else
  fail "mute" "exit code: $exit_code"
fi

# ============================================================
echo ""
echo "=== Text Extraction (unit) ==="
# ============================================================

# Extract the text extraction logic from the hook and test it directly.
# This avoids depending on background process output.

extract_text() {
  local transcript="$1"
  local seen_tool_result=0
  local claude_response=""
  while IFS= read -r line; do
    message_type=$(echo "$line" | jq -r '.type' 2>/dev/null)
    if [ "$message_type" = "tool_result" ]; then
      seen_tool_result=1
    fi
    if [ "$message_type" = "assistant" ]; then
      TEXT=$(echo "$line" | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null | tr '\n' ' ')
      if [ -n "$TEXT" ]; then
        if [ "$seen_tool_result" != "1" ]; then
          claude_response="$TEXT"
          break
        fi
      fi
    fi
  done < <(tail -r "$transcript")
  echo "$claude_response"
}

# --- After tool_result ---
cat > "$TMPDIR/t1.jsonl" << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"I'll check the files."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","id":"tool1"}]}}
{"type":"tool_result","tool_use_id":"tool1","content":"file contents here"}
{"type":"assistant","message":{"content":[{"type":"text","text":"The file looks good."}]}}
EOF

result=$(extract_text "$TMPDIR/t1.jsonl")
if [[ "$result" == *"The file looks good."* ]]; then
  pass "extracts text after tool_result"
else
  fail "extracts text after tool_result" "got: $result"
fi

# --- No tools ---
cat > "$TMPDIR/t2.jsonl" << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Hello, simple response."}]}}
EOF

result=$(extract_text "$TMPDIR/t2.jsonl")
if [[ "$result" == *"Hello, simple response."* ]]; then
  pass "extracts text without tools"
else
  fail "extracts text without tools" "got: $result"
fi

# --- Skips pre-tool text ---
cat > "$TMPDIR/t3.jsonl" << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Let me check..."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","id":"tool1"}]}}
{"type":"tool_result","tool_use_id":"tool1","content":"ok"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Done, everything works."}]}}
EOF

result=$(extract_text "$TMPDIR/t3.jsonl")
if [[ "$result" == *"Done, everything works."* ]] && [[ "$result" != *"Let me check"* ]]; then
  pass "skips pre-tool text"
else
  fail "skips pre-tool text" "got: $result"
fi

# --- Tool-only response (no final text) ---
cat > "$TMPDIR/t4.jsonl" << 'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","id":"tool1"}]}}
{"type":"tool_result","tool_use_id":"tool1","content":"ok"}
EOF

result=$(extract_text "$TMPDIR/t4.jsonl")
if [ -z "$result" ]; then
  pass "returns empty for tool-only response"
else
  fail "returns empty for tool-only response" "got: $result"
fi

# ============================================================
echo ""
echo "=== TTS_SUMMARY Extraction (unit) ==="
# ============================================================

extract_summary() {
  local text="$1"
  echo "$text" | tr '\n' ' ' | awk '
    {
      start = index($0, "<!-- TTS_SUMMARY")
      if (start > 0) {
        rest = substr($0, start + 16)
        end = index(rest, "TTS_SUMMARY -->")
        if (end > 0) {
          content = substr(rest, 1, end - 1)
          gsub(/^[[:space:]]+/, "", content)
          gsub(/[[:space:]]+$/, "", content)
          print content
        }
      }
    }
  '
}

result=$(extract_summary "Technical details here.
<!-- TTS_SUMMARY
Brief summary for speech.
TTS_SUMMARY -->
More details.")
if [[ "$result" == "Brief summary for speech." ]]; then
  pass "extracts TTS_SUMMARY content"
else
  fail "extracts TTS_SUMMARY content" "got: $result"
fi

result=$(extract_summary "No markers here, just plain text.")
if [ -z "$result" ]; then
  pass "returns empty when no TTS_SUMMARY"
else
  fail "returns empty when no TTS_SUMMARY" "got: $result"
fi

# ============================================================
echo ""
echo "=== Interrupt Hook ==="
# ============================================================

bash "$HOOK_DIR/tts-interrupt-hook.sh" < /dev/null 2>/dev/null
if [ $? -eq 0 ]; then
  pass "exits 0 with no running process"
else
  fail "exits 0 with no running process" "exit code: $?"
fi

# ============================================================
echo ""
echo "=== Session End Hook ==="
# ============================================================

echo '{"session_id":"test","reason":"exit"}' \
  | bash "$HOOK_DIR/tts-session-end-hook.sh" 2>/dev/null
if [ $? -eq 0 ]; then
  pass "exits 0"
else
  fail "exits 0" "exit code: $?"
fi

# ============================================================
echo ""
echo "=== Results ==="
echo -e "  ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
[ $FAIL -eq 0 ] || exit 1
