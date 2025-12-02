#!/bin/bash
# sync-to-plugin.sh - Sync development files to gtd-nvim plugin
# Run from anywhere - uses absolute paths

set -e

NVIM_CONFIG="$HOME/.config/nvim/lua"
PLUGIN_DIR="$HOME/projects/gtd-nvim/lua/gtd-nvim"

echo "🔄 Syncing GTD-Nvim development files..."

# GTD modules
echo "  → GTD modules"
rsync -av --delete \
  --exclude='*.backup*' \
  --exclude='*~' \
  --exclude='*.bak' \
  --exclude='.DS_Store' \
  --exclude='*.lua-' \
  --exclude='Untitled' \
  --exclude='*.txt' \
  --exclude='*.tgz' \
  "$NVIM_CONFIG/gtd/" "$PLUGIN_DIR/gtd/"

# Zettelkasten modules
echo "  → Zettelkasten modules"
rsync -av --delete \
  --exclude='*.backup*' \
  --exclude='*~' \
  --exclude='.DS_Store' \
  "$NVIM_CONFIG/utils/zettelkasten/" "$PLUGIN_DIR/zettelkasten/"

# GTD Audit modules
echo "  → GTD Audit modules"
rsync -av --delete \
  --exclude='*.backup*' \
  --exclude='*~' \
  --exclude='.DS_Store' \
  "$NVIM_CONFIG/utils/gtd-audit/" "$PLUGIN_DIR/audit/"

# Utils (link_insert, link_open)
echo "  → Utils"
mkdir -p "$PLUGIN_DIR/utils"
cp -f "$NVIM_CONFIG/utils/link_insert.lua" "$PLUGIN_DIR/utils/" 2>/dev/null || true
cp -f "$NVIM_CONFIG/utils/link_open.lua" "$PLUGIN_DIR/utils/" 2>/dev/null || true

# Clean up backup files in destination
echo "  → Cleaning backup files"
find "$PLUGIN_DIR" -name "*.backup*" -delete 2>/dev/null || true
find "$PLUGIN_DIR" -name "*~" -delete 2>/dev/null || true
find "$PLUGIN_DIR" -name "*.bak" -delete 2>/dev/null || true
find "$PLUGIN_DIR" -name ".DS_Store" -delete 2>/dev/null || true
find "$PLUGIN_DIR" -name "*.lua-" -delete 2>/dev/null || true

echo "✅ Sync complete!"
echo ""
echo "Next steps:"
echo "  cd ~/projects/gtd-nvim"
echo "  git status"
echo "  git add -A"
echo "  git commit -m 'Sync latest changes'"
echo "  git push"
