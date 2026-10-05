"""Monta el tráiler: toma el vídeo grabado con Movie Maker (con efectos y ambiente), le mezcla
la música del título con fundidos y lo guarda en MP4 (H.264 + AAC).

Uso:
  Godot --path . --write-movie captures/trailer/trailer.avi --fixed-fps 30 --resolution 2560x1440 -- --ib-trailer
  (con editor/movie_writer/mjpeg_quality=1.0 en override.cfg para que el AVI no pierda detalle)
  python tools/make_trailer.py            # -> captures/trailer/IslaBrisa_trailer.mp4
  python tools/make_trailer.py --frames   # además, saca fotogramas sueltos para revisarlo
"""
import os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "captures", "trailer", "trailer.avi")
MUSIC = os.path.join(ROOT, "assets", "audio", "music_title.wav")
OUT = os.path.join(ROOT, "captures", "trailer", "IslaBrisa_trailer.mp4")
FFMPEG = shutil.which("ffmpeg") or "ffmpeg"
MAX_LEN = 25.0  # segundos


def duration(path: str) -> float:
    probe = shutil.which("ffprobe") or FFMPEG.replace("ffmpeg", "ffprobe")
    out = subprocess.run([probe, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out)


def main() -> None:
    dur = min(duration(SRC), MAX_LEN)
    fade_out = max(dur - 2.5, 0.0)
    # Música: entra con fundido, baja un poco bajo los efectos y se apaga al final.
    filt = (
        f"[1:a]atrim=0:{dur:.2f},afade=t=in:d=0.8,afade=t=out:st={fade_out:.2f}:d=2.5,volume=0.85[m];"
        f"[0:a]volume=0.9[s];"
        f"[s][m]amix=inputs=2:duration=first:dropout_transition=0:normalize=0,alimiter=limit=0.95[a]"
    )
    # Se graba a 1440p y se reduce a 1080p (supermuestreo: bordes limpios) con un enfoque suave.
    filt += ";[0:v]scale=1920:1080:flags=lanczos,unsharp=5:5:0.45:5:5:0.0[v]"
    cmd = [FFMPEG, "-y", "-t", f"{dur:.2f}", "-i", SRC, "-i", MUSIC, "-filter_complex", filt, "-map", "[v]", "-map", "[a]",
           "-c:v", "libx264", "-preset", "slow", "-crf", "15", "-tune", "film", "-profile:v", "high",
           "-pix_fmt", "yuv420p", "-movflags", "+faststart",
           "-c:a", "aac", "-b:a", "192k", OUT]
    subprocess.run(cmd, check=True, capture_output=True)
    print(f"tráiler: {OUT} ({dur:.1f} s, {os.path.getsize(OUT) / 1e6:.1f} MB)")
    if "--frames" in sys.argv:
        frames = os.path.join(ROOT, "captures", "trailer", "frames")
        os.makedirs(frames, exist_ok=True)
        t = 2.0
        i = 0
        while t < dur:
            subprocess.run([FFMPEG, "-y", "-ss", f"{t:.2f}", "-i", OUT, "-frames:v", "1", "-vf", "scale=960:-1",
                            os.path.join(frames, f"f{i:02d}_{t:04.1f}.jpg")], check=True, capture_output=True)
            t += 3.0
            i += 1
        print(f"fotogramas: {frames} ({i})")


if __name__ == "__main__":
    main()
