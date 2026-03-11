# claude-code-kokoro-tts

A fork of [~cg/claude-code-tts](https://git.sr.ht/~cg/claude-code-tts) with **multi-language support**.

This project adds multi-language text-to-speech capability using [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx), with [misaki\[ja\]](https://github.com/hexgrad/misaki) for proper Japanese kanji-to-phoneme conversion.

## Supported Languages

| Language | Code | Voice Prefix | Example Voices |
|----------|------|-------------|----------------|
| English  | `en` | `af_*`, `am_*`, `bf_*`, `bm_*` | `af_sky`, `af_bella`, `bm_george` |
| Japanese | `ja` | `jf_*`, `jm_*` | `jf_alpha`, `jf_gongitsune`, `jm_kumo` |
| French   | `fr` | `ff_*` | `ff_siwis` |
| German   | `de` | `gf_*` | `gf_pilgrim` |
| Spanish  | `es` | `ef_*`, `em_*` | `ef_dora`, `em_alex` |

See [Kokoro VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md) for the full list (54 voices across 5 languages).

## Key Features

- **Multi-language support** -- 5 languages with automatic language detection from voice name
- **Japanese phonemization** via misaki\[ja\] -- handles kanji, hiragana, katakana correctly (kokoro-onnx's built-in espeak-ng reads kanji as "chinese letter")
- **Speed control** -- adjustable speech rate via `--speed` flag
- **Mute toggle** -- TTS mute/unmute via `/tts-mute` slash command
- **Audio ducking** (macOS) -- automatically lowers music volume during TTS playback

## Prerequisites

- [uv](https://astral.sh/uv) -- fast Python package manager
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

### Manual Installation

```bash
# Install dependencies
uv pip install kokoro-onnx sounddevice numpy

# For Japanese support, also install:
uv pip install misaki[ja] unidic-lite

# Run (English)
echo "Hello world" | python scripts/kokoro-tts.py \
  --model ./kokoro-v1.0.onnx \
  --voices ./voices-v1.0.bin \
  --voice af_sky

# Run (Japanese)
echo "日本語テキスト" | python scripts/kokoro-tts.py \
  --model ./kokoro-v1.0.onnx \
  --voices ./voices-v1.0.bin \
  --voice jf_alpha
```

## Configuration

### Voice & Language

Set `KOKORO_VOICE` and optionally `KOKORO_LANG` in `~/.claude/settings.json`:

```json
{
  "env": {
    "KOKORO_VOICE": "af_sky",
    "KOKORO_LANG": ""
  }
}
```

**Language is auto-detected from the voice name prefix** -- you usually don't need to set `KOKORO_LANG`. Just change the voice and the language switches automatically:

```json
{ "env": { "KOKORO_VOICE": "af_sky" } }
```
Uses English automatically.

```json
{ "env": { "KOKORO_VOICE": "jf_alpha" } }
```
Uses Japanese automatically.

```json
{ "env": { "KOKORO_VOICE": "ff_siwis" } }
```
Uses French automatically.

If you need to override the auto-detection, set `KOKORO_LANG` explicitly:

```json
{
  "env": {
    "KOKORO_VOICE": "af_sky",
    "KOKORO_LANG": "en"
  }
}
```

### Speed

```bash
python scripts/kokoro-tts.py --speed 1.2 ...
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
3. Language is auto-detected from the voice name prefix (or set via `KOKORO_LANG`)
4. For Japanese, misaki\[ja\] converts text to phonemes (handling kanji correctly)
5. For other languages, kokoro-onnx's built-in espeak-ng handles phonemization
6. kokoro-onnx synthesizes speech
7. Audio plays in the background; interrupted when a new prompt is submitted

## License

ISC License -- see the [LICENSE](LICENSE) file for details.
