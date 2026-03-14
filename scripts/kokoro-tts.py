#!/usr/bin/env python3
"""Multi-language TTS using kokoro KPipeline.

Supports multiple languages via KPipeline with automatic phonemization.
For Japanese, uses misaki[ja] for proper kanji-to-phoneme conversion.
For other languages, uses espeak-ng via KPipeline internals.

Language code (single character) can be specified via --lang flag,
or auto-detected from the voice name prefix:
  af_*/am_*/bf_*/bm_* -> a/b (English)
  jf_*/jm_*           -> j (Japanese)
  ff_*                -> f (French)
  ef_*/em_*           -> e (Spanish)

Usage:
    echo "Hello world" | python kokoro-tts.py --voice af_sky
    echo "日本語テキスト" | python kokoro-tts.py --voice jf_alpha
    python kokoro-tts.py input.txt --voice jf_alpha --speed 1.2
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import sounddevice as sd

# Voice prefix to KPipeline lang_code mapping
VOICE_LANG_MAP = {
    "a": "a",  # af_*, am_* -> American English
    "b": "b",  # bf_*, bm_* -> British English
    "j": "j",  # jf_*, jm_* -> Japanese
    "f": "f",  # ff_*       -> French
    "e": "e",  # ef_*, em_* -> Spanish
}

SAMPLE_RATE = 24000


def detect_lang_from_voice(voice: str) -> str | None:
    """Detect KPipeline lang_code from voice name prefix."""
    if voice and len(voice) >= 2:
        return VOICE_LANG_MAP.get(voice[0])
    return None


def main():
    parser = argparse.ArgumentParser(description="Multi-language TTS with kokoro KPipeline")
    parser.add_argument("input_file", nargs="?", help="Input text file (reads stdin if omitted)")
    parser.add_argument("--voice", default="jf_alpha", help="Voice name (default: jf_alpha)")
    parser.add_argument("--speed", type=float, default=1.0, help="Speech speed (default: 1.0)")
    parser.add_argument("--lang", default=None, help="KPipeline lang_code: a, b, j, e, f (auto-detected from voice if omitted)")
    parser.add_argument("--output", help="Output WAV file (plays audio if omitted)")
    args = parser.parse_args()

    # Auto-detect language from voice name if not specified
    lang = args.lang or detect_lang_from_voice(args.voice)
    if not lang:
        lang = "a"
        print(f"Could not detect language for voice '{args.voice}', defaulting to '{lang}'", file=sys.stderr)

    # Patch unidic to use unidic-lite for Japanese (must happen before KPipeline triggers MeCab)
    if lang == "j":
        import types

        import unidic_lite

        _fake_unidic = types.ModuleType("unidic")
        _fake_unidic.DICDIR = unidic_lite.DICDIR
        sys.modules["unidic"] = _fake_unidic

    from kokoro import KPipeline

    print(f"Language: {lang}, Voice: {args.voice}", file=sys.stderr)

    # Read input text
    if args.input_file:
        text = Path(args.input_file).read_text(encoding="utf-8").strip()
    else:
        text = sys.stdin.read().strip()

    if not text:
        print("No input text provided", file=sys.stderr)
        sys.exit(1)

    # Initialize KPipeline
    pipeline = KPipeline(lang_code=lang, repo_id="hexgrad/Kokoro-82M")

    # Generate and play audio segments
    all_samples = []
    for gs, ps, audio in pipeline(text, voice=args.voice, speed=args.speed):
        if audio is not None:
            all_samples.append(audio)

    if not all_samples:
        print("No audio generated", file=sys.stderr)
        sys.exit(1)

    samples = np.concatenate(all_samples)

    if args.output:
        import soundfile as sf

        sf.write(args.output, samples, SAMPLE_RATE)
        print(f"Saved to {args.output}", file=sys.stderr)
    else:
        sd.play(samples, SAMPLE_RATE)
        sd.wait()


if __name__ == "__main__":
    main()
