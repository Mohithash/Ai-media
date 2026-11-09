"""Generate the voiceover, per-scene timings and captions from narration.json.

Usage: python3 tts.py <narration.json> <voice_dir> <out_dir>

Outputs in out_dir:
  voice.wav      full narration
  timings.json   per-scene start/duration and per-line cue times (seconds, scene-relative)
  captions.ass   burned-in subtitles
"""
import json
import re
import sys
import wave
from pathlib import Path

from piper import PiperVoice, SynthesisConfig

LEAD_IN = 0.45     # silence at the start of each scene
GAP = 0.32         # silence between lines
TAIL = 0.75        # silence at the end of each scene
MAX_WORDS = 7      # words per caption chunk

# Spoken forms for words the voice mispronounces. Captions keep the written form.
SPOKEN = [
    (r"\bAI\b", "A.I."),
    (r"\bHTML\b", "H.T.M.L."),
    (r"\bCSS\b", "C.S.S."),
    (r"\blakh\b", "lack"),
    (r"\bEtsy\b", "Etsee"),
]


def spoken(text):
    for pat, rep in SPOKEN:
        text = re.sub(pat, rep, text)
    return text


def chunk_caption(text):
    words = text.split()
    n = max(1, -(-len(words) // MAX_WORDS))
    size = -(-len(words) // n)
    return [" ".join(words[i:i + size]) for i in range(0, len(words), size)]


def ass_time(t):
    cs = int(round(t * 100))
    h, cs = divmod(cs, 360000)
    m, cs = divmod(cs, 6000)
    s, cs = divmod(cs, 100)
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def main():
    narration = json.loads(Path(sys.argv[1]).read_text())
    voice_dir, out = Path(sys.argv[2]), Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    voice = PiperVoice.load(str(voice_dir / f"{narration['voice']}.onnx"))
    rate = voice.config.sample_rate
    cfg = SynthesisConfig(length_scale=0.95)  # slightly faster than default: YouTube pacing

    def silence(sec):
        return b"\x00\x00" * int(rate * sec)

    pcm = bytearray()
    timings, events = [], []
    t = 0.0
    for scene in narration["scenes"]:
        start = t
        pcm += silence(LEAD_IN)
        t += LEAD_IN
        cues = []
        for i, line in enumerate(scene["lines"]):
            audio = b"".join(c.audio_int16_bytes for c in voice.synthesize(spoken(line), cfg))
            dur = len(audio) / 2 / rate
            cues.append({"t": round(t - start, 3), "d": round(dur, 3)})
            chunks = chunk_caption(line)
            total_chars = sum(len(c) for c in chunks)
            ct = t
            for c in chunks:
                cd = dur * len(c) / total_chars
                events.append((ct, ct + cd, c))
                ct += cd
            pcm += audio
            t += dur
            if i < len(scene["lines"]) - 1:
                pcm += silence(GAP)
                t += GAP
        pcm += silence(TAIL)
        t += TAIL
        timings.append({"id": scene["id"], "start": round(start, 3), "duration": round(t - start, 3), "cues": cues})

    with wave.open(str(out / "voice.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(pcm))
    (out / "timings.json").write_text(json.dumps(timings, indent=1))

    header = """[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 0

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,Inter,52,&H00FFFFFF,&H00FFFFFF,&H00000000,&H96000000,-1,0,0,0,100,100,0,0,1,5,2,2,120,120,48,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    lines = [f"Dialogue: 0,{ass_time(a)},{ass_time(b)},Cap,,0,0,0,,{txt}" for a, b, txt in events]
    (out / "captions.ass").write_text(header + "\n".join(lines) + "\n")
    print(f"total {t:.1f}s, {len(events)} caption chunks")


if __name__ == "__main__":
    main()
