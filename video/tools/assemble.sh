#!/usr/bin/env bash
# Join rendered scenes + voiceover + burned-in captions into the final video.
# Usage: assemble.sh <narration.json> <buildDir> <out.mp4>
set -euo pipefail
NARR="$1"; B="$2"; OUT="$3"
IDS=$(python3 -c "import json,sys; print(' '.join(s['id'] for s in json.load(open(sys.argv[1]))['scenes']))" "$NARR")
LIST="$B/concat.txt"
: > "$LIST"
for id in $IDS; do echo "file '$B/scenes/$id.mp4'" >> "$LIST"; done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$LIST" -i "$B/voice.wav" \
  -vf "ass=$B/captions.ass" \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000" \
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k \
  -movflags +faststart -shortest "$OUT"
ffprobe -v error -show_entries format=duration,size -of default=nw=1 "$OUT"
