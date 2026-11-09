# Video pipeline

Turns a narration script into a finished 1080p YouTube video: AI voiceover, animated scenes,
burned-in captions, and a thumbnail.

```
video/
  001/narration.json      what is said, scene by scene (edit this to change the video)
  001/output/             final video + thumbnail
  tools/tts.py            narration -> voice.wav + timings.json + captions.ass (Piper TTS)
  tools/stage.html        the animated scenes (1920x1080), synced to the voice line by line
  tools/record.js         renders each scene frame-by-frame to MP4 (Playwright + ffmpeg)
  tools/assemble.sh       joins scenes + voice + captions into the final MP4
  tools/thumbnail.html/js 1280x720 thumbnail
apps/hustle-tracker/      the real app built (by AI) and shown in video 001
```

## Rebuild video 001

Requirements: Python 3, `pip install piper-tts`, Node with Playwright, ffmpeg.

```bash
B=/tmp/video-build
mkdir -p $B/voice
# 1. Voice model (Piper "ryan", high quality)
curl -L -o $B/voice/en_US-ryan-high.onnx      https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx
curl -L -o $B/voice/en_US-ryan-high.onnx.json https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx.json
# 2. Voiceover, timings, captions
python3 video/tools/tts.py video/001/narration.json $B/voice $B/out
# 3. Scenes (preview stills first with STILLS="0.5,0.97" and fps 10)
cd video/tools && node record.js "$PWD/../.." $B/out 30 hook stakes plan build demo changes online verdict money outro
# 4. Final video
./assemble.sh ../001/narration.json $B/out ../001/output/video-001.mp4
```

## Using your own voice instead of the AI voice

Record yourself reading each line of `narration.json` (one line = one sentence), keeping the same
order. Easiest route: play the finished video muted, record your voiceover over it in CapCut,
and lower or delete the original audio track. Your own voice builds much more trust than an AI voice.
