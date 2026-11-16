#!/usr/bin/env bash
# Build the soundtrack: Quran recitation (Mishary Alafasy) over a soft, non-melodic ambient bed,
# with a light swell + chime on the name reveal. The bed ducks automatically under the recitation.
# Usage: mix.sh <out.wav>    (cue times come from reel.html: window.AUDIO_CUES / REVEAL_AT)
set -euo pipefail
cd "$(dirname "$0")"
OUT="$1"
read -r DUR REV CUES < <(node -e "
const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();
await p.goto('file://'+process.cwd()+'/reel.html');await p.evaluate(()=>window.ready);
const r=await p.evaluate(()=>[DURATION,REVEAL_AT,AUDIO_CUES]);await b.close();
console.log(r[0].toFixed(2), r[1].toFixed(2), r[2].map(c=>c.file+'@'+c.at).join(','))})()")
echo "duration=$DUR reveal=$REV cues=$CUES"

IN=(); F=""; i=0; LABELS=""
for c in ${CUES//,/ }; do
  file=${c%@*}; at=${c#*@}; ms=$(python3 -c "print(int($at*1000))")
  IN+=(-i "audio/$file")
  F+="[$i:a]aresample=48000,aformat=channel_layouts=stereo,adelay=${ms}|${ms}[r$i];"
  LABELS+="[r$i]"; i=$((i+1))
done
N=$i
R=$REV
PAD="0.22*sin(2*PI*110*t)*(0.6+0.4*sin(2*PI*0.07*t))+0.16*sin(2*PI*164.81*t)*(0.6+0.4*sin(2*PI*0.05*t+1))+0.10*sin(2*PI*220*t)*(0.6+0.4*sin(2*PI*0.09*t+2))+0.05*sin(2*PI*329.63*t)*(0.5+0.5*sin(2*PI*0.11*t+3))"
CHIME="if(gte(t,$R),(0.16*sin(2*PI*880*t)+0.11*sin(2*PI*1318.5*t)+0.07*sin(2*PI*1760*t)+0.05*sin(2*PI*2637*t))*exp(-(t-$R)*0.9),0)"

ffmpeg -y -loglevel error "${IN[@]}" \
  -f lavfi -i "aevalsrc=${PAD}:s=48000:d=${DUR}" \
  -f lavfi -i "anoisesrc=c=pink:a=0.5:r=48000:d=${DUR}" \
  -f lavfi -i "anoisesrc=c=white:a=0.6:r=48000:d=${DUR}" \
  -f lavfi -i "aevalsrc='${CHIME}':s=48000:d=${DUR}" \
  -filter_complex "
  ${F}${LABELS}amix=inputs=${N}:normalize=0,apad,atrim=0:${DUR},asplit=2[quran][sc];
  [${N}:a]aformat=channel_layouts=stereo,lowpass=f=900,aecho=0.8:0.7:120|240:0.35|0.25,volume=0.55[pad];
  [$((N+1)):a]lowpass=f=500,highpass=f=80,tremolo=f=0.1:d=0.5,volume=0.25,aformat=channel_layouts=stereo[wind];
  [$((N+2)):a]bandpass=f=2500:w=3000,volume='if(between(t,$R-2.2,$R),pow((t-($R-2.2))/2.2,3)*0.5,0)':eval=frame,aformat=channel_layouts=stereo[swell];
  [$((N+3)):a]aformat=channel_layouts=stereo,aecho=0.8:0.8:180|360:0.4|0.3[chime];
  [pad][wind][swell][chime]amix=inputs=4:normalize=0,afade=t=in:d=3,afade=t=out:st=$(python3 -c "print($DUR-3)"):d=3,volume=0.5[bg];
  [bg][sc]sidechaincompress=threshold=0.02:ratio=6:attack=80:release=900[bgduck];
  [quran][bgduck]amix=inputs=2:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[out]" \
  -map "[out]" -t "$DUR" -c:a pcm_s16le "$OUT"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT"
