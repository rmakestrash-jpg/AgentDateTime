#!/usr/bin/env bash
# install.sh — Install Claude Code Time Awareness hooks.
#
# Usage:
#   ./install.sh              # Global install (~/.claude/)
#   ./install.sh --project    # Per-project install (.claude/ in current directory)
#   ./install.sh --uninstall  # Remove global install

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-global}"

# ─── Preflight checks ───

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed."
  echo "  macOS:  brew install jq"
  echo "  Ubuntu: sudo apt install jq"
  echo "  Arch:   sudo pacman -S jq"
  exit 1
fi

# ─── Determine target directories ───

if [ "$MODE" = "--project" ]; then
  HOOKS_DIR=".claude/hooks"
  SETTINGS_FILE=".claude/settings.json"
  CLAUDE_MD="CLAUDE.md"
  echo "Installing per-project to $(pwd)/.claude/"
elif [ "$MODE" = "--uninstall" ]; then
  echo "Uninstalling global time awareness hooks..."
  rm -f "$HOME/.claude/hooks/time-log.sh"
  rm -f "$HOME/.claude/hooks/time-inject.sh"
  rm -f "$HOME/.claude/hooks/time_events.jsonl"
  echo "Removed hook scripts and event log."
  echo ""
  echo "NOTE: You still need to manually remove the hooks entries from"
  echo "  $HOME/.claude/settings.json"
  echo "and the Time Awareness block from your CLAUDE.md."
  exit 0
else
  HOOKS_DIR="$HOME/.claude/hooks"
  SETTINGS_FILE="$HOME/.claude/settings.json"
  CLAUDE_MD="$HOME/.claude/CLAUDE.md"
  echo "Installing globally to ~/.claude/"
fi

# ─── Copy hook scripts ───

mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/time-log.sh" "$HOOKS_DIR/time-log.sh"
cp "$SCRIPT_DIR/hooks/time-inject.sh" "$HOOKS_DIR/time-inject.sh"
chmod +x "$HOOKS_DIR/time-log.sh"
chmod +x "$HOOKS_DIR/time-inject.sh"
echo "✓ Hook scripts installed to $HOOKS_DIR/"

# ─── Merge hooks into settings.json ───

if [ -f "$SETTINGS_FILE" ]; then
  # Settings file exists — merge hooks
  EXISTING=$(cat "$SETTINGS_FILE")
  
  if echo "$EXISTING" | jq -e '.hooks' &>/dev/null; then
    # Has existing hooks — merge ours in
    MERGED=$(jq -s '.[0].hooks * .[1].hooks | {hooks: .} * (.[0] | del(.hooks))' \
      "$SETTINGS_FILE" "$SCRIPT_DIR/settings-hooks.json" 2>/dev/null)
    
    if [ -n "$MERGED" ]; then
      echo "$MERGED" | jq '.' > "$SETTINGS_FILE"
      echo "✓ Hooks merged into existing $SETTINGS_FILE"
    else
      echo "⚠ Could not auto-merge hooks. Please manually merge settings-hooks.json"
      echo "  into $SETTINGS_FILE"
    fi
  else
    # No existing hooks key — add ours
    jq -s '.[0] * .[1]' "$SETTINGS_FILE" "$SCRIPT_DIR/settings-hooks.json" > "${SETTINGS_FILE}.tmp"
    mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "✓ Hooks added to $SETTINGS_FILE"
  fi
else
  # No settings file — copy ours
  # For project installs, adjust paths to use $CLAUDE_PROJECT_DIR
  if [ "$MODE" = "--project" ]; then
    sed 's|\$HOME/.claude/hooks/|\$CLAUDE_PROJECT_DIR/.claude/hooks/|g' \
      "$SCRIPT_DIR/settings-hooks.json" > "$SETTINGS_FILE"
  else
    cp "$SCRIPT_DIR/settings-hooks.json" "$SETTINGS_FILE"
  fi
  echo "✓ Created $SETTINGS_FILE with hook configuration"
fi

# ─── Append CLAUDE.md block ───

if [ -f "$CLAUDE_MD" ]; then
  if grep -q "Time Awareness" "$CLAUDE_MD" 2>/dev/null; then
    echo "✓ Time Awareness block already exists in $CLAUDE_MD (skipped)"
  else
    echo "" >> "$CLAUDE_MD"
    cat "$SCRIPT_DIR/TIME_AWARENESS.md" >> "$CLAUDE_MD"
    echo "✓ Time Awareness block appended to $CLAUDE_MD"
  fi
else
  cp "$SCRIPT_DIR/TIME_AWARENESS.md" "$CLAUDE_MD"
  echo "✓ Created $CLAUDE_MD with Time Awareness block"
fi

# ─── Done ───

echo ""
echo "Installation complete. Start a new Claude Code session to activate."
echo ""
echo "Verify with: /hooks (inside Claude Code)"
echo "View event log: cat ${HOOKS_DIR}/time_events.jsonl"
echo ""
echo "To uninstall: ./install.sh --uninstall"
