"""The game's songs rendered to WAV like libsnd + the SPU play them. Spec: specs/sound.md "Music render".

Input: the FAALL music fonts (instruments + SEQ songs) and libsnd's tables in the executable.
Output: output/music/font_nn/track_t.wav (16-bit stereo 44.1 kHz; looping songs carry their loop in
a `smpl` chunk) and index.json (per track: loop ticks / samples, length, peak, play mode).
`DW_MUSIC_FONTS=1,2` renders only those fonts (the index then lists only them).
"""

import os
import struct
import time
from concurrent.futures import ProcessPoolExecutor

from ..assets import AssetWriter, _dump
from ..exporters import wav
from ..formats import libsnd, spu, vab
from ..formats import seq as seqfmt
from ..paths import SECTOR_SIZE
from ..source import SourceFile
from . import mmd_files, sound

NAME = "music"
SOURCE_PATH = "SOUND/VHB/FAALL.VHB"
SPEC = "specs/sound.md"
CODE_REFS = [
    "dw_decomp/src/main/sound.c:517 initializeMusic (SsSetTickMode(SS_TICK240), SsSetMVol(127,127), reverb STUDIO_B depth 0x7000)",
    "dw_decomp/src/main/sound.c:738 loadMusicFont, :475 seqOpen, :488 seqPlay (SsSeqSetVol 0x50; fonts 0x1D-0x20 once), :753 playMusic",
    "dw_decomp/asm/us/main/psyq/libsnd.s: _SsInitSoundSeq, _SsSeqPlay, _SsGetSeqData, _SsContDataEntry, _SsContNrpn2, _SsVmKeyOn, _SsVmAlloc, _SsVmKeyOnNow, _SsVmSetVol, _SsVmPBVoice, _SsVmFlush",
    "dw_decomp/config/us/symbols.txt: _svm_ptable 0x80128864, _spu_rev_param 0x8012855C",
]

PTABLE = 0x80128864  # u16[193]
REV_PARAM = 0x8012855C  # 0x44-byte entries: u32 mask + 32 u16 registers
REV_ENTRY = 0x44
STUDIO_B = 3  # SPU_REV_MODE_STUDIO_B (initializeMusic)
REVERB_SIZE = 0x4840  # Studio Medium work area (psx-spx "Reverb Examples")
REVERB_DEPTH = 0x7000
SEQ_VOLUME = 0x50
MAX_SECONDS = 900


def read_tables(exe: bytes) -> dict:
    def at(a):
        return a - mmd_files.EXE_LOAD

    ptable = list(struct.unpack_from("<193H", exe, at(PTABLE)))
    presets = []
    for k in range(10):
        p = at(REV_PARAM) + k * REV_ENTRY
        mask = struct.unpack_from("<I", exe, p)[0]
        presets.append({"mask": mask, "regs": dict(zip(spu.REVERB_REGS, struct.unpack_from("<32H", exe, p + 4)))})
    return {"ptable": ptable, "reverb_presets": presets}


def _render(job: dict) -> dict:
    """One song (runs in a worker process); an error is returned, not raised."""
    try:
        return _render_song(job)
    except Exception as e:  # noqa: BLE001 - reported as a failed check
        return {"font": job["font"], "track": job["track"], "error": f"{type(e).__name__}: {e}"}


def _render_song(job: dict) -> dict:
    t0 = time.time()
    bank = libsnd.Bank(job["vh"], job["vags"])
    res = libsnd.render_song(job["seq"], bank, job["ptable"], job["regs"], REVERB_SIZE, job["play_once"],
                             REVERB_DEPTH, MAX_SECONDS)
    left, right = res["left"], res["right"]
    inter = [0] * (2 * len(left))
    inter[0::2], inter[1::2] = left, right
    loop = res["loop"]
    wav.write(job["path"], wav.encode(inter, spu.RATE, (loop["start"], loop["end"]) if loop else None, channels=2))
    peak = max([abs(x) for x in left] + [abs(x) for x in right] + [0])
    clips = sum(1 for x in inter if x in (32767, -32768))
    return {"font": job["font"], "track": job["track"], "samples": len(left), "seconds": round(len(left) / spu.RATE, 3),
            "ticks": res["ticks"], "loop": loop, "jumps": res["jumps"], "capped": res["capped"], "peak": peak,
            "clipped_samples": clips, "render_seconds": round(time.time() - t0, 1)}


