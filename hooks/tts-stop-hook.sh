#!/bin/bash
# Claude Code TTS Hook - Reads Claude's responses using kokoro-tts

# Voice configuration - can be set via env vars in ~/.claude/settings.json
VOICE="${KOKORO_VOICE:-af_sky}"
SPEED="${KOKORO_SPEED:-1.0}"
LANG="${KOKORO_LANG:-}"  # Auto-detected from voice if empty

# Audio ducking configuration - lowers Apple Music volume while TTS plays (like Google Maps in CarPlay)
# macOS only - uses AppleScript to control Apple Music's internal volume
AUDIO_DUCK_ENABLED="${AUDIO_DUCK_ENABLED:-true}"
AUDIO_DUCK_SCRIPT="$HOME/.claude/scripts/audio-duck.sh"

# Mute check - skip TTS if mute file exists (toggle via /tts-mute command)
if [ -f /tmp/kokoro-mute ]; then
  exit 0
fi

# Debug logging
echo "[$(date)] Kokoro TTS hook triggered" >> /tmp/kokoro-hook.log

# Small delay to avoid race condition where transcript isn't fully written yet
sleep 1

# Read the hook input JSON from stdin
input=$(cat)

# Debug: Log the input
echo "[$(date)] Hook input: $input" >> /tmp/kokoro-hook.log

# Extract the transcript path
transcript_path=$(echo "$input" | jq -r '.transcript_path')

# Debug: Log the transcript path
echo "[$(date)] Transcript path: $transcript_path" >> /tmp/kokoro-hook.log

# Expand tilde to home directory if present
transcript_path="${transcript_path/#\~/$HOME}"

# Check if transcript file exists
if [ ! -f "$transcript_path" ]; then
  echo "[$(date)] Transcript file not found: $transcript_path" >> /tmp/kokoro-hook.log
  exit 0
fi

# Extract Claude's last response from the transcript
# Loop through messages in reverse to find text that appears AFTER tool uses completed
# This prevents reading text that PreToolUse hook already played
# NOTE: Using process substitution < <(tail -r ...) instead of pipe to avoid subshell variable scope issues
# Using tail -r instead of tac for macOS compatibility
seen_tool_result=0
claude_response=""
while IFS= read -r line; do
  message_type=$(echo "$line" | jq -r '.type' 2>/dev/null)

  # Once we see a tool_result, we know tools have been used
  if [ "$message_type" = "tool_result" ]; then
    seen_tool_result=1
  fi

  # Look for assistant text messages
  if [ "$message_type" = "assistant" ]; then
    TEXT=$(echo "$line" | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null | tr '\n' ' ')

    # Only use text if we haven't seen any tool_results yet (meaning this is final response after tools)
    # OR if we never saw tool_results (meaning no tools were used)
    if [ -n "$TEXT" ]; then
      if [ "$seen_tool_result" != "1" ]; then
        claude_response="$TEXT"
        break
      fi
    fi
  fi
done < <(tail -r "$transcript_path")
# Truncate to 5000 characters
claude_response="${claude_response:0:5000}"

# Debug: Log what was extracted
echo "[$(date)] Extracted response: $claude_response" >> /tmp/kokoro-hook.log

