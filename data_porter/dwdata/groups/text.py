"""Text group: the decomp's string tables (text/<dir>/<name>.yaml) -> output/text/<dir>/<name>.json.

Follows specs/text.md. Each YAML file belongs to src/<dir>/<name>.c (which includes the
generated <text/<dir>/<name>.h>); its blocks become C strings, string arrays or text
embedded in other tables through a macro (DIGIMON_PARA_NAME(STR_DIGIMON_NAME_AGUMON)).
Every variant is kept as written; `text` adds the value each language's release really uses.
"""

import re
from collections import defaultdict

from .. import textyaml
from ..cdata import CError, CIndex
from ..decomp import Decomp
from ..output import GroupWriter
from ..source import SourceText

NAME = "text"
SPEC = "specs/text.md"
PURPOSE = "In-game strings of all releases (names, descriptions, menus, battle and minigame messages)"
SOURCE_GLOB = "text/**/*.yaml"
EXCLUDED = {"text/example.yaml": "format documentation of the decomp's text generator, not game text"}

# Region (include/dw/version.h) -> language key used in the YAML files.
LANGUAGE_OF_REGION = {"NTSCJ": "ja", "NTSCU": "en_us", "PAL": "en_eu"}
# A missing en_eu key means the EU release uses the en_us text (stored as full-width glyphs).
FALLBACK = {"en_eu": "en_us"}
REQUIRED = ("ja", "en_us")
VARIANT_RE = re.compile(r"(ja|en_us|en_eu)(?:@([a-z0-9_]+))?")
BLOCK_OPTIONS = ("storage", "macro", "lines", "empty")

FILE_PURPOSES = {
    "btl/battle_effect": "Battle-end box messages: command learned, item dropped, injury, technique learned, MP bonus",
    "btl/battle_hud": "Battle HUD / battle-end text pieces (colour codes, MP bonus percentages)",
    "btl/command_shout": "Battle command names and the shouts the tamer calls out",
    "fish/fish": "Fishing minigame messages (bait, line, catch length) and EU digit glyphs",
    "kar/kar": "Curling minigame menu and the Penguinmon / MetalMamemon tutorial dialogue",
    "main/battle_ui": "Bits labels of the battle result UI",
    "main/game_menu": "Status / technique / medal / card / chart menu labels, medal names and descriptions, tamer level titles",
    "main/inventory": "Inventory menu labels (use, move, sort, drop), sort modes, drop confirmation",
    "main/item": "Technique names (MOVE_NAMES), item names (ITEM_NAMES) and descriptions (ITEM_DESCS), sickness message",
    "main/main": "Digimon names (DIGIMON_NAMES, embedded in DIGIMON_DATA) and the trial-version end message",
    "main/main_menu": "Save / load screens: labels, memory card messages, save messages",
    "main/map": "Map (area) names shown when entering an area",
    "main/partner_impl": "Partner sickness message",
    "main/script_common": "BGM track names (jukebox), tournament names and grades",
    "main/script_value": "Speaker names used by event scripts (sign, box, NPC Digimon)",
    "main/tamer": "Tamer messages (item pickup, inventory full, tamer level up/down)",
    "main/ui": "Stat labels (HP, MP, Off, Def, Speed, Brain)",
    "main/utils2": "Pause label",
    "shop/script_menu": "Naming screen (name entry rows and buttons) and trade label",
    "std/std_main": "Battle command names of the STD overlay",
    "trn/trn_reward": "Training reward messages (commands taught, technique mastered)",
    "vs/vs_main": "Battle command names of the versus mode",
    "vs/vs_scene": "Versus mode result (win / lose)",
    "vs/vs_select": "Versus mode 'press start' prompt",
}

