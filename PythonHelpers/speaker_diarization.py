#!/usr/bin/env python3
"""
Speaker diarization script using pyannote.audio
Called by Swift via Process() to identify different speakers in audio files

Usage:
    python3 speaker_diarization.py <audio_file_path> [--num_speakers <num>]

Output:
    JSON array to stdout with speaker segments:
    [
        {
            "start": 0.0,
            "end": 2.5,
            "speaker": "SPEAKER_00"
        },
        ...
    ]
"""

import sys
import json
import argparse
import warnings
from pathlib import Path

# Suppress warnings for cleaner output
warnings.filterwarnings("ignore")

def diarize_audio(audio_path: str, num_speakers: int = None) -> list:
    """
    Perform speaker diarization on an audio file

    Args:
        audio_path: Path to the audio file (WAV format recommended)
        num_speakers: Optional number of speakers to detect

    Returns:
        List of dictionaries with start, end, and speaker fields
    """
    try:
        from pyannote.audio import Pipeline
        import torch

        # Check if CUDA is available
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        # Load the pre-trained pipeline
        # Note: This requires a HuggingFace token for the first run
        # Set HF_TOKEN environment variable or use huggingface-cli login
        pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1",
            use_auth_token=True
        )

        # Move pipeline to GPU if available
        if device.type == "cuda":
            pipeline = pipeline.to(device)

        # Run diarization
        if num_speakers:
            diarization = pipeline(audio_path, num_speakers=num_speakers)
        else:
            diarization = pipeline(audio_path)

        # Convert to list of dictionaries
        segments = []
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segments.append({
                "start": round(turn.start, 3),
                "end": round(turn.end, 3),
                "speaker": speaker
            })

        return segments

    except ImportError as e:
        print(json.dumps({"error": f"Missing dependency: {str(e)}"}), file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": f"Diarization failed: {str(e)}"}), file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Speaker diarization using pyannote.audio")
    parser.add_argument("audio_file", help="Path to the audio file")
    parser.add_argument("--num_speakers", type=int, help="Number of speakers to detect (optional)")

    args = parser.parse_args()

    # Check if file exists
    if not Path(args.audio_file).exists():
        print(json.dumps({"error": f"Audio file not found: {args.audio_file}"}), file=sys.stderr)
        sys.exit(1)

    # Perform diarization
    segments = diarize_audio(args.audio_file, args.num_speakers)

    # Output JSON to stdout
    print(json.dumps(segments, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
