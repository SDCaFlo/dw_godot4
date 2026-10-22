"""SOUND/VHB/*.VHB: sound banks (samples, instruments) and music sequences. Spec: specs/sound.md.

One folder per VAB (whole file, or one chunk of a bundle): samples as WAV, bank.json, a preview
SF2; music fonts also get their SEQ tracks as .seq + .mid. index.json says who loads what.
"""

import hashlib
import math
import struct

from ..assets import AssetWriter, _dump
from ..data.digimon import DIGIMON_TYPES
from ..exporters import sf2, wav
from ..formats import seq as seqfmt
from ..formats import vab
from ..paths import SECTOR_SIZE
from ..source import SourceFile
from . import maps, mmd_files

NAME = "sound"
SOURCE_PATH = "SOUND/VHB/*.VHB"
SPEC = "specs/sound.md"
CODE_REFS = [
    "dw_decomp/src/main/sound.c:385 readVHBFile / :439 readVHBFileSectors (VHB offsets -> VH copy, SsVabOpenHeadSticky, SsVabTransBody)",
    "dw_decomp/src/main/sound.c:517 initializeMusic (SS -> slot 0, SL -> slot 1), :710 VSLoadSounds (SB -> slot 8)",
    "dw_decomp/src/main/sound.c:721 loadMapSounds (ESALL, MAP_SOUND_PARA / 2 sectors), :676 loadPartnerSounds (VLALL, 15 sectors), :694 loadDigimonSounds (VBALL, 7 sectors)",
    "dw_decomp/src/main/sound.c:738 loadMusicFont (FAALL, 0x27 sectors, SEQ section -> SEQ_BUFFER), :475 seqOpen, :488 seqPlay, :753 playMusic",
    "dw_decomp/src/main/sound.c:602 startSound (tones whose max == note), :641 playSound (slot 0/1/8: prog value/16, note value%16+60)",
    "dw_decomp/src/main/script_interp.c:2587 playBGM, :1584 handleMusicOverride; btl.c:361 battle music (font 0x21, ENEMY_MUSIC_MAPPING)",
    "dw_decomp/src/main/file_table_us.c:756-762 VHB sizes",
]

DIR = "SOUND/VHB"
FILE_SIZES = {"ESALL": 0x387000, "FAALL": 0x283800, "SB": 0x3CACC, "SL": 0xD90C, "SS": 0xDF5C,
              "VBALL": 0xF8800, "VLALL": 0x78000}
CHUNK_SECTORS = {"VLALL": 15, "VBALL": 7, "FAALL": 0x27}
EXPECTED_CHUNKS = {"VLALL": 16, "VBALL": 71, "FAALL": 33, "ESALL": 22}
SLOTS = {"SS": [0], "SL": [1], "FAALL": [2], "VLALL": [3], "VBALL": [4, 5, 6, 7], "ESALL": [8], "SB": [8]}
# dw_decomp/config/us/symbols.txt
VHB_SOUNDBUFFER_START = 0x80127ED4  # u32[10]
DIGIMON_VLALL_SOUND_ID = 0x80127EFC  # u8[66]
DIGIMON_VBALL_SOUND_ID = 0x80127F40  # u8[180]
MAP_SOUND_PARA = 0x80127FF4  # {u16 sector*2, u16 count*2}[22]
ENEMY_MUSIC_MAPPING = 0x8012BAE4  # u8[48], battle track for enemy type - 0x43
ONE_SHOT_FONTS = {0x1D: 1, 0x1E: 2, 0x1F: 2, 0x20: 2}  # seqPlay: played once unless this track


def read_tables(exe: bytes) -> dict:
    def at(addr):
        return addr - mmd_files.EXE_LOAD

    return {
        "vhb_soundbuffer_start": list(struct.unpack_from("<10I", exe, at(VHB_SOUNDBUFFER_START))),
        "digimon_vlall_sound_id": list(exe[at(DIGIMON_VLALL_SOUND_ID):at(DIGIMON_VLALL_SOUND_ID) + 66]),
        "digimon_vball_sound_id": list(exe[at(DIGIMON_VBALL_SOUND_ID):at(DIGIMON_VBALL_SOUND_ID) + len(DIGIMON_TYPES)]),
        "map_sound_para": [list(struct.unpack_from("<HH", exe, at(MAP_SOUND_PARA) + 4 * i)) for i in range(22)],
        "enemy_music_mapping": list(exe[at(ENEMY_MUSIC_MAPPING):at(ENEMY_MUSIC_MAPPING) + 48]),
    }


