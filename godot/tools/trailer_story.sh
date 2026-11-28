#!/usr/bin/env bash
# The scripted trailer (scripts/trailer_story.gd) recorded by Movie Maker at 1920×1080, 60 fps, cut to the frames
# the story printed, encoded to MP4; the shots' seconds into OUT_DIR/shots.txt (for the subtitles).
#   GODOT=/path/to/godot tools/trailer_story.sh OUT_DIR
# Run from godot/. On a machine without a GPU, under xvfb-run.
set -euo pipefail
OUT=${1:?out dir}
GODOT=${GODOT:-godot}
mkdir -p "$OUT"
printf '[display]\n\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/size/mode=0\n' > override.cfg
trap 'rm -f override.cfg' EXIT
[ -n "${CUT_ONLY:-}" ] || $GODOT --path . --write-movie "$OUT/story.avi" --fixed-fps 60 --resolution 1920x1080 -- \
	--seed=777 --company --hq=center --set=res:0,glint:true,trails:true,blur:0 --story > "$OUT/story.log" 2>&1 || true
start=$(grep -o "STORY START [0-9]*" "$OUT/story.log" | awk '{print $3}')
end=$(grep -o "STORY END [0-9]*" "$OUT/story.log" | awk '{print $3}')
grep -o "STORY SHOT .*" "$OUT/story.log" | sed 's/STORY SHOT //' > "$OUT/shots.txt"
d=$(awk "BEGIN{printf \"%.3f\", ($end - $start) / 60}")
ffmpeg -loglevel error -y -ss "$(awk "BEGIN{printf \"%.4f\", $start / 60}")" -i "$OUT/story.avi" -t "$d" \
	-vf "fade=t=in:st=0:d=0.5,fade=t=out:st=$(awk "BEGIN{printf \"%.2f\", $d - 0.8}"):d=0.8" -an \
	-c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -r 60 -movflags +faststart "$OUT/triroute_story.mp4"
echo "done: $OUT/triroute_story.mp4 ($d s); shots: $OUT/shots.txt"