SCHEMA = {
    "records": "one block per top-level YAML key, in file order",
    "block": {
        "block": "block name (YAML top-level key); the generated header defines <block>_TEXT (and <block>_STRINGS for entries)",
        "line": "line of the block in the YAML file",
        "kind": "'strings': named C strings; 'entries': C array of strings (index = original array index); 'text': the block itself is one string",
        "options": "generator options as written: storage (named / literal / embedded per release), macro (embedding macro), lines (strings per entry per release), empty (symbol of the empty string)",
        "c": "C side: array symbol (entries), generated macros, where the owning C file places them",
        "used_by": "references to the block's array symbol (entries blocks)",
        "strings / entries": "the string records",
    },
    "string": {
        "id": "C symbol / string id (first name if the entry has one name per line); null for an unnamed entry",
        "index": "entries only: array index used by the code (e.g. MOVE_NAMES[move id])",
        "line": "line in the YAML file",
        "null_entry": "entries only: true for a NULL pointer entry",
        "text": "value used by each language's main release (ja: jp_rev1, en_us: us, en_eu: eu); null = the string does not exist there; cut at the first NUL like a C string; lines of a multi-line entry joined with \\n",
        "variants": "every language key exactly as written (lossless); null = NULL; a missing key = not written (en_eu falls back to en_us)",
        "release_text": "only releases whose text differs from their language's main release (e.g. ja@jp_trial)",
        "lines": "multi-line entries (lines option): the line strings per language, padded with '' like the C array",
        "line_ids": "one C name per line when the entry is split in several lines",
        "named": "releases where an otherwise literal entry is a named string (generator option)",
        "same_as": "unnamed entries: per language, the earlier named entry with the same text (the generator points both to one string)",
        "symbol": "US RAM symbol (config/us/symbols*.txt) when the string is a named symbol",
        "used_by": "code references: file, line, binary, enclosing function / data / macro, releases that compile the line",
        "c_definitions": "references that are the string's own C definition (`char X[] = \"...\";` under #if VERSION_...)",
        "c_text": "releases whose text comes from that C definition because the YAML has none: {release: {text, at}}; "
                  "already included in text / release_text",
    },
}


class Context:
    def __init__(self, decomp: Decomp):
        self.decomp = decomp
        self.releases = decomp.releases
        self.language_of = {name: LANGUAGE_OF_REGION.get(r.region) for name, r in self.releases.items()}
        self.languages = {}
        for name, lang in self.language_of.items():
            self.languages.setdefault(lang, []).append(name)
        # Main release of a language: the newest build of its region (jp_rev1 for ja).
        self.main_release = {lang: max(rels, key=lambda n: self.releases[n].date)
                             for lang, rels in self.languages.items()}


def _option(opt, release: str, default=None):
    if isinstance(opt, dict):
        return opt.get(release, opt.get("default", default))
    return default


def _c_string(s):
    """What C sees: text up to the first NUL."""
    return s.split("\0", 1)[0] if isinstance(s, str) else s


