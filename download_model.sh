#!/bin/bash

# Script to download the whisper large-v3 model
# Usage: ./download_model.sh

set -e

MODEL_DIR="$HOME/Library/Application Support/DeanConversion/models"
MODEL_FILE="ggml-large-v3.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"

# Proxy settings (uncomment if needed)
PROXY="http://127.0.0.1:61199"
PROXY_ARG="-x $PROXY"

echo "Dean Conversion Tool - Model Downloader"
echo "======================================="
echo ""

# Create model directory
echo "Creating model directory: $MODEL_DIR"
mkdir -p "$MODEL_DIR"

# Check if model already exists
if [ -f "$MODEL_DIR/$MODEL_FILE" ]; then
    echo "Model already exists at: $MODEL_DIR/$MODEL_FILE"
    echo "Delete it first if you want to re-download."
    exit 0
fi

echo "Downloading large-v3 model (~3.1GB)..."
echo "This may take several minutes depending on your internet connection."
echo ""

# Download with progress and proxy
curl -L --progress-bar \
    $PROXY_ARG \
    -o "$MODEL_DIR/$MODEL_FILE" \
    "$MODEL_URL"

# Verify download
if [ -f "$MODEL_DIR/$MODEL_FILE" ]; then
    FILE_SIZE=$(du -h "$MODEL_DIR/$MODEL_FILE" | cut -f1)
    echo ""
    echo "✓ Model downloaded successfully!"
    echo "  Location: $MODEL_DIR/$MODEL_FILE"
    echo "  Size: $FILE_SIZE"
    echo ""
    echo "You can now use the Dean Conversion Tool."
else
    echo "✗ Download failed!"
    exit 1
fi
