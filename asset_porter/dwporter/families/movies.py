"""MOVIE/*.STR: FMVs (MDEC video + XA audio). Spec: specs/movies.md.

Always writes the audio (WAV), preview frames and movie.json; the full video as .ogv (Godot) only
when ffmpeg is available (PATH or DW_FFMPEG); every frame as PNG only with DW_MOVIE_ALL_FRAMES=1.
"""

import os
import shutil
import subprocess
from fractions import Fraction

from ..assets import AssetWriter, _dump
from ..exporters import png, wav
from ..formats import strmovie as sm
from ..source import SourceFile

NAME = "movies"
SOURCE_PATH = "MOVIE/*.STR"
SPEC = "specs/movies.md"
CODE_REFS = [
    "dw_decomp/src/main/file_table_us.c:750-753 STR sizes (sectors * 2336)",
    "dw_decomp/src/mov/mov.c:46 MOV_MOVIES (path, start frame, last frame); :120 MOV_startRead (double speed, stream)",
    "dw_decomp/src/mov/mov.c:135 MOV_decodeFrame (DecDCTvlc2), :175 MOV_readFrame (StHEADER, stop at frameCount), :207 MOV_playMovie (24-bit, y 32)",
    "dw_decomp/src/main/main.c:3418,3427,3442,3476,3527 playMovie(0..3)",
]

MOVIES = {  # name -> (MOV_MOVIES index, FILE_OFFSET_TABLE size, last frame shown by the game)
    "OP1": (0, 0x0296FD00, 3637),
    "OP2": (1, 0x02464A00, 3266),
    "ED2": (2, 0x01D8CA00, 2654),
    "EDR": (3, 0x02675E00, 3447),
}
SECTORS_PER_SECOND = 150  # double speed
AUDIO_RATE = 37800
PREVIEW_EVERY = 60