def _attenuation(*volumes) -> int:
    """Centibels for the product of 0..127 volumes (SF2 initialAttenuation)."""
    gain = 1.0
    for v in volumes:
        gain *= v / 127
    return 1440 if gain <= 0 else min(1440, max(0, round(-200 * math.log10(gain))))


def _bank(out, folder, src, offset, size, label, usage) -> dict:
    """Convert one VAB (VHB at src[offset:offset+size]); returns a summary for index.json."""
    data = src.data[offset:offset + size]
    span = src.span(offset, size)
    try:
        secs = vab.parse_vhb(data)
        vh = vab.parse_vh(data, secs[0])
    except (vab.VabError, struct.error) as e:
        out.check(f"{label}: VHB/VAB header", False, str(e))
        return {}
    h = vh["header"]
    ps = h["programs"]
    out.check(f"{label}: VHB offsets ascending inside the chunk",
              all(a < b for a, b in zip(secs, secs[1:])) and secs[-1] <= size, str(secs))
    out.check(f"{label}: chunk is zero after the VHB end", not any(data[secs[-1]:]), f"end 0x{secs[-1]:X}")
    out.check(f"{label}: VAB version 7", h["version"] == 7, str(h["version"]))
    vh_size = vab.VAB_HEADER + vab.PROGRAMS * vab.PROG_SIZE + ps * vab.TONES_PER_PROGRAM * vab.TONE_SIZE + vab.VAG_TABLE * 2
    out.check(f"{label}: VH size = 32 + 2048 + 512 * programs + 512 = VB offset", secs[0] + vh_size == secs[1],
              f"0x{secs[0] + vh_size:X} / 0x{secs[1]:X}")
    out.check(f"{label}: fsize = VB end - VH start", h["fsize"] == secs[2] - secs[0], f"0x{h['fsize']:X}")
    progs = [p["index"] for p in vh["programs"] if p["tones"]]
    out.check(f"{label}: programs with tones = header programs", len(progs) == ps, f"{progs}")
    out.check(f"{label}: tone counts sum to header tones",
              sum(vh["programs"][p]["tones"] for p in progs) == h["tones"], str(h["tones"]))
    bad_tones = []
    programs = []
    for k, p in enumerate(progs):
        tones = vh["tones"][k][:vh["programs"][p]["tones"]]
        bad_tones += [(p, t["program"], t["vag"]) for t in tones if t["program"] != p or not 1 <= t["vag"] <= h["vags"]]
        programs.append(dict(vh["programs"][p], tone_block=k, tone_list=tones,
                             unused_tone_slots=vh["tones"][k][len(tones):]))
    out.check(f"{label}: tones name their program and an existing sample", not bad_tones, str(bad_tones[:3]))

    body = data[secs[1]:secs[2]]
    vags = vab.split_vags(vh, body)
    listed = sum(len(v) for _, v in vags)
    out.check(f"{label}: listed sample sizes fit in VB", listed <= len(body), f"{listed} / {len(body)}")
    unreferenced = body[listed:]

    samples, sf2_samples, files = [], [], []
    for n, (voff, vdata) in enumerate(vags, start=1):
        sample = {"vag": n, "offset_in_vb": voff, "size": len(vdata), "sha1": hashlib.sha1(vdata).hexdigest()}
        if not vdata:
            samples.append(dict(sample, file=None))
            continue
        try:
            dec = vab.decode_adpcm(vdata)
        except vab.VabError as e:
            out.check(f"{label}: sample {n} decodes", False, str(e))
            continue
        loop = (dec["loop_start"], dec["loop_end"]) if dec["loop_end"] is not None else None
        root = next((t["center"] for p in programs for t in p["tone_list"] if t["vag"] == n), 60)
        path = folder / f"vag_{n:02d}.wav"
        wav.write(path, wav.encode(dec["samples"], vab.BASE_RATE, loop, root))
        files.append(out._rel(path))
        sample.update(file=out._rel(path), samples=len(dec["samples"]), loop=list(loop) if loop else None,
                      end_flag_block=dec["end_block"], blocks=dec["blocks"])
        samples.append(sample)
        sf2_samples.append({"name": f"vag_{n:02d}", "data": dec["samples"], "rate": vab.BASE_RATE, "root": root,
                            "loop": loop, "vag": n})

    # preview soundfont
    index_of = {s["vag"]: i for i, s in enumerate(sf2_samples)}
    instruments, presets = [], []
    for p in programs:
        zones = [{"sample": index_of[t["vag"]], "key_lo": min(t["min"], t["max"]), "key_hi": max(t["min"], t["max"]),
                  "root": t["center"], "fine_tune": round(t["shift"] * 100 / 128),
                  "pan": round((t["pan"] - 64) * 500 / 64), "attenuation": _attenuation(t["volume"], p["volume"]),
                  "loop": sf2_samples[index_of[t["vag"]]]["loop"] is not None}
                 for t in p["tone_list"] if t["vag"] in index_of]
        if not zones:
            continue
        instruments.append({"name": f"program {p['index']}", "zones": zones})
        for bank in (0, 128):  # 128: MIDI channel 10 is a drum channel in GM players
            presets.append({"name": f"program {p['index']}", "program": p["index"], "bank": bank,
                            "instrument": len(instruments) - 1})
    if sf2_samples:
        sf2.write(folder / "bank.sf2", sf2.build(label, sf2_samples, instruments, presets))
        files.append(out._rel(folder / "bank.sf2"))

    record = {
        "asset_id": span.asset_id,
        "family": NAME,
        "format": "VHB (VAB)",
        "source": span.identity(),
        "psxprev_name": span.psxprev_name,
        "vhb_offsets": secs,
        "vab_header": h,
        "programs": programs,
        "vag_size_table": vh["vag_sizes"],
        "samples": samples,
        "unreferenced_vb_bytes": {"offset_in_vb": listed, "size": len(unreferenced), "hex": unreferenced.hex()},
        "usage": usage,
        "playback": {"base_rate": vab.BASE_RATE,
                     "pitch": "rate = 44100 * 2 ** ((note - center + shift / 128) / 12)",
                     "sound_effect": "playSound: every tone of the program whose max == note"},
    }
    summary = {"asset_id": span.asset_id, "folder": out._rel(folder) if folder.exists() else None,
               "programs": ps, "tones": h["tones"], "samples": len(vags)}

    if len(secs) == 4:  # FAALL: SEQ table
        seq_data = data[secs[2]:secs[3]]
        tracks = []
        try:
            offs = seqfmt.parse_table(seq_data)
        except struct.error as e:
            out.check(f"{label}: SEQ table", False, str(e))
            offs = []
        ends = offs[1:] + [len(seq_data)]
        for t, (o, e) in enumerate(zip(offs, ends)):
            try:
                s = seqfmt.parse(seq_data, o)
            except (seqfmt.SeqError, IndexError) as ex:
                out.check(f"{label}: track {t} parses", False, str(ex))
                continue
            gap = seq_data[o + s["size"]:e]
            out.check(f"{label}: track {t} parses and ends at the next track (padding 00/CD fill)",
                      o + s["size"] <= e and 1 <= len(gap) <= 4 and gap[0] == 0 and set(gap) <= {0x00, 0xCD},
                      f"end 0x{o + s['size']:X}, next 0x{e:X}, padding {gap.hex()}")
            raw = seq_data[o:o + s["size"]]
            (folder / f"track_{t}.seq").write_bytes(raw)
            (folder / f"track_{t}.mid").write_bytes(seqfmt.to_midi(s))
            files += [out._rel(folder / f"track_{t}.seq"), out._rel(folder / f"track_{t}.mid")]
            tracks.append({"track": t, "offset_in_seq_section": o, "size": s["size"], "padding_hex": gap.hex(),
                           "sha1": hashlib.sha1(raw).hexdigest(), "version": s["version"],
                           "resolution": s["resolution"], "tempo": s["tempo"], "rhythm": s["rhythm"],
                           "ticks": s["ticks"], "seconds_at_start_tempo": round(s["ticks"] * s["tempo"] / s["resolution"] / 1e6, 2),
                           "channels": s["channels"], "notes": s["notes"], "loop_markers": s["loop_markers"],
                           "files": [f"track_{t}.seq", f"track_{t}.mid"]})
        record["seq_section"] = {"offset": secs[2], "size": len(seq_data), "table": offs, "tracks": tracks}
        summary["tracks"] = len(tracks)

    record["outputs"] = files
    _dump(folder / "bank.json", record)
    out.assets.append({"asset_id": span.asset_id, "sidecar": out._rel(folder / "bank.json"), "outputs": files})
    summary["folder"] = out._rel(folder)
    return summary


