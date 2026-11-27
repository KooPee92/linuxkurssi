#!/bin/bash
set -Eeuo pipefail

# Week 5 - Prepare deployment
# Verify GitHub commit and prepare trusted application files

umask 077

# Require root permissions
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Root permissions required"
    exit 1
fi

# Validate commit SHA
SHA="${1:-}"

if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: Invalid commit SHA"
    exit 1
fi

# Configuration
REPO="https://github.com/KooPee92/linuxkurssi.git"
BASE="/var/lib/viikko5-verified"
TARGET="$BASE/$SHA"

echo "Preparing Week 5 commit: $SHA"

# Create protected directory
install -d -m 700 -o root -g root "$BASE"

# Prevent preparing an existing release
if [ -e "$TARGET" ]; then
    echo "ERROR: Commit already prepared"
    exit 1
fi

# Create temporary working directory
WORK=$(mktemp -d "$BASE/.prepare.XXXXXXXX")

cleanup() {
    rm -rf -- "$WORK"
}

trap cleanup EXIT

# Initialize temporary Git repository
git init -q "$WORK/repo"

# Fetch the latest main branch
echo "Fetching GitHub repository..."

git -C "$WORK/repo" fetch -q --depth=1 \
    "$REPO" refs/heads/main

# Read the downloaded commit SHA
ACTUAL=$(git -C "$WORK/repo" rev-parse FETCH_HEAD)

# Verify commit
if [ "$ACTUAL" != "$SHA" ]; then
    echo "ERROR: Commit SHA mismatch"
    echo "Expected: $SHA"
    echo "Actual:   $ACTUAL"
    exit 1
fi

echo "Git commit verified"

# Export Week 5 application files
mkdir "$WORK/export"

git -C "$WORK/repo" archive "$SHA" week5 \
    | tar -xf - -C "$WORK/export"

# Verify required files
echo "Checking application files..."

for file in \
    app.py \
    db.py \
    requirements.txt \
    templates/index.html \
    static/style.css \
    static/chat.js \
    deploy/viikko5.conf \
    deploy/viikko5-limits.conf \
    deploy/viikko5.service
do
    if [ ! -f "$WORK/export/week5/$file" ]; then
        echo "ERROR: Missing file: $file"
        exit 1
    fi
done

# Reject symbolic links
if find "$WORK/export/week5" -type l | grep -q .; then
    echo "ERROR: Symbolic links are not allowed"
    exit 1
fi

# Protect prepared files
chown -R root:root "$WORK/export"
chmod -R go-w "$WORK/export"

# Activate prepared directory
mv "$WORK/export" "$TARGET"

echo "----------------------------------------"
echo "Week 5 preparation successful!"
echo "Verified commit: $SHA"
echo "Prepared files: $TARGET/week5"
echo "----------------------------------------"