class FileModel:
    """One YAML file interpreted as blocks of strings; collects format issues instead of raising."""

    def __init__(self, ctx: Context, src: SourceText, root):
        self.ctx, self.src = ctx, src
        self.issues = []
        self.blocks = []
        if not isinstance(root, textyaml.Map):
            self.issue(1, "document is not a mapping")
            return
        for name, node in root.items():
            self.blocks.append(self._block(name, root.key_lines[name], node))

    def issue(self, line: int, message: str) -> None:
        self.issues.append(f"{self.src.path}:{line}: {message}")

    # -- parsing ----------------------------------------------------------------------------

    def _variants(self, node, owner: str) -> dict:
        variants = {}
        for key, value in node.items():
            m = VARIANT_RE.fullmatch(key)
            if not m:
                continue
            lang, release = m.groups()
            if release is not None and (release not in self.ctx.releases or self.ctx.language_of[release] != lang):
                self.issue(node.key_lines[key], f"{owner}: variant {key!r} names no {lang} release")
            if isinstance(value, textyaml.Scalar):
                variants[key] = value.value
            elif isinstance(value, textyaml.Seq) and all(isinstance(v, textyaml.Scalar) for v in value.items):
                variants[key] = [v.value for v in value.items]
            else:
                self.issue(node.key_lines[key], f"{owner}: {key} must be a string, NULL or a list of lines")
        for lang in REQUIRED:
            if lang not in variants:
                self.issue(node.line, f"{owner}: no {lang} text")
        return variants

    def _string(self, sid, line: int, node, extra_keys=()) -> dict:
        if not isinstance(node, textyaml.Map):
            self.issue(line, f"{sid}: expected a mapping of language keys")
            return {"id": sid, "line": line, "variants": {}}
        for key in node.keys():
            if not VARIANT_RE.fullmatch(key) and key not in extra_keys:
                self.issue(node.key_lines[key], f"{sid}: unknown key {key!r}")
        return {"id": sid, "line": line, "variants": self._variants(node, sid or f"entry@{line}")}

    def _block(self, name: str, line: int, node) -> dict:
        block = {"block": name, "line": line, "kind": None, "options": {}, "items": []}
        if not isinstance(node, textyaml.Map):
            self.issue(line, f"{name}: block must be a mapping")
            return block
        keys = node.keys()
        if "strings" in keys and "entries" in keys:
            self.issue(line, f"{name}: both strings and entries")
        if "strings" in keys or "entries" in keys:
            for key in keys:
                if key in BLOCK_OPTIONS:
                    block["options"][key] = textyaml.to_python(node.get(key))
                elif key not in ("strings", "entries"):
                    self.issue(node.key_lines[key], f"{name}: unknown block key {key!r}")
        if "strings" in keys:
            block["kind"] = "strings"
            strings = node.get("strings")
            if not isinstance(strings, textyaml.Map):
                self.issue(line, f"{name}: strings must be a mapping")
            else:
                for sid, snode in strings.items():
                    block["items"].append(self._string(sid, strings.key_lines[sid], snode))
        elif "entries" in keys:
            block["kind"] = "entries"
            entries = node.get("entries")
            if not isinstance(entries, textyaml.Seq):
                self.issue(line, f"{name}: entries must be a list")
            else:
                for index, enode in enumerate(entries.items):
                    block["items"].append(self._entry(name, index, enode))
        else:
            block["kind"] = "text"
            block["items"].append(self._string(name, line, node))
        self._resolve(block)
        return block

    def _entry(self, block: str, index: int, node) -> dict:
        if isinstance(node, textyaml.Scalar):
            if node.value is not None:
                self.issue(node.line, f"{block}[{index}]: a scalar entry must be NULL")
            return {"index": index, "id": None, "line": node.line, "null_entry": True, "variants": {}}
        entry = self._string(None, node.line, node, extra_keys=("name", "named"))
        entry["index"] = index
        names = textyaml.to_python(node.get("name")) if "name" in node else None
        if isinstance(names, list):
            if not names or not all(isinstance(n, str) for n in names):
                self.issue(node.line, f"{block}[{index}]: bad name list")
            entry["id"] = names[0] if names else None
            entry["line_ids"] = names
        elif names is not None and not isinstance(names, str):
            self.issue(node.line, f"{block}[{index}]: bad name")
        else:
            entry["id"] = names
        if "named" in node:
            named = textyaml.to_python(node.get("named"))
            if not isinstance(named, list) or any(r not in self.ctx.releases for r in named):
                self.issue(node.line, f"{block}[{index}]: named must list releases")
            entry["named"] = named
        return entry

    # -- resolution -------------------------------------------------------------------------

    def value_for(self, item: dict, release: str):
        """(raw value, key it came from) of an item in a release, before line handling."""
        lang = self.ctx.language_of[release]
        variants = item["variants"]
        for key in (f"{lang}@{release}", lang, FALLBACK.get(lang)):
            if key and key in variants:
                return variants[key], key
        return None, None

    def _lines(self, block: dict, item: dict, release: str, value):
        n = _option(block["options"].get("lines"), release, 1)
        where = f"{block['block']}[{item.get('index', item['id'])}]"
        if not isinstance(n, int) and not (isinstance(n, str) and n.isdigit()):
            self.issue(item["line"], f"{where}: lines option must be a number")
            n = 1
        n = int(n)
        if value is None:
            return None, n
        if isinstance(value, list):
            if n == 1:
                self.issue(item["line"], f"{where}: list of lines in a one-line release ({release})")
            if len(value) > n:
                self.issue(item["line"], f"{where}: {len(value)} lines, {release} has {n}")
            return list(value) + [""] * (n - len(value)), n
        return [value] + [""] * (n - 1), n

    def _resolve(self, block: dict) -> None:
        ctx = self.ctx
        for item in block["items"]:
            if item.get("null_entry"):
                item["text"] = {lang: None for lang in ctx.languages}
                item["by_release"] = {r: None for r in ctx.releases}
                continue
            by_release, lines_of = {}, {}
            for release in ctx.releases:
                value, _ = self.value_for(item, release)
                lines, n = self._lines(block, item, release, value)
                if lines is None:
                    by_release[release] = None
                    continue
                if n > 1:
                    lines_of[release] = lines
                    shown = [_c_string(x) if x is not None else "" for x in lines]
                    while len(shown) > 1 and shown[-1] == "":
                        shown.pop()
                    by_release[release] = "\n".join(shown)
                else:
                    by_release[release] = _c_string(lines[0])
            item["by_release"] = by_release
            item["text"] = {lang: by_release[ctx.main_release[lang]] for lang in ctx.languages}
            item["release_text"] = {r: t for r, t in by_release.items()
                                    if t != item["text"][ctx.language_of[r]]}
            item["lines"] = {lang: lines_of[ctx.main_release[lang]] for lang in ctx.languages
                             if ctx.main_release[lang] in lines_of}
            if "line_ids" in item:
                max_lines = max([_option(block["options"].get("lines"), r, 1) for r in ctx.releases], key=int)
                if len(item["line_ids"]) > int(max_lines):
                    self.issue(item["line"], f"{block['block']}[{item['index']}]: more names than lines")
        if block["kind"] == "entries":
            for item in block["items"]:
                if item["id"] is None and not item.get("null_entry"):
                    item["same_as"] = {}
                    for lang in ctx.languages:
                        text = item["text"][lang]
                        match = next((e["id"] for e in block["items"][:item["index"]]
                                      if e["id"] is not None and not e.get("null_entry")
                                      and e["text"][lang] == text), None)
                        item["same_as"][lang] = match if text is not None else None

    # -- names ------------------------------------------------------------------------------

    def defined_names(self):
        """(name, release, text) of every C name this file defines in each release."""
        for block in self.blocks:
            for item in block["items"]:
                if item.get("null_entry"):
                    continue
                names = item.get("line_ids") or ([item["id"]] if item["id"] else [])
                for release, text in item["by_release"].items():
                    if text is None:
                        continue
                    if len(names) > 1:
                        value, _ = self.value_for(item, release)
                        parts = value if isinstance(value, list) else [value]
                        for name, part in zip(names, parts):
                            if part is not None:
                                yield name, release, _c_string(part)
                    elif names:
                        yield names[0], release, text


