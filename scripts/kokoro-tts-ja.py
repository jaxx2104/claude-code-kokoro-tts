#!/usr/bin/env python3
"""Japanese TTS using kokoro_onnx with misaki[ja] phonemizer.

kokoro_onnx's built-in phonemizer (espeak-ng) cannot handle Japanese kanji,
reading them as "chinese letter". This script uses misaki[ja] for proper
Japanese phonemization, then passes phonemes to kokoro_onnx for synthesis.

Usage:
    echo "日本語テキスト" | python kokoro-tts-ja.py --voice jf_alpha --model /path/to/model.onnx --voices /path/to/voices.bin
    python kokoro-tts-ja.py input.txt --voice jf_alpha --stream
"""

import argparse
import os
import sys
from pathlib import Path

# Patch unidic to use unidic-lite dictionary before any imports that trigger MeCab
import unidic_lite
import importlib
import types

# Create a fake unidic module that points to unidic-lite's dictionary
_fake_unidic = types.ModuleType("unidic")
_fake_unidic.DICDIR = unidic_lite.DICDIR
sys.modules["unidic"] = _fake_unidic

import numpy as np
import sounddevice as sd
from kokoro_onnx import Kokoro
from misaki import ja


def phonemize_japanese(text: str) -> str:
    """Convert Japanese text to phonemes using misaki[ja]."""
    g2p = ja.JAG2P()
    phonemes, _ = g2p(text)
    return phonemes


def main():
    parser = argparse.ArgumentParser(description="Japanese TTS with kokoro_onnx + misaki")
    parser.add_argument("input_file", nargs="?", help="Input text file (reads stdin if omitted)")
    parser.add_argument("--voice", default="jf_alpha", help="Voice name (default: jf_alpha)")
    parser.add_argument("--speed", type=float, default=1.0, help="Speech speed (default: 1.0)")
    parser.add_argument("--model", required=True, help="Path to kokoro-v1.0.onnx")
    parser.add_argument("--voices", required=True, help="Path to voices-v1.0.bin")
    parser.add_argument("--stream", action="store_true", help="Stream audio playback")
    parser.add_argument("--lang", default="ja", help="Language (default: ja)")
    parser.add_argument("--output", help="Output WAV file (plays audio if omitted)")
    args = parser.parse_args()

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
    if args.lang == "ja":
        phonemes = phonemize_japanese(text)
        print(f"Phonemes: {phonemes}", file=sys.stderr)
        samples, sample_rate = kokoro.create(
            phonemes,
            voice=args.voice,
            speed=args.speed,
            lang=args.lang,
            is_phonemes=True,
        )
    else:
        samples, sample_rate = kokoro.create(
            text,
            voice=args.voice,
            speed=args.speed,
            lang=args.lang,
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