def convert(input_root, output_root) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    exe = SourceFile.open(input_root, mmd_files.EXE)
    src = SourceFile.open(input_root, SOURCE_PATH)
    tables = read_tables(exe.data)
    pt, presets = tables["ptable"], tables["reverb_presets"]
    out.check("_svm_ptable: 0x1000 at the centre, 0x2000 an octave up", pt[0] == 0x1000 and pt[192] == 0x2000,
              f"0x{pt[0]:X} 0x{pt[192]:X}")
    out.check("_svm_ptable rises", all(a < b for a, b in zip(pt, pt[1:])))
    out.check("_spu_rev_param[1] is Room (dAPF1 0x7D, dAPF2 0x5B)",
              presets[1]["regs"]["dAPF1"] == 0x7D and presets[1]["regs"]["dAPF2"] == 0x5B)
    out.check("_spu_rev_param[3] is Studio Medium (dAPF1 0xB1, vIIR 0x70F0, vRIN 0x8000)",
              presets[3]["regs"]["dAPF1"] == 0xB1 and presets[3]["regs"]["vIIR"] == 0x70F0
              and presets[3]["regs"]["vRIN"] == 0x8000)
    regs = presets[STUDIO_B]["regs"]
    span_max = max(v for k, v in regs.items() if k[0] in "md") * 8
    out.check("Studio B addresses fit in the 0x4840-byte work area", span_max < REVERB_SIZE, f"0x{span_max:X}")

    only = os.environ.get("DW_MUSIC_FONTS")
    fonts = [int(x) for x in only.split(",")] if only else list(range(1, sound.EXPECTED_CHUNKS["FAALL"] + 1))
    step = sound.CHUNK_SECTORS["FAALL"] * SECTOR_SIZE
    jobs = []
    for font in fonts:
        chunk = src.data[(font - 1) * step:font * step]
        secs = vab.parse_vhb(chunk)
        vh = vab.parse_vh(chunk, secs[0])
        body = chunk[secs[1]:secs[2]]
        vags = {n: d for n, (_, d) in enumerate(vab.split_vags(vh, body), start=1)}
        out.check(f"font {font}: no noise tones (vag 0xFF)",
                  all(t["vag"] != 0xFF for blk in vh["tones"] for t in blk), "")
        seq_data = chunk[secs[2]:secs[3]]
        offs = seqfmt.parse_table(seq_data)
        for t, o in enumerate(offs):
            s = seqfmt.parse(seq_data, o)
            once = font in sound.ONE_SHOT_FONTS and t != sound.ONE_SHOT_FONTS[font]
            folder = out.dir / f"font_{font:02d}"
            folder.mkdir(parents=True, exist_ok=True)
            jobs.append({"font": font, "track": t, "vh": vh, "vags": vags, "seq": seq_data[o:o + s["size"]],
                         "ptable": pt, "regs": regs, "play_once": once, "path": folder / f"track_{t}.wav",
                         "span": src.span((font - 1) * step + secs[2] + o, s["size"])})
    workers = max(1, (os.cpu_count() or 2) - 1)
    results = []
    with ProcessPoolExecutor(max_workers=workers) as pool:
        payload = [{k: v for k, v in j.items() if k != "span"} for j in jobs]
        for job, res in zip(jobs, pool.map(_render, payload)):
            results.append((job, res))
    tracks = []
    for job, res in results:
        label = f"font {job['font']} track {job['track']}"
        if "error" in res:
            out.check(f"{label}: renders", False, res["error"])
            continue
        out.check(f"{label}: renders to its {'end' if job['play_once'] else 'loop'}", not res["capped"],
                  f"{res['seconds']} s")
        if res["loop"]:
            out.check(f"{label}: the loop is not empty", res["loop"]["end"] > res["loop"]["start"], str(res["loop"]))
        rel = out._rel(job["path"])
        tracks.append(dict(res, play_once=job["play_once"], file=rel, asset_id=job["span"].asset_id,
                           source=job["span"].identity()))
        out.assets.append({"asset_id": job["span"].asset_id, "outputs": [rel]})
    index = {
        "render": {"rate": spu.RATE, "ticks_per_second": libsnd.TICKS_PER_SECOND, "seq_volume": SEQ_VOLUME,
                   "main_volume": "SsSetMVol(127, 127)", "reverb": {"mode": "STUDIO_B", "preset": STUDIO_B,
                   "work_area": REVERB_SIZE, "depth": REVERB_DEPTH, "registers": regs},
                   "loop": "intro + body twice; smpl loop = the second pass"},
        "tables": {"ptable": pt},
        "tracks": tracks,
    }
    _dump(out.dir / "index.json", index)
    out.finish([exe, src])
    return out
