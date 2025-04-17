#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && cd ".." && pwd)"
INITIAL_DIR="$(pwd)"
TEMP_OUT=$(mktemp)

CONVERTER="pandoc"
PDF_ENGINE="lualatex"

cleanup() {
    rm -f "$TEMP_OUT"
    cd "$INITIAL_DIR"
}
trap cleanup EXIT

for tool in "$CONVERTER" "$PDF_ENGINE"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo >&2 "Error: $tool is required to compile $DEST but not installed."
        exit 1
    fi
done

if ! cd "$ROOT_DIR"; then
    echo >&2 "Error: Failed to switch to desired working directory $ROOT_DIR"
    exit 1
fi

SOURCE="README.md"
DEST="README.pdf"
METADATA="pandoc_config/meta.yaml"

for file in "$SOURCE" "$METADATA"; do
    if [ ! -f "$file" ]; then
        echo >&2 "Error: Required configuration file $file not found."
        exit 1
    fi
done

echo "Compiling $SOURCE to a PDF..."

COMPILE_CMD=(
    "$CONVERTER" "$SOURCE" "$METADATA"
    -o "$TEMP_OUT" -s
    -f markdown -t pdf --pdf-engine="$PDF_ENGINE"
)

if ! "${COMPILE_CMD[@]}"; then
    echo >&2 "Error: $CONVERTER failed to generate the PDF."
    exit 1
fi

if [ -f "$DEST" ]; then
    echo "$DEST already exists. Overwriting..."
fi

if ! mv -f "$TEMP_OUT" "$DEST"; then
    echo >&2 "Error: Failed to save output to $DEST."
    exit 1
fi

DEST_PATH="$(cd "$(dirname "$DEST")" && pwd)/$(basename "$DEST")"
echo "PDF compiled successfully: \"$DEST_PATH\""
