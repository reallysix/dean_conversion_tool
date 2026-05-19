#!/bin/bash

# Integration test script for Dean Conversion Tool
# Tests the full pipeline: audio preprocessing → transcription → export

set -e

echo "=========================================="
echo "Dean Conversion Tool - Integration Test"
echo "=========================================="
echo ""

# Configuration
WHISPER_MODEL="$HOME/Library/Application Support/DeanConversion/models/ggml-large-v3.bin"
TEST_AUDIO="$HOME/Desktop/test_audio.wav"
OUTPUT_DIR="$HOME/Desktop/test_output"
WHISPER_CLI="/opt/homebrew/bin/whisper-cli"
FFMPEG="/opt/homebrew/bin/ffmpeg"
YTDLP="$(command -v yt-dlp || true)"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "1. Testing Environment"
echo "----------------------"

# Check whisper-cli
if [ -f "$WHISPER_CLI" ]; then
    echo "✓ whisper-cli found: $WHISPER_CLI"
else
    echo "✗ whisper-cli not found"
    exit 1
fi

# Check model
if [ -f "$WHISPER_MODEL" ]; then
    MODEL_SIZE=$(du -h "$WHISPER_MODEL" | cut -f1)
    echo "✓ Whisper model found: $MODEL_SIZE"
else
    echo "✗ Whisper model not found: $WHISPER_MODEL"
    exit 1
fi

# Check ffmpeg
if [ -f "$FFMPEG" ]; then
    echo "✓ FFmpeg found: $FFMPEG"
else
    echo "✗ FFmpeg not found"
    exit 1
fi

# Check yt-dlp
if [ -n "$YTDLP" ]; then
    echo "✓ yt-dlp found: $YTDLP"
else
    echo "✗ yt-dlp not found"
    exit 1
fi

# Check Python
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    echo "✓ Python found: $PYTHON_VERSION"
else
    echo "✗ Python not found"
    exit 1
fi

# Check pyannote.audio
if python3 -c "import pyannote.audio" 2>/dev/null; then
    echo "✓ pyannote.audio installed"
else
    echo "✗ pyannote.audio not installed"
fi

echo ""
echo "2. Testing Audio Preprocessing"
echo "------------------------------"

# Create test audio if not exists
if [ ! -f "$TEST_AUDIO" ]; then
    echo "Creating test audio file..."
    $FFMPEG -f lavfi -i "sine=frequency=440:duration=5" -ar 16000 -ac 1 -c:a pcm_s16le "$TEST_AUDIO" -y 2>/dev/null
fi

if [ -f "$TEST_AUDIO" ]; then
    echo "✓ Test audio file exists: $TEST_AUDIO"

    # Convert to WAV format
    CONVERTED_AUDIO="$OUTPUT_DIR/converted_test.wav"
    $FFMPEG -i "$TEST_AUDIO" -ar 16000 -ac 1 -c:a pcm_s16le -f wav -y "$CONVERTED_AUDIO" 2>/dev/null

    if [ -f "$CONVERTED_AUDIO" ]; then
        echo "✓ Audio conversion successful: $CONVERTED_AUDIO"
    else
        echo "✗ Audio conversion failed"
        exit 1
    fi
else
    echo "✗ Test audio file not found"
    exit 1
fi

echo ""
echo "3. Testing Whisper Transcription"
echo "--------------------------------"

# Run whisper transcription
TRANSCRIPT_FILE="$OUTPUT_DIR/converted_test.wav.txt"
echo "Running whisper transcription..."

$WHISPER_CLI -m "$WHISPER_MODEL" -f "$CONVERTED_AUDIO" -otxt 2>/dev/null

if [ -f "$TRANSCRIPT_FILE" ]; then
    TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT_FILE")
    echo "✓ Transcription successful"
    echo "  Output: $TRANSCRIPT_FILE"
    echo "  Content: $TRANSCRIPT_CONTENT"
else
    echo "✗ Transcription failed - no output file"
    exit 1
fi

echo ""
echo "4. Testing Export Formats"
echo "------------------------"

# Test SRT export
SRT_FILE="$OUTPUT_DIR/converted_test.wav.srt"
$WHISPER_CLI -m "$WHISPER_MODEL" -f "$CONVERTED_AUDIO" -osrt 2>/dev/null

if [ -f "$SRT_FILE" ]; then
    echo "✓ SRT export successful"
else
    echo "✗ SRT export failed"
fi

echo ""
echo "5. Testing Python Integration"
echo "------------------------------"

# Test Python script
PYTHON_SCRIPT="/Users/olivia/MyObjects/2026Projects/dean_conversion_tool/PythonHelpers/speaker_diarization.py"

if [ -f "$PYTHON_SCRIPT" ]; then
    echo "✓ Python script found: $PYTHON_SCRIPT"

    # Test with help command
    if python3 "$PYTHON_SCRIPT" --help > /dev/null 2>&1; then
        echo "✓ Python script runs successfully"
    else
        echo "✗ Python script failed to run"
    fi
else
    echo "✗ Python script not found"
fi

echo ""
echo "6. Test Results Summary"
echo "----------------------"

echo "Environment:"
echo "  - Whisper CLI: $(which whisper-cli)"
echo "  - Model: $WHISPER_MODEL"
echo "  - FFmpeg: $(which ffmpeg)"
echo "  - yt-dlp: $(which yt-dlp)"
echo "  - Python: $(which python3)"

echo ""
echo "Test Files Created:"
ls -la "$OUTPUT_DIR" 2>/dev/null || echo "  No test files created"

echo ""
echo "=========================================="
echo "Integration Test Complete!"
echo "=========================================="
