#!/usr/bin/env bash
# Check everything a choreographed (C) or background (A) take needs, and print
# the fix for each gap. Changes nothing.
#
# Usage: preflight.sh [url-fragment]
#   url-fragment  also confirm a tab whose URL contains it is open in the browser
# Environment: DEMO_CDP_PORT (default 9333), DEMO_PYTHON (default: the
#   ~/.cache/record-demo-venv interpreter when it exists, else python3).
# Exit status: 0 ready, 1 at least one gap.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
port=${DEMO_CDP_PORT:-9333}
py=${DEMO_PYTHON:-$([ -x "$HOME/.cache/record-demo-venv/bin/python" ] && echo "$HOME/.cache/record-demo-venv/bin/python" || echo python3)}
frag=${1:-}
gaps=0
ok() { echo "ok    $1"; }
gap() { echo "MISS  $1"; echo "      fix: $2"; gaps=$((gaps + 1)); }

command -v node >/dev/null && ok "node $(node -v)" || gap "node" "install Node 18+"
[ -d "$here/node_modules/playwright-core" ] && ok "playwright-core" || gap "playwright-core" "(cd $here && npm i)"
"$py" -c "import numpy, PIL" 2>/dev/null && ok "numpy + Pillow ($py)" \
  || gap "numpy + Pillow for $py" "python3 -m venv ~/.cache/record-demo-venv && ~/.cache/record-demo-venv/bin/pip install numpy Pillow, (picked up automatically)"
command -v ffmpeg >/dev/null && ok "ffmpeg" || gap "ffmpeg" "rerun the dotfiles install.sh, or brew install ffmpeg (slow; start it in the background)"
command -v swiftc >/dev/null && ok "swiftc (URL caption bar)" || gap "swiftc" "xcode-select --install, or pass --no-url-bar to choreo.sh"

if curl -s -m 2 "http://127.0.0.1:$port/json/version" >/dev/null; then
  ok "browser DevTools on :$port"
  if [ -n "$frag" ]; then
    curl -s -m 2 "http://127.0.0.1:$port/json/list" | grep -q "\"url\": *\"[^\"]*$frag" \
      && ok "tab matching '$frag'" || gap "no tab matching '$frag'" "open the page in that browser first"
  fi
else
  gap "no browser DevTools on :$port" "bash $here/demo-browser.sh start \"<url>\", or set DEMO_CDP_PORT to a signed-in browser that already exposes one"
fi

others=$(pgrep -fl "screencast.mjs|run.mjs|choreo.sh" || true)
[ -z "$others" ] && ok "no other driver running" || gap "another driver is running: $others" "stop it; two drivers corrupt both takes"

[ "$gaps" = 0 ] && echo "ready" || echo "$gaps gap(s)"
[ "$gaps" = 0 ]