def _rgba(rgb: bytes) -> bytes:
    out = bytearray(len(rgb) // 3 * 4)
    out[0::4], out[1::4], out[2::4] = rgb[0::3], rgb[1::3], rgb[2::3]
    out[3::4] = b"\xff" * (len(rgb) // 3)
    return bytes(out)


def _frames(data: bytes, sectors: list) -> dict:
    frames = {}
    for kind, off, _ in sectors:
        if kind == "video":
            h = sm.video_header(data, off)
            frames.setdefault(h["frame"], []).append((h, off))
    return {n: sorted(parts, key=lambda p: p[0]["chunk"]) for n, parts in frames.items()}


def _movie(out, src, name, movie_id, table_size, last_frame, ffmpeg, all_frames, max_frames) -> None:
    data, label = src.data, name
    try:
        sectors = sm.split_sectors(data)
    except sm.StrError as e:
        out.check(f"{label}: sector walk", False, str(e))
        return
    out.check(f"{label}: sector count = table size / 2336", len(sectors) * sm.RAW_SECTOR == table_size,
              f"{len(sectors)} sectors")
    audio = [(o, z) for k, o, z in sectors if k == "audio"]
    out.check(f"{label}: audio sectors = sectors / 8", len(audio) == len(sectors) // sm.AUDIO_EVERY, str(len(audio)))
    frames = _frames(data, sectors)
    numbers = sorted(frames)
    out.check(f"{label}: frames numbered 1..N without gaps", numbers == list(range(1, len(numbers) + 1)),
              f"{len(numbers)} frames")
    duration = Fraction(len(sectors), SECTORS_PER_SECOND)
    fps = Fraction(len(numbers)) / duration
    shown = min(last_frame, len(numbers))
    folder = out.dir / name
    outputs = []

    # audio first: ffmpeg needs it before the frames are streamed
    state, left, right = [0, 0, 0, 0], [], []
    for off, size in audio:
        lft, rgt = sm.decode_xa(data[off:off + size], state)
        left += lft
        right += rgt
    audio_seconds = Fraction(len(left), AUDIO_RATE)
    out.check(f"{label}: audio duration = video duration", audio_seconds == duration,
              f"{float(audio_seconds):.3f} s / {float(duration):.3f} s")
    clipped = sum(1 for v in left + right if v in (-32768, 32767))
    wav.write(folder / "audio.wav", wav.encode_stereo(left, right, AUDIO_RATE))
    outputs.append(out._rel(folder / "audio.wav"))

    pipe, cut_wav = None, folder / "audio_shown.wav"
    if ffmpeg and max_frames is None:
        cut = len(left) * shown // len(numbers)
        wav.write(cut_wav, wav.encode_stereo(left[:cut], right[:cut], AUDIO_RATE))
        width, height = frames[1][0][0]["width"], frames[1][0][0]["height"]
        pipe = subprocess.Popen(
            [ffmpeg, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{width}x{height}",
             "-r", f"{fps.numerator}/{fps.denominator}", "-i", "-", "-i", str(cut_wav),
             "-c:v", "libtheora", "-pix_fmt", "yuv420p", "-q:v", "9", "-c:a", "libvorbis", "-q:a", "6", str(folder / "movie.ogv")],
            stdin=subprocess.PIPE, stderr=subprocess.PIPE)

    records, bad, slack = [], [], 0
    for n in numbers:
        parts = frames[n]
        h0 = parts[0][0]
        record = {"frame": n, "sectors": [o for _, o in parts], "header": h0}
        records.append(record)
        complete = [p[0]["chunk"] for p in parts] == list(range(h0["chunks"])) and \
            all(p[0]["chunks"] == h0["chunks"] and p[0]["frame_size"] == h0["frame_size"] for p in parts) and \
            h0["frame_size"] <= h0["chunks"] * (sm.VIDEO_SECTOR - sm.STR_HEADER)
        if not complete:
            bad.append((n, "chunks"))
            continue
        if max_frames is not None and n > max_frames:
            continue
        bitstream = b"".join(data[o + sm.STR_HEADER:o + sm.VIDEO_SECTOR] for _, o in parts)[:h0["frame_size"]]
        try:
            dec = sm.decode_bitstream(bitstream, h0["width"], h0["height"])
        except sm.StrError as e:
            bad.append((n, str(e)))
            continue
        expected = -(-((dec["mdec_codes"] + 1) // 2) // 32) * 32
        if expected != dec["codes_field"] or dec["codes_field"] != h0["codes"] or dec["bits_used"] > dec["bits_total"]:
            bad.append((n, f"codes {dec['mdec_codes']} -> {expected} vs {dec['codes_field']}"))
        slack = max(slack, dec["bits_total"] - dec["bits_used"])
        record["decode"] = {k: dec[k] for k in ("version", "qscale", "mdec_codes", "bits_used", "bits_total")}
        preview = n % PREVIEW_EVERY == 1 or n == shown
        to_pipe = pipe is not None and n <= shown
        if preview or all_frames or to_pipe:
            rgb = sm.render(dec, h0["width"], h0["height"])
            if preview or all_frames:
                path = folder / ("frames" if all_frames else "preview") / f"frame_{n:05d}.png"
                png.write(path, png.encode_rgba(h0["width"], h0["height"], _rgba(rgb)))
                outputs.append(out._rel(path))
            if to_pipe:
                pipe.stdin.write(rgb)
    out.check(f"{label}: every frame decodes; code count matches the header (VLC + block structure)",
              not bad, str(bad[:3]))

    ogv = None
    if pipe is not None:
        pipe.stdin.close()
        err = pipe.stderr.read().decode(errors="replace")
        pipe.wait()
        cut_wav.unlink(missing_ok=True)
        out.check(f"{label}: ffmpeg wrote movie.ogv", pipe.returncode == 0, err[-300:])
        if pipe.returncode == 0:
            ogv = out._rel(folder / "movie.ogv")
            outputs.append(ogv)

    span = src.span(0, src.size)
    record = {
        "asset_id": span.asset_id,
        "family": NAME,
        "format": "STR (MDEC + XA)",
        "source": span.identity(),
        "movie": {"id": movie_id, "table_size": table_size, "last_frame_shown": last_frame},
        "sectors": {"count": len(sectors), "pattern": "".join(k[0].upper() for k, _, _ in sectors),
                    "video": sum(1 for k, _, _ in sectors if k == "video"), "audio": len(audio),
                    "empty": sum(1 for k, _, _ in sectors if k == "empty")},
        "video": {"frames": len(numbers), "fps": [fps.numerator, fps.denominator], "fps_float": round(float(fps), 4),
                  "duration_seconds": round(float(duration), 3), "max_bit_slack": slack,
                  "screen_position": [0, 32], "decoded_frames": max_frames or len(numbers), "ogv": ogv,
                  "ogv_note": None if ogv else "ffmpeg not found (or limited run): install it and re-run for movie.ogv"},
        "audio": {"format": "XA ADPCM 4-bit stereo", "rate": AUDIO_RATE, "samples_per_channel": len(left),
                  "clipped_samples": clipped, "inferred": "rate/stereo from timing (sector subheaders not in the dump)"},
        "frames": records,
        "outputs": outputs,
    }
    _dump(folder / "movie.json", record)
    out.assets.append({"asset_id": span.asset_id, "sidecar": out._rel(folder / "movie.json"), "outputs": outputs})


def convert(input_root, output_root, names=None, max_frames=None) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    ffmpeg = os.environ.get("DW_FFMPEG") or shutil.which("ffmpeg")
    all_frames = os.environ.get("DW_MOVIE_ALL_FRAMES") == "1"
    sources = []
    for name, (movie_id, table_size, last_frame) in MOVIES.items():
        if names is not None and name not in names:
            continue
        src = SourceFile.open(input_root, f"MOVIE/{name}.STR")
        sources.append(src)
        _movie(out, src, name, movie_id, table_size, last_frame, ffmpeg, all_frames, max_frames)
    out.finish(sources, {"ffmpeg": ffmpeg})
    return out
