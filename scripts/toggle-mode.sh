#!/bin/bash
# GTD-NVIM Restoration Script
# Restores legacy gtd-nvim and disables chronos

NVIM_LUA="$HOME/.config/nvim/lua"

echo "=== GTD-NVIM Restoration ==="
echo ""

case "${1:-status}" in
  restore)
    echo "Restoring gtd-nvim legacy mode..."
    
    # Restore plugin spec
    if [ -f "$NVIM_LUA/plugins/gtd-nvim.lua.disabled" ]; then
      mv "$NVIM_LUA/plugins/gtd-nvim.lua.disabled" "$NVIM_LUA/plugins/gtd-nvim.lua"
      echo "  ✓ Restored plugins/gtd-nvim.lua"
    fi
    
    # Restore mappings
    if [ -f "$NVIM_LUA/mappings/gtd.lua.disabled" ]; then
      mv "$NVIM_LUA/mappings/gtd.lua.disabled" "$NVIM_LUA/mappings/gtd.lua"
      echo "  ✓ Restored mappings/gtd.lua"
    fi
    
    # Disable chronos
    if [ -f "$NVIM_LUA/plugins/chronos.lua" ]; then
      mv "$NVIM_LUA/plugins/chronos.lua" "$NVIM_LUA/plugins/chronos.lua.disabled"
      echo "  ✓ Disabled plugins/chronos.lua"
    fi
    
    echo ""
    echo "Done! Restart nvim to use gtd-nvim (prefix: <leader>c)"
    ;;
    
  chronos)
    echo "Switching to chronos mode..."
    
    # Disable gtd-nvim
    if [ -f "$NVIM_LUA/plugins/gtd-nvim.lua" ]; then
      mv "$NVIM_LUA/plugins/gtd-nvim.lua" "$NVIM_LUA/plugins/gtd-nvim.lua.disabled"
      echo "  ✓ Disabled plugins/gtd-nvim.lua"
    fi
    
    # Disable mappings
    if [ -f "$NVIM_LUA/mappings/gtd.lua" ]; then
      mv "$NVIM_LUA/mappings/gtd.lua" "$NVIM_LUA/mappings/gtd.lua.disabled"
      echo "  ✓ Disabled mappings/gtd.lua"
    fi
    
    # Enable chronos
    if [ -f "$NVIM_LUA/plugins/chronos.lua.disabled" ]; then
      mv "$NVIM_LUA/plugins/chronos.lua.disabled" "$NVIM_LUA/plugins/chronos.lua"
      echo "  ✓ Restored plugins/chronos.lua"
    fi
    
    echo ""
    echo "Done! Restart nvim to use chronos (prefix: <leader>x)"
    ;;
    
  status|*)
    echo "Current state:"
    echo ""
    
    # Check gtd-nvim
    if [ -f "$NVIM_LUA/plugins/gtd-nvim.lua" ]; then
      echo "  gtd-nvim:  ACTIVE (prefix: <leader>c)"
    elif [ -f "$NVIM_LUA/plugins/gtd-nvim.lua.disabled" ]; then
      echo "  gtd-nvim:  disabled"
    else
      echo "  gtd-nvim:  not found"
    fi
    
    # Check chronos
    if [ -f "$NVIM_LUA/plugins/chronos.lua" ]; then
      echo "  chronos:   ACTIVE (prefix: <leader>x)"
    elif [ -f "$NVIM_LUA/plugins/chronos.lua.disabled" ]; then
      echo "  chronos:   disabled"
    else
      echo "  chronos:   not found"
    fi
    
    echo ""
    echo "Usage:"
    echo "  $0 status   - Show current state"
    echo "  $0 restore  - Switch to gtd-nvim legacy"
    echo "  $0 chronos  - Switch to chronos (daemon)"
    ;;
esac
