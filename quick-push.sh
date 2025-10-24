#!/bin/bash
# Quick push script for GTD-Nvim development

if [ -z "$1" ]; then
    echo "Usage: ./quick-push.sh \"commit message\""
    exit 1
fi

cd "$(dirname "$0")"

echo "📝 Staging changes..."
git add -A

echo "💾 Committing..."
git commit --no-gpg-sign -m "$1"

echo "🚀 Pushing to GitHub..."
git push origin main

echo "✅ Done! Changes published to https://github.com/dr3v3s/gtd-nvim"
