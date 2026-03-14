#!/bin/bash
# Kokoro TTS Hook Installation Script for Claude Code
# This script sets up automatic TTS playback for Claude Code responses

set -e

echo "======================================"
echo "Kokoro TTS Hook Installer"
echo "======================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Cross-platform sed in-place editing
# macOS uses BSD sed which requires -i '' whereas GNU sed uses -i without argument
sed_in_place() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Check prerequisites
echo "Checking prerequisites..."

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Please install jq first:"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    echo "  macOS: brew install jq"
    echo "  Fedora: sudo dnf install jq"
    exit 1
fi

echo -e "${GREEN}OK${NC} jq is installed"
echo ""

# Create hooks directory
HOOKS_DIR="$HOME/.claude/hooks"
mkdir -p "$HOOKS_DIR"

# Create tts-stop-hook.sh by copying from hooks/ directory (single source of truth)
echo "Creating TTS playback hook..."
cp "$SCRIPT_DIR/hooks/tts-stop-hook.sh" "$HOOKS_DIR/tts-stop-hook.sh"

# Replace placeholders with actual paths
sed_in_place "s|__CLAUDE_TTS_PROJECT_DIR__|$SCRIPT_DIR|g" "$HOOKS_DIR/tts-stop-hook.sh"

# Create tts-interrupt-hook.sh by copying from hooks/ directory (single source of truth)
echo "Creating TTS interrupt hook..."
cp "$SCRIPT_DIR/hooks/tts-interrupt-hook.sh" "$HOOKS_DIR/tts-interrupt-hook.sh"

# Replace placeholders with actual paths
sed_in_place "s|__CLAUDE_TTS_PROJECT_DIR__|$SCRIPT_DIR|g" "$HOOKS_DIR/tts-interrupt-hook.sh"

# Create tts-session-end-hook.sh by copying from hooks/ directory (single source of truth)
echo "Creating SessionEnd TTS hook..."
cp "$SCRIPT_DIR/hooks/tts-session-end-hook.sh" "$HOOKS_DIR/tts-session-end-hook.sh"

# Make hooks executable
chmod +x "$HOOKS_DIR/tts-stop-hook.sh"
chmod +x "$HOOKS_DIR/tts-interrupt-hook.sh"
chmod +x "$HOOKS_DIR/tts-session-end-hook.sh"

echo -e "${GREEN}OK${NC} Hook scripts created and made executable"
echo ""

# Configure ~/.claude/settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Configuring Claude Code settings..."

# Create or update settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
    # Create new settings file
    cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "env": {
    "KOKORO_VOICE": "af_sky",
    "KOKORO_LANG": ""
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-interrupt-hook.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-stop-hook.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-session-end-hook.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
    echo -e "${GREEN}OK${NC} Created new settings.json with KOKORO_VOICE=af_sky"
else
    # Backup existing settings
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
    echo "Backed up existing settings to $SETTINGS_FILE.backup"

    # Merge hooks into existing settings and add KOKORO_VOICE if not present
    jq '.hooks.UserPromptSubmit = [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tts-interrupt-hook.sh", "timeout": 5}]}] |
        .hooks.Stop = [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tts-stop-hook.sh", "timeout": 10}]}] |
        .hooks.SessionEnd = [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tts-session-end-hook.sh", "timeout": 5}]}] |
        .env.KOKORO_VOICE //= "af_sky" |
        .env.KOKORO_LANG //= "" |
        .env.KOKORO_UV_BIN //= ""' \
        "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

    echo -e "${GREEN}OK${NC} Updated existing settings.json with TTS hooks and KOKORO_VOICE"
fi

echo ""
echo "======================================"
echo -e "${GREEN}Installation Complete!${NC}"
echo "======================================"
echo ""
echo "The following hooks have been installed:"
echo "  - Stop hook (TTS playback): ~/.claude/hooks/tts-stop-hook.sh"
echo "  - UserPromptSubmit hook (TTS interrupt): ~/.claude/hooks/tts-interrupt-hook.sh"
echo "  - SessionEnd hook (Cleanup): ~/.claude/hooks/tts-session-end-hook.sh"
echo ""
echo "Next steps:"
echo "  1. Start or restart Claude Code"
echo "  2. Claude's responses will be automatically read aloud"
echo "  3. Submit a new message to interrupt ongoing TTS playback"
echo ""
echo "To verify installation:"
echo "  - Run '/hooks' in Claude Code to see registered hooks"
echo "  - Check logs: tail -f /tmp/kokoro-hook.log"
echo ""
echo "To customize the voice, edit KOKORO_VOICE in:"
echo "  ~/.claude/settings.json"
echo "  (e.g. \"KOKORO_VOICE\": \"af_bella\")"
echo ""
echo "For troubleshooting, see README.md"
echo ""