def load_file(decomp: Decomp, path: str) -> FileModel:
    """One text file interpreted on its own (for groups that take names from it, e.g. MOVE_NAMES)."""
    src = SourceText(decomp.root, path)
    return FileModel(Context(decomp), src, textyaml.parse(src.text, path))


def block_of(model: FileModel, name: str):
    return next((b for b in model.blocks if b["block"] == name), None)


def _owner_c(src_path: str) -> str:
    # text/<dir>/<name>.yaml -> src/<dir>/<name>.c
    return "src/" + src_path[len("text/"):-len(".yaml")] + ".c"


def _table_name(src_path: str) -> str:
    return src_path[len("text/"):-len(".yaml")]


def _ref_out(ref: dict) -> dict:
    out = {"file": ref["file"], "line": ref["line"], "binary": ref["binary"], "in": ref["in"], "kind": ref["kind"],
           "releases": ref["releases"]}
    if "unknown" in ref:
        out["unknown"] = ref["unknown"]
    return out


def _string_out(item: dict, ctx: Context, symbols: dict, refs: list) -> dict:
    out = {}
    if "index" in item:
        out["index"] = item["index"]
    out["id"] = item["id"]
    out["line"] = item["line"]
    if item.get("null_entry"):
        out["null_entry"] = True
    out["text"] = item["text"]
    out["variants"] = item["variants"]
    for key in ("release_text", "lines", "line_ids", "named", "same_as", "c_text"):
        if item.get(key):
            out[key] = item[key]
    names = item.get("line_ids") or ([item["id"]] if item["id"] else [])
    sym = {n: symbols[n] for n in names if n in symbols}
    if sym:
        out["symbol"] = sym[names[0]] if len(names) == 1 else sym
    out["used_by"] = [_ref_out(r) for r in refs]
    c_defs = [_ref_out(r) for r in refs if r["kind"] == "data" and r["in"] in names]
    if c_defs:
        # The C file defines this name itself for these releases (text not in the YAML).
        out["c_definitions"] = c_defs
    return out


