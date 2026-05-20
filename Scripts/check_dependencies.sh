#!/bin/bash

set -euo pipefail

INSTALL_MISSING=false

if [[ "${1:-}" == "--install" ]]; then
    INSTALL_MISSING=true
fi

REQUIRED_TOOLS=(
    "whisper-cli:whisper-cpp"
    "ffmpeg:ffmpeg"
    "ffprobe:ffmpeg"
    "yt-dlp:yt-dlp"
    "deno:deno"
)

missing_packages=()

echo "Checking Dean Conversion Tool dependencies..."

for item in "${REQUIRED_TOOLS[@]}"; do
    tool="${item%%:*}"
    package="${item#*:}"

    if command -v "$tool" >/dev/null 2>&1; then
        echo "✓ $tool: $(command -v "$tool")"
    else
        echo "✗ $tool is missing (Homebrew package: $package)"
        missing_packages+=("$package")
    fi
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "✗ python3 is missing"
else
    echo "✓ python3: $(command -v python3)"
fi

if python3 -c "import pyannote.audio" >/dev/null 2>&1; then
    echo "✓ pyannote.audio is installed"
else
    echo "⚠ pyannote.audio is not installed; speaker diarization will be unavailable"
fi

if [[ ${#missing_packages[@]} -eq 0 ]]; then
    echo "All required command-line tools are installed."
    exit 0
fi

if [[ "$INSTALL_MISSING" != true ]]; then
    echo ""
    echo "Install missing tools with:"
    echo "  brew install $(printf "%s\n" "${missing_packages[@]}" | sort -u | tr '\n' ' ')"
    echo ""
    echo "Or run:"
    echo "  Scripts/check_dependencies.sh --install"
    exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required to install missing tools. Install it from https://brew.sh/"
    exit 1
fi

echo ""
echo "Installing missing Homebrew packages..."
brew install $(printf "%s\n" "${missing_packages[@]}" | sort -u)

echo ""
echo "Dependency installation complete."