def convert(input_root, output_root) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    exe = SourceFile.open(input_root, mmd_files.EXE)
    tables = read_tables(exe.data)
    map_entries = maps.read_tables(exe.data)["entries"]
    sources = [exe]
    on_disc = sorted(p.stem for p in (input_root / DIR).glob("*.VHB"))
    out.check("VHB files on disc are the ones the code loads", on_disc == sorted(FILE_SIZES), str(on_disc))
    index = {"slots": {"vab_slots": SLOTS, "spu_start": tables["vhb_soundbuffer_start"]}, "files": {}}

    def type_names(ids, value):
        return [{"type": t, "name": DIGIMON_TYPES[t][2]} for t, v in enumerate(ids) if v == value]

    for name in sorted(FILE_SIZES):
        src = SourceFile.open(input_root, f"{DIR}/{name}.VHB")
        sources.append(src)
        out.check(f"{name}: size matches FILE_OFFSET_TABLE", src.size == FILE_SIZES[name], f"0x{src.size:X}")
        if name in CHUNK_SECTORS:
            step = CHUNK_SECTORS[name] * SECTOR_SIZE
            chunks = [(i * step, step) for i in range(src.size // step)]
            out.check(f"{name}: whole number of {CHUNK_SECTORS[name]}-sector chunks", src.size % step == 0)
        elif name == "ESALL":
            para = tables["map_sound_para"]
            chunks = [(a // 2 * SECTOR_SIZE, b // 2 * SECTOR_SIZE) for a, b in para]
            tiled = all(chunks[i][0] + chunks[i][1] == chunks[i + 1][0] for i in range(len(chunks) - 1))
            out.check("ESALL: MAP_SOUND_PARA ranges tile the file", tiled and chunks[-1][0] + chunks[-1][1] == src.size)
        else:
            chunks = [(0, src.size)]
        if name in EXPECTED_CHUNKS:
            out.check(f"{name}: {EXPECTED_CHUNKS[name]} chunks", len(chunks) == EXPECTED_CHUNKS[name], str(len(chunks)))

        entries = []
        for k, (off, size) in enumerate(chunks):
            if name == "FAALL":
                font = k + 1
                folder, label = out.dir / name / f"font_{font:02d}", f"FAALL font {font}"
                usage = {"loader": f"loadMusicFont({font}) -> slot 2", "font": font,
                         "played_once_unless_track": ONE_SHOT_FONTS.get(font)}
                if font == 0x21:
                    usage["battle"] = {"tracks": "btl.c: 3 boss/special, 0 or 1 normal, ENEMY_MUSIC_MAPPING[type - 0x43]",
                                       "enemy_music_mapping": tables["enemy_music_mapping"]}
            elif name == "VLALL":
                folder, label = out.dir / name / f"set_{k:02d}", f"VLALL set {k}"
                usage = {"loader": f"loadPartnerSounds -> readVHBFileSectors(3, VLALL, {k} * 15, 15)",
                         "partner_types": type_names(tables["digimon_vlall_sound_id"], k)}
                if k == 15:
                    usage["note"] = "also used for types outside 1-65"
            elif name == "VBALL":
                folder, label = out.dir / name / f"set_{k:02d}", f"VBALL set {k}"
                usage = {"loader": f"loadDigimonSounds(slot 4-7) -> readVHBFileSectors(VBALL, {k} * 7, 7)",
                         "digimon_types": type_names(tables["digimon_vball_sound_id"], k)}
            elif name == "ESALL":
                folder, label = out.dir / name / f"set_{k:02d}", f"ESALL set {k}"
                usage = {"loader": f"loadMapSounds({k}) -> slot 8", "map_sound_para": tables["map_sound_para"][k],
                         "maps": [{"id": e["id"], "name": e["filename"], "display_name": e["display_name"]}
                                  for e in map_entries if e["filename"] and e["sound_id"] == k]}
            else:
                folder, label = out.dir / name, name
                usage = {"loader": {"SS": "initializeMusic -> slot 0", "SL": "initializeMusic -> slot 1",
                                    "SB": "VSLoadSounds (VS mode) -> slot 8"}[name]}
            entries.append(dict(_bank(out, folder, src, off, size, label, usage), chunk=k, offset=off, size=size))
        index["files"][name] = entries

    referenced_vball = set(tables["digimon_vball_sound_id"])
    out.check("every VBALL set is used by a Digimon type", referenced_vball == set(range(EXPECTED_CHUNKS["VBALL"])),
              str(sorted(set(range(EXPECTED_CHUNKS["VBALL"])) - referenced_vball)))
    index["tables"] = tables
    _dump(out.dir / "index.json", index)
    out.finish(sources)
    return out
