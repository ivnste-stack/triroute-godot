#!/bin/bash
# Builds the legacy HTML game (the reference for the Godot port).
#   bash legacy/build.sh  ->  legacy/dist/triroute.html  and  legacy/tests/t.html (used by the Playwright tests)
set -e
L="$(cd "$(dirname "$0")" && pwd)"; G="$L/src"
JS="$G/03-core.js $G/04-map.js $G/04b-earth.js $G/04c-logibg.js $G/04d-logo.js $G/04e-dlcimg.js $G/05-data.js $G/06-sim.js $G/07-events.js $G/08-ui.js $G/086-logistics.js $G/logcities.js $G/088-ticker.js $G/08d-settings.js $G/08e-company.js $G/08f-incidents.js $G/08g-business.js $G/08h-shot.js $G/08j-music.js $G/08k-keys.js $G/08l-start.js $G/08n-editor.js $G/08p-postal.js $G/08q-planner.js $G/08r-multi.js $G/08v-cons.js $G/08w-move.js $G/08x-grade.js $G/09-main.js $G/08u-diag.js"
mkdir -p "$L/dist"
cat $JS > "$L/dist/all.js"
node --check "$L/dist/all.js"
OUT="$L/dist/triroute.html"
{ cat "$G/01-head.html" "$G/02-body.html"; echo "<script>"; cat "$L/dist/all.js"; echo "</script>"; } > "$OUT"
{ printf '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>'; cat "$OUT"; printf '</body></html>'; } > "$L/tests/t.html"
echo "built $OUT"
