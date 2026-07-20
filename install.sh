#!/usr/bin/env bash
set -euo pipefail

# install.sh - Deploy skills to target directories
#
# Usage: ./install.sh TARGET_DIR [TARGET_DIR2 ...]
#
# Copies contents of skills/ directory to each target directory.

if [ $# -eq 0 ]; then
    echo "Error: No target directory specified"
    echo "Usage: $0 TARGET_DIR [TARGET_DIR2 ...]"
    exit 1
fi

SKILLS_SOURCE="./skills"

if [ ! -d "$SKILLS_SOURCE" ]; then
    echo "Error: Skills source directory '$SKILLS_SOURCE' not found"
    exit 1
fi

# Deploy to each target directory
for TARGET_DIR in "$@"; do
    echo "Deploying to: $TARGET_DIR"

    # Create target directory if it doesn't exist
    mkdir -p "$TARGET_DIR"

    # Copy skills to target
    # Use rsync if available for better output, otherwise fall back to cp
    if command -v rsync >/dev/null 2>&1; then
        rsync -av --delete "$SKILLS_SOURCE/" "$TARGET_DIR/"
    else
        cp -rv "$SKILLS_SOURCE/"* "$TARGET_DIR/"
    fi

    echo "✓ Deployed to $TARGET_DIR"
    echo ""
done

echo "✓ Deployment complete!"
