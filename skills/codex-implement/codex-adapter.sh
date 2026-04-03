#!/usr/bin/env bash
# Codex transport adapter — prefer companion plugin (HTTP), fall back to CLI.
# Usage: bash codex-adapter.sh "prompt text here"
set -euo pipefail

PROMPT="$1"

# Search for companion plugin at known paths
find_companion() {
  local candidates=(
    "${CLAUDE_PLUGIN_ROOT:-__none__}/scripts/codex-companion.mjs"
    "$HOME/.claude/plugins/marketplaces/openai-codex/plugins/codex/scripts/codex-companion.mjs"
  )
  # Check versioned cache paths (glob picks up any version)
  for d in "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs; do
    [ -f "$d" ] 2>/dev/null && candidates+=("$d")
  done
  for p in "${candidates[@]}"; do
    [ -f "$p" ] 2>/dev/null && echo "$p" && return 0
  done
  return 1
}

if COMPANION="$(find_companion)"; then
  >&2 echo "[codex-adapter] transport: companion plugin"
  timeout 300 node "$COMPANION" task "$PROMPT" < /dev/null
else
  >&2 echo "[codex-adapter] transport: codex exec CLI"
  timeout 300 codex exec --sandbox read-only --skip-git-repo-check -- "$PROMPT" < /dev/null
fi