def _apply_c_text(item: dict, binary: str, ctx: Context, c_text: dict) -> None:
    """Fill releases where the YAML has no text but the C file defines the string itself."""
    if item.get("null_entry") or not item["id"] or item.get("line_ids"):
        return
    found = {}
    for release, text in item["by_release"].items():
        hit = c_text.get((binary, release, item["id"]))
        if hit and text is None:
            item["by_release"][release] = hit[0]
            found[release] = {"text": hit[0], "at": f"{hit[1]}:{hit[2]}"}
    if not found:
        return
    item["c_text"] = found
    item["text"] = {lang: item["by_release"][ctx.main_release[lang]] for lang in ctx.languages}
    item["release_text"] = {r: t for r, t in item["by_release"].items() if t != item["text"][ctx.language_of[r]]}


def _md_cell(text) -> str:
    if text is None:
        return "—"
    s = text.replace("\0", "\\0").replace("\n", " ⏎ ").replace("|", "\\|")
    return f"`{s}`" if s.strip() != s or s == "" else s


def _report(models: list, ctx: Context, codes: dict) -> str:
    out = ["# Text report", "",
           "Generated by `python -m dwdata convert text`. One table per block; columns are the text each "
           "language's main release uses (ja = jp_rev1, en_us = us, en_eu = eu). — = the string does not exist "
           "in that release; ⏎ = line break of a multi-line entry; `\\0` = NUL byte. See `specs/text.md`.", "",
           "## Control codes found", ""]
    for lang, found in codes.items():
        out.append(f"- {lang}: " + (", ".join(f"`{c}` ×{n}" for c, n in sorted(found.items())) or "none"))
    out.append("")
    for model in models:
        out += [f"## {model.src.path}", "", f"Owner: `{_owner_c(model.src.path)}`. "
                f"{FILE_PURPOSES.get(_table_name(model.src.path), '')}", ""]
        for block in model.blocks:
            out += [f"### {block['block']} ({block['kind']}, {len(block['items'])})", ""]
            if block["options"]:
                out += ["Options: `" + ", ".join(f"{k}: {v}" for k, v in block["options"].items()) + "`", ""]
            first = "index | id" if block["kind"] == "entries" else "id"
            out.append(f"| {first} | ja | en_us | en_eu |")
            out.append("|" + "---|" * (len(first.split("|")) + 3))
            for item in block["items"]:
                sid = item["id"] or (f"= {item['same_as'].get('en_us')}" if item.get("same_as") else "NULL"
                                     if item.get("null_entry") else "")
                head = f"{item['index']} | {sid}" if block["kind"] == "entries" else sid
                out.append(f"| {head} | " + " | ".join(_md_cell(item["text"][lang]) for lang in ("ja", "en_us", "en_eu"))
                           + " |")
            out.append("")
    return "\n".join(out)


def _control_codes(models: list) -> dict:
    found = {"en_us": defaultdict(int), "en_eu": defaultdict(int)}
    for model in models:
        for block in model.blocks:
            for item in block["items"]:
                for lang, pattern in (("en_us", r"#[A-Z][0-9]?"), ("en_eu", r"\{[^{}]*\}")):
                    text = item["text"].get(lang)
                    if text:
                        for code in re.findall(pattern, text):
                            found[lang][code] += 1
    return {lang: dict(v) for lang, v in found.items()}


