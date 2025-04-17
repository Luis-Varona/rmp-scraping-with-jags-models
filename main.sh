#!/usr/bin/env bash
set -euo pipefail

NUM_PARTS=4
if ! python "part1.py"; then
    echo >&2 "Failed to run Python script to scrape RMP data."
    exit 1
fi

for i in $(seq 2 $NUM_PARTS); do
    if ! Rscript "Rscript part$i.R"; then
        echo >&2 "Failed to run R script for hierarchical model $(i - 1)."
        exit 1
    fi
done

rm -f "README.pdf"
pandoc "README.md" -o "README.pdf" -s -f markdown -t pdf --pdf-engine=lualatex
