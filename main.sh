#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INITIAL_DIR="$(pwd)"
trap 'cd "$INITIAL_DIR"' EXIT

if ! cd "$ROOT_DIR"; then
    echo >&2 "Error: Failed to switch to desired working directory."
    exit 1
fi

NUM_PARTS=4
if ! python "part1.py"; then
    echo >&2 "Failed to run Python script to scrape RMP data."
    exit 1
fi

for i in $(seq 2 $NUM_PARTS); do
    if ! Rscript "Rscript part$i.R"; then
        echo >&2 "Failed to run R script for hierarchical model $((i - 1))."
        exit 1
    fi
done

if ! bash "pandoc_config/compile_pdf.sh"; then
    echo >&2 "Failed to compile PDF report."
    exit 1
fi
