#!/usr/bin/env bash
# The game's trailer: every scene of scripts/trailer.gd recorded by Movie Maker (1920×1080, 60 fps), cut to
# the frames the scene printed, joined, with the music of tools/trailer_music.py.
#   GODOT=/path/to/godot tools/trailer.sh OUT_DIR [scene …]
# Run from godot/. On a machine without a GPU, under xvfb-run.
set -euo pipefail
OUT=${1:?out dir}
shift || true
GODOT=${GODOT:-godot}
mkdir -p "$OUT"
# Movie Maker records at the project's window size: 1920×1080 for the recording only (override.cfg is read
# by the engine over project.godot); removed at the end unless KEEP_OVERRIDE is set (parallel runs)
printf '[display]\n\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/size/mode=0\n' > override.cfg
[ -n "${KEEP_OVERRIDE:-}" ] || trap 'rm -f override.cfg' EXIT
# scene: duration, world
declare -A DUR=([intro]=8 [network]=10 [pirates]=8 [border]=7 [storm]=7 [money]=9 [night]=6 [end]=6)
declare -A WORLD=([intro]="--size=earth" [end]="--size=earth")
ORDER=(intro network pirates border storm money night end)
SCENES=("$@")
[ ${#SCENES[@]} -eq 0 ] && SCENES=("${ORDER[@]}")

for s in "${SCENES[@]}"; do
	echo "== $s"
	[ -n "${CUT_ONLY:-}" ] || $GODOT --path . --rendering-driver vulkan --write-movie "$OUT/$s.avi" --fixed-fps 60 --resolution 1920x1080 -- \
		--seed=777 --company --stress --hubs=30 --days=3 ${WORLD[$s]:-} --set=res:0,glint:true,trails:true,blur:0 --trailer=$s \
		> "$OUT/$s.log" 2>&1 || [ -n "${CUT_ONLY:-}" ] || true
	start=$(grep -o "TRAILER START [0-9]*" "$OUT/$s.log" | awk '{print $3}')
	d=${DUR[$s]}
	# the scene alone, a quick dip from and to black at the cuts
	ffmpeg -loglevel error -y -ss "$(awk "BEGIN{printf \"%.4f\", $start / 60}")" -i "$OUT/$s.avi" -t "$d" \
		-vf "fade=t=in:st=0:d=0.1,fade=t=out:st=$(awk "BEGIN{printf \"%.2f\", $d - 0.1}"):d=0.1" -an \
		-c:v libx264 -preset slow -crf 15 -pix_fmt yuv420p -r 60 "$OUT/$s.mp4"
done

python3 tools/trailer_music.py "$OUT/music.wav" 61
: > "$OUT/list.txt"
for s in "${ORDER[@]}"; do echo "file '$s.mp4'" >> "$OUT/list.txt"; done
ffmpeg -loglevel error -y -f concat -safe 0 -i "$OUT/list.txt" -i "$OUT/music.wav" \
	-vf "fade=t=in:st=0:d=0.6,fade=t=out:st=59.6:d=1.4" -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -r 60 \
	-c:a aac -b:a 256k -shortest -movflags +faststart "$OUT/triroute_trailer.mp4"
echo "done: $OUT/triroute_trailer.mp4"
