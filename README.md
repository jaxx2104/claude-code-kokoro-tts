# claude-code-kokoro-tts

A fork of [~cg/claude-code-tts](https://git.sr.ht/~cg/claude-code-tts) with **multi-language support**.

This project adds multi-language text-to-speech capability using [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx), with [misaki\[ja\]](https://github.com/hexgrad/misaki) for proper Japanese kanji-to-phoneme conversion.

## Key Features

- **Multi-language support** -- 5 languages with automatic language detection from voice name
- **Japanese phonemization** via misaki\[ja\] -- handles kanji, hiragana, katakana correctly (kokoro-onnx's built-in espeak-ng reads kanji as "chinese letter")
- **Speed control** -- adjustable speech rate via `--speed` flag
- **Mute toggle** -- TTS mute/unmute via `/tts-mute` slash command
- **Audio ducking** (macOS) -- automatically lowers music volume during TTS playback

## Prerequisites

- [uv](https://astral.sh/uv) -- fast Python package manager
- [Claude Code](https://claude.ai/code)

## Installation

```bash
git clone https://github.com/jaxx2104/claude-code-kokoro-tts.git
cd claude-code-kokoro-tts
./install.sh
```

The installer will download model files, set up hooks in `~/.claude/hooks/`, and configure Claude Code settings.

## Configuration

### Voice & Language

Set `KOKORO_VOICE` in `~/.claude/settings.json`. Language is auto-detected from the voice name prefix (`af_*`=English, `jf_*`=Japanese, etc.):

```json
{ "env": { "KOKORO_VOICE": "jf_alpha" } }
```

To override auto-detection, set `KOKORO_LANG` explicitly (e.g. `"en"`, `"ja"`, `"fr"`).

### uv binary path

If `uv` is not available via `~/.local/share/mise/shims` (e.g. projects without `uv` in `.tool-versions`), set `KOKORO_UV_BIN` to the absolute path of the `uv` binary:

```json
{ "env": { "KOKORO_UV_BIN": "/path/to/uv" } }
```

## License

ISC License -- see the [LICENSE](LICENSE) file for details.
