# claude-code-kokoro-tts

A fork of [~cg/claude-code-tts](https://git.sr.ht/~cg/claude-code-tts) with **Japanese support**.

This project adds Japanese text-to-speech capability using [misaki\[ja\]](https://github.com/hexgrad/misaki) for proper kanji-to-phoneme conversion, on top of [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx).

## Key Features

- **Japanese phonemization** via misaki\[ja\] — handles kanji, hiragana, katakana correctly (kokoro-onnx's built-in espeak-ng reads kanji as "chinese letter")
- **Speed control** — adjustable speech rate via `--speed` flag
- **Mute toggle** — TTS mute/unmute via `/tts-mute` slash command
- **Audio ducking** (macOS) — automatically lowers music volume during TTS playback

## Prerequisites

- [uv](https://astral.sh/uv) — fast Python package manager
- [Claude Code](https://claude.ai/code)
- Model files (downloaded automatically by `install.sh`):
  - `kokoro-v1.0.onnx` (~310 MB)
  - `voices-v1.0.bin` (~25 MB)

## Installation

```bash
git clone https://github.com/jaxx2104/claude-code-kokoro-tts.git
cd claude-code-kokoro-tts
./install.sh
```

The installer will download model files, set up hooks in `~/.claude/hooks/`, and configure Claude Code settings.

### Manual Installation (Japanese TTS script only)

```bash
# Install dependencies
uv pip install kokoro-onnx misaki[ja] unidic-lite sounddevice numpy

# Run
echo "日本語テキスト" | python scripts/kokoro-tts-ja.py \
  --model ./kokoro-v1.0.onnx \
  --voices ./voices-v1.0.bin \
  --voice jf_alpha
```

## Configuration

### Voice

Set `KOKORO_VOICE` in `~/.claude/settings.json`:

```json
{
  "env": {
    "KOKORO_VOICE": "jf_alpha"
  }
}
```

Japanese voices: `jf_alpha`, `jf_gongitsune`, `jf_nezumi`, `jf_tebukuro`, `jm_kumo`

See [Kokoro VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md) for the full list (54 voices across 5 languages).

### Speed

```bash
python scripts/kokoro-tts-ja.py --speed 1.2 ...
```

Default is `1.0`. Higher values speak faster.

### Mute

Use the `/tts-mute` slash command in Claude Code to toggle TTS on/off.

### Audio Ducking (macOS)

```json
{
  "env": {
    "AUDIO_DUCK_ENABLED": "true",
    "DUCK_LEVEL": "5"
  }
}
```

Automatically lowers Apple Music volume to the specified percentage while TTS is playing.

## How It Works

1. Claude Code's hook system captures responses on the `Stop` event
2. Text is extracted and cleaned of markdown formatting
3. For Japanese, misaki\[ja\] converts text to phonemes (handling kanji correctly)
4. kokoro-onnx synthesizes speech from phonemes
5. Audio plays in the background; interrupted when a new prompt is submitted

## License

ISC License — see the [LICENSE](LICENSE) file for details.
