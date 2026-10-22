#!/usr/bin/env bash
# Run JavaScript in the Chrome tab whose URL contains <url-fragment> (any window,
# incognito included) and print the result. Fallback driver for tabs the
# Claude in Chrome tab group can't reach.
#
# Usage: chrome-js.sh <url-fragment> <file.js>
#
# Needs Chrome → View → Developer → Allow JavaScript from Apple Events, plus
# Automation permission claude.app → Google Chrome. The JS must be a single
# expression (wrap in an IIFE); return strings/JSON, not objects.
set -euo pipefail

[ "$#" -eq 2 ] || { sed -n '2,10p' "$0" >&2; exit 2; }

osascript - "$1" "$(cat "$2")" <<'EOF'
on run argv
  set frag to item 1 of argv
  tell application "Google Chrome"
    repeat with w in windows
      repeat with t in tabs of w
        if URL of t contains frag then return (execute t javascript (item 2 of argv))
      end repeat
    end repeat
  end tell
  error "no Chrome tab with URL containing " & frag
end run
EOF
