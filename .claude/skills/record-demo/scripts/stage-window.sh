#!/usr/bin/env bash
# Find the Chrome window holding a tab whose URL contains <url-fragment>, make
# that tab active, un-minimize the window, bring it to the front, and size it
# to <w>x<h> at (<x>,<y>). Prints "x y w h" (screen points) for record.sh start.
#
# Usage: stage-window.sh <url-fragment> [x y w h]   (default 64 80 1280 800)
#
# Needs Automation permission: claude.app → Google Chrome. window.screenX in the
# page is unreliable here: the Claude in Chrome tab group often lives in its own,
# minimized window, which reports 0×0 or dock-sized bounds.
set -euo pipefail

[ "$#" -ge 1 ] || { sed -n '2,10p' "$0" >&2; exit 2; }
frag=$1 x=${2:-64} y=${3:-80} w=${4:-1280} h=${5:-800}

osascript - "$frag" "$x" "$y" "$((x + w))" "$((y + h))" <<'EOF'
on run argv
  set frag to item 1 of argv
  set b to {(item 2 of argv) as integer, (item 3 of argv) as integer, (item 4 of argv) as integer, (item 5 of argv) as integer}
  tell application "Google Chrome"
    activate
    repeat with w in windows
      set i to 0
      repeat with t in tabs of w
        set i to i + 1
        if URL of t contains frag then
          set minimized of w to false
          set active tab index of w to i
          set index of w to 1
          set bounds of w to b
          return
        end if
      end repeat
    end repeat
    error "no Chrome tab with URL containing " & frag
  end tell
end run
EOF
sleep 0.5
echo "$x $y $w $h"
