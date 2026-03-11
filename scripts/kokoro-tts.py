#!/usr/bin/env python3
"""Multi-language TTS using kokoro_onnx.

Supports 5 languages: English (en), Japanese (ja), French (fr), German (de), Spanish (es).
For Japanese, uses misaki[ja] for proper kanji-to-phoneme conversion.
For other languages, uses kokoro_onnx's built-in espeak-ng phonemizer.

Language can be specified via --lang flag, or auto-detected from the voice name prefix:
  af_*/am_*/bf_*/bm_* -> en (English)
  jf_*/jm_*           -> ja (Japanese)
  ff_*                -> fr (French)
  gf_*                -> de (German)
  ef_*/em_*           -> es (Spanish)

Usage:
    echo "Hello world" | python kokoro-tts.py --voice af_sky --model /path/to/model.onnx --voices /path/to/voices.bin
    echo "日本語テキスト" | python kokoro-tts.py --voice jf_alpha --model /path/to/model.onnx --voices /path/to/voices.bin
    python kokoro-tts.py input.txt --voice jf_alpha --stream
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import sounddevice as sd
from kokoro_onnx import Kokoro

# Voice prefix to language mapping
VOICE_LANG_MAP = {
    "a": "en",  # af_*, am_* -> American English
    "b": "en",  # bf_*, bm_* -> British English
    "j": "ja",  # jf_*, jm_* -> Japanese
    "f": "fr",  # ff_*       -> French
    "g": "de",  # gf_*       -> German
    "e": "es",  # ef_*, em_* -> Spanish
}


def detect_lang_from_voice(voice: str) -> str | None:
    """Detect language from voice name prefix."""
    if voice and len(voice) >= 2:
        return VOICE_LANG_MAP.get(voice[0])
    return None


def phonemize_japanese(text: str) -> str:
    """Convert Japanese text to phonemes using misaki[ja]."""
    # Lazy import: only load misaki and unidic when Japanese is actually used
    import unidic_lite
    import types

    # Patch unidic to use unidic-lite dictionary before any imports that trigger MeCab
    _fake_unidic = types.ModuleType("unidic")
    _fake_unidic.DICDIR = unidic_lite.DICDIR
    sys.modules["unidic"] = _fake_unidic

    from misaki import ja

    g2p = ja.JAG2P()
    phonemes, _ = g2p(text)
    return phonemes


def main():
    parser = argparse.ArgumentParser(description="Multi-language TTS with kokoro_onnx")
    parser.add_argument("input_file", nargs="?", help="Input text file (reads stdin if omitted)")
    parser.add_argument("--voice", default="af_sky", help="Voice name (default: af_sky)")
    parser.add_argument("--speed", type=float, default=1.0, help="Speech speed (default: 1.0)")
    parser.add_argument("--model", required=True, help="Path to kokoro-v1.0.onnx")
    parser.add_argument("--voices", required=True, help="Path to voices-v1.0.bin")
    parser.add_argument("--stream", action="store_true", help="Stream audio playback")
    parser.add_argument("--lang", default=None, help="Language code: en, ja, fr, de, es (auto-detected from voice if omitted)")
    parser.add_argument("--output", help="Output WAV file (plays audio if omitted)")
    args = parser.parse_args()

    # Auto-detect language from voice name if not specified
    lang = args.lang or detect_lang_from_voice(args.voice)
    if not lang:
        lang = "en"  # Default to English
        print(f"Could not detect language for voice '{args.voice}', defaulting to '{lang}'", file=sys.stderr)

    print(f"Language: {lang}, Voice: {args.voice}", file=sys.stderr)

    # Read input text
    if args.input_file:
        text = Path(args.input_file).read_text(encoding="utf-8").strip()
    else:
        text = sys.stdin.read().strip()

    if not text:
        print("No input text provided", file=sys.stderr)
        sys.exit(1)

    # Initialize kokoro
    kokoro = Kokoro(args.model, args.voices)

    # Phonemize with misaki for Japanese, then pass phonemes directly
    if lang == "ja":
        phonemes = phonemize_japanese(text)
        print(f"Phonemes: {phonemes}", file=sys.stderr)
        samples, sample_rate = kokoro.create(
            phonemes,
            voice=args.voice,
            speed=args.speed,
            lang=lang,
            is_phonemes=True,
        )
    else:
        # For non-Japanese languages, kokoro_onnx handles phonemization via espeak-ng
        samples, sample_rate = kokoro.create(
            text,
            voice=args.voice,
            speed=args.speed,
            lang=lang,
        )

    if args.output:
        import soundfile as sf
        sf.write(args.output, samples, sample_rate)
        print(f"Saved to {args.output}", file=sys.stderr)
    else:
        # Play audio
        sd.play(samples, sample_rate)
        sd.wait()


if __name__ == "__main__":
    main()