def convert(input_root, output_root) -> GroupWriter:
    out = GroupWriter(output_root, NAME, SPEC, PURPOSE)
    out.reset()
    decomp = Decomp(input_root)
    if not out.check("decomp found", decomp.exists(), str(decomp.root)):
        out.finish([])
        return out
    ctx = Context(decomp)
    out.check("every release maps to a language", all(ctx.language_of.values()),
              ", ".join(f"{r}->{lang}" for r, lang in ctx.language_of.items()))

    paths = sorted(decomp.rel(p) for p in decomp.root.glob(SOURCE_GLOB))
    excluded = [p for p in paths if p in EXCLUDED]
    paths = [p for p in paths if p not in EXCLUDED]
    out.check("text files found", len(paths) > 0, f"{len(paths)} files, excluded: {excluded}")

    sources, models = [], []
    for path in paths:
        src = SourceText(decomp.root, path)
        sources.append(src.identity())
        try:
            root = textyaml.parse(src.text, path)
        except textyaml.YamlError as e:
            out.check(f"{path}: parse", False, str(e))
            continue
        model = FileModel(ctx, src, root)
        out.check(f"{path}: format", not model.issues, "; ".join(model.issues[:20]) or
                  f"{len(model.blocks)} blocks, {sum(len(b['items']) for b in model.blocks)} strings")
        models.append(model)

    # Which C names each binary's text defines, per release (for references and uniqueness).
    definitions = defaultdict(list)   # (binary, release, name) -> [(file, text)]
    binary_of = {}
    for model in models:
        binary_of[model.src.path] = decomp.binary_of(_owner_c(model.src.path))
        for name, release, text in model.defined_names():
            definitions[(binary_of[model.src.path], release, name)].append((model.src.path, text))
    defined_in = defaultdict(set)     # name -> binaries defining it
    for binary, _, name in definitions:
        defined_in[name].add(binary)
    clashes = [f"{n} ({b}, {r}): " + ", ".join(f for f, _ in v) for (b, r, n), v in sorted(definitions.items())
               if len({t for _, t in v}) > 1]
    out.check("a C name has one text per binary and release", not clashes, "; ".join(clashes[:20]) or
              f"{len({n for _, _, n in definitions})} names")

    names = set(defined_in)
    for model in models:
        for block in model.blocks:
            names.add(block["block"])
            names.update(f"{block['block']}{s}" for s in ("_TEXT", "_STRINGS"))
            if block["options"].get("macro"):
                names.add(block["options"]["macro"])
    refs = decomp.references(names)

    def refs_for(name: str, binary: str) -> list:
        # Overlays link against main; main never references overlay data.
        return [r for r in refs.get(name, []) if r["binary"] == binary
                or (binary == "main" and r["binary"] not in defined_in[name])]

    # Some releases define a string directly in C (`char STR_X[] = "...";` under #if VERSION_...)
    # instead of through the YAML: the reference that is the definition itself is a data scope
    # named like the string.
    c_defined = {(r["binary"], release, name) for name in defined_in for r in refs.get(name, [])
                 if r["kind"] == "data" and r["in"] == name for release in r["releases"]}
    # Read the text of those C definitions and use it where the YAML has none.
    index, c_text, c_errors = CIndex(decomp), {}, []
    for name in sorted(defined_in):
        for r in refs.get(name, []):
            if r["kind"] != "data" or r["in"] != name:
                continue
            try:
                loaded = index.table(r["file"], name)
            except CError as e:
                c_errors.append(f"{name}: {e}")
                continue
            for release in r["releases"]:
                value = loaded.get(release) and loaded[release].value
                if isinstance(value, str):
                    c_text[(r["binary"], release, name)] = (value, r["file"], r["line"])
                else:
                    c_errors.append(f"{name} ({release}) at {r['file']}:{r['line']}: not a string")
    out.check("strings defined in C are read", not c_errors, "; ".join(c_errors[:10]) or
              ", ".join(sorted({f"{n} ({r})" for (_, r, n) in c_text})))
    for model in models:
        for block in model.blocks:
            for item in block["items"]:
                _apply_c_text(item, binary_of[model.src.path], ctx, c_text)

    missing_text = []
    for name, bins in sorted(defined_in.items()):
        for binary in sorted(bins):
            for ref in refs_for(name, binary):
                for release in ref["releases"]:
                    if (binary, release, name) not in definitions and (binary, release, name) not in c_defined:
                        missing_text.append(f"{name} used at {ref['file']}:{ref['line']} ({release})")
    out.check("code only uses strings that exist in the release compiling it", not missing_text,
              "; ".join(missing_text[:20]) or "all references resolved")

    unmatched = []
    for model in models:
        for block in model.blocks:
            for item in block["items"]:
                for lang, match in (item.get("same_as") or {}).items():
                    if match is None and item["text"][lang] is not None:
                        unmatched.append(f"{model.src.path}:{item['line']} {block['block']}[{item['index']}] ({lang})")
    out.check("every unnamed entry repeats an earlier named entry", not unmatched, "; ".join(unmatched[:20]) or
              "ok")

    for model in models:
        owner = _owner_c(model.src.path)
        binary = binary_of[model.src.path]
        header = f"<text/{_table_name(model.src.path)}.h>"
        owner_path = decomp.root / owner
        owner_text = owner_path.read_text(encoding="utf-8", errors="replace") if owner_path.is_file() else ""
        out.check(f"{model.src.path}: {owner} includes {header}", f"#include {header}" in owner_text, owner)
        symbols = decomp.symbols(binary)

        records, unplaced, all_refs = [], [], []
        for block in model.blocks:
            name = block["block"]
            macros = [f"{name}_TEXT"] + ([f"{name}_STRINGS"] if block["kind"] == "entries" else [])
            if block["options"].get("macro"):
                macros.append(block["options"]["macro"])
            placed = {m: [r["line"] for r in refs.get(m, []) if r["file"] == owner] for m in macros}
            placed = {m: lines for m, lines in placed.items() if lines}
            if not placed:
                unplaced.append(name)
            rec = {"block": name, "line": block["line"], "kind": block["kind"], "options": block["options"],
                   "c": {"file": owner, "binary": binary, "macros": macros, "placed_at": placed}}
            if block["kind"] == "entries":
                rec["c"]["array"] = name
                if name in symbols:
                    rec["c"]["symbol"] = symbols[name]
                array_refs = [r for r in refs_for(name, binary) if r["kind"] != "macro" or r["file"] != owner]
                rec["used_by"] = [_ref_out(r) for r in array_refs]
                all_refs += [(r, name) for r in array_refs]
            items = []
            for item in block["items"]:
                item_names = item.get("line_ids") or ([item["id"]] if item["id"] else [])
                item_refs = [r for n in dict.fromkeys(item_names) for r in refs_for(n, binary)]
                all_refs += [(r, item["id"]) for r in item_refs]
                items.append(_string_out(item, ctx, symbols, item_refs))
            rec["count"] = len(items)
            rec["entries" if block["kind"] == "entries" else "strings"] = items
            records.append(rec)
        out.check(f"{model.src.path}: every block is placed in {owner}", not unplaced,
                  f"not placed: {unplaced}" if unplaced else f"{len(records)} blocks")

        used_by = {}
        for ref, sid in all_refs:
            key = (ref["file"], ref["in"], ref["kind"])
            entry = used_by.setdefault(key, {"file": ref["file"], "in": ref["in"], "kind": ref["kind"],
                                             "lines": set(), "names": set()})
            entry["lines"].add(ref["line"])
            if sid:
                entry["names"].add(sid)
        used_by = [dict(v, lines=sorted(v["lines"]), names=sorted(v["names"]))
                   for _, v in sorted(used_by.items(), key=lambda kv: (kv[0][0], min(kv[1]["lines"])))]

        table_name = _table_name(model.src.path)
        table = {
            "table": {"name": f"text/{table_name}", "purpose": FILE_PURPOSES.get(table_name, "")},
            "source": {"files": [model.src.identity()], "c_file": owner, "header": header, "binary": binary,
                       "releases": {r: {"language": ctx.language_of[r], "region": rel.region, "date": rel.date}
                                    for r, rel in ctx.releases.items()},
                       "main_release": ctx.main_release, "fallback": FALLBACK},
            "schema": SCHEMA,
            "records": records,
            "used_by": used_by,
            "godot": {
                "status": "planned (GameData autoload not implemented yet)",
                "access": "GameData.text(id, language) for named strings; "
                          "GameData.text_entry(\"" + table_name + "\", block, index) for entries arrays",
                "languages": {lang: ctx.main_release[lang] for lang in ctx.languages},
                "notes": "Text is kept as written: control codes (#C1/#R/#W in en_us, {C1}-style in en_eu, bare "
                         "C/R/W in ja) and button / full-width glyphs are for the Godot text renderer to "
                         "interpret (specs/text.md).",
            },
        }
        out.write_table(table_name, table, symbols=[b["block"] for b in model.blocks])

    counts = {"files": len(models), "blocks": sum(len(m.blocks) for m in models),
              "strings": sum(len(b["items"]) for m in models for b in m.blocks)}
    codes = _control_codes(models)
    out.write_report("report.md", _report(models, ctx, codes))
    out.finish(sources, extra={"counts": counts, "control_codes": codes, "excluded": EXCLUDED})
    return out
