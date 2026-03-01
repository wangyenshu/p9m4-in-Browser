#!/bin/bash

OUTPUT_FILE="debian-state-base.bin"
SPLIT_SIZE="20M"

split -b "$SPLIT_SIZE" "$OUTPUT_FILE" "${OUTPUT_FILE}.part"

# Rename to .part1, .part2...
i=1
for f in "${OUTPUT_FILE}.part"* ; do
    mv "$f" "${OUTPUT_FILE}.part$i"
    echo "Created ${OUTPUT_FILE}.part$i"
    ((i++))
done