# Only proceed if we got a response
if [ -n "$claude_response" ]; then
  echo "[$(date)] Sending to kokoro-tts with $VOICE voice" >> /tmp/kokoro-hook.log
  echo "[$(date)] Response length: ${#claude_response}" >> /tmp/kokoro-hook.log

  # Check if response contains TTS_SUMMARY marker
  if echo "$claude_response" | grep -q "<!-- TTS_SUMMARY"; then
    # Extract only the TTS_SUMMARY content
    # Note: $claude_response is already flattened to a single line by tr '\n' ' ' earlier
    # Uses awk with index() to extract text between markers on a single line
    tts_summary=$(echo "$claude_response" | awk '
      {
        start = index($0, "<!-- TTS_SUMMARY")
        if (start > 0) {
          rest = substr($0, start + 16)  # 16 = length("<!-- TTS_SUMMARY")
          end = index(rest, "TTS_SUMMARY -->")
          if (end > 0) {
            content = substr(rest, 1, end - 1)
            gsub(/^[[:space:]]+/, "", content)
            gsub(/[[:space:]]+$/, "", content)
            print content
          }
        }
      }
    ')

    if [ -n "$tts_summary" ]; then
      echo "[$(date)] Found TTS_SUMMARY, using summary content only" >> /tmp/kokoro-hook.log
      # Strip any markdown from TTS_SUMMARY content (e.g., **bold** -> bold)
      claude_response=$(echo "$tts_summary" | uv run --with mistune python "$HOME/.claude/scripts/strip_markdown.py" 2>>/tmp/kokoro-hook.log || echo "$tts_summary")
    else
      echo "[$(date)] TTS_SUMMARY marker found but empty, falling back to full response" >> /tmp/kokoro-hook.log
    fi
  else
    echo "[$(date)] No TTS_SUMMARY found, stripping markdown via strip_markdown.py" >> /tmp/kokoro-hook.log

    # Strip markdown formatting using mistune Python library
    claude_response=$(echo "$claude_response" | uv run --with mistune python "$HOME/.claude/scripts/strip_markdown.py" 2>>/tmp/kokoro-hook.log || echo "$claude_response")
  fi

  echo "[$(date)] Final response for TTS (length: ${#claude_response})" >> /tmp/kokoro-hook.log

  # Kill any existing TTS processes to prevent overlapping audio
  # This ensures the final response "wins" over any PreToolUse audio still playing
  if pkill -9 -f kokoro-tts 2>/dev/null; then
    echo "[$(date)] Killed existing kokoro-tts process" >> /tmp/kokoro-hook.log
  fi

  # Save response to secure temp file to avoid pipe blocking issues
  # Use mktemp with restrictive permissions for security
  tmpfile=$(mktemp /tmp/kokoro-input.XXXXXX)
  chmod 600 "$tmpfile"
  echo "$claude_response" > "$tmpfile"

  # Audio ducking: lower other audio before TTS starts
  if [ "$AUDIO_DUCK_ENABLED" = "true" ] && [ -x "$AUDIO_DUCK_SCRIPT" ]; then
    echo "[$(date)] Ducking audio before TTS" >> /tmp/kokoro-hook.log
    "$AUDIO_DUCK_SCRIPT" duck
  fi

  # Build uv run command with language-appropriate dependencies
  UV_DEPS="--with kokoro-onnx --with sounddevice"
  # Determine effective language for dependency selection
  EFFECTIVE_LANG="$LANG"
  if [ -z "$EFFECTIVE_LANG" ]; then
    # Auto-detect from voice prefix (j=ja, a/b=en, f=fr, g=de, e=es)
    case "${VOICE:0:1}" in
      j) EFFECTIVE_LANG="ja" ;;
      a|b) EFFECTIVE_LANG="en" ;;
      f) EFFECTIVE_LANG="fr" ;;
      g) EFFECTIVE_LANG="de" ;;
      e) EFFECTIVE_LANG="es" ;;
      *) EFFECTIVE_LANG="en" ;;
    esac
  fi
  if [ "$EFFECTIVE_LANG" = "ja" ]; then
    UV_DEPS="$UV_DEPS --with misaki[ja] --with unidic-lite"
  fi

  # Build --lang argument
  LANG_ARG=""
  if [ -n "$LANG" ]; then
    LANG_ARG="--lang $LANG"
  fi

  # Run kokoro-tts.py in background and capture PID for audio ducking restore
  UV_NATIVE_TLS=1 uv run $UV_DEPS \
    python "$HOME/.claude/scripts/kokoro-tts.py" "$tmpfile" \
    --voice "$VOICE" --speed "$SPEED" $LANG_ARG --model "$HOME/.local/share/kokoro-tts/kokoro-v1.0.onnx" \
    --voices "$HOME/.local/share/kokoro-tts/voices-v1.0.bin" >>/tmp/kokoro-hook.log 2>&1 &
  TTS_PID=$!
  echo "[$(date)] Started kokoro-tts with PID: $TTS_PID" >> /tmp/kokoro-hook.log

  # In background: wait for TTS to finish, then restore audio volume
  if [ "$AUDIO_DUCK_ENABLED" = "true" ] && [ -x "$AUDIO_DUCK_SCRIPT" ]; then
    (
      while kill -0 "$TTS_PID" 2>/dev/null; do
        sleep 0.5
      done
      echo "[$(date)] TTS finished, restoring audio" >> /tmp/kokoro-hook.log
      "$AUDIO_DUCK_SCRIPT" restore
    ) &
  fi
else
  echo "[$(date)] No response found" >> /tmp/kokoro-hook.log
fi

# Exit successfully (non-blocking)
exit 0
