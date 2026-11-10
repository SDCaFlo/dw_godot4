"""Builds dw_convert.exe (distribution step D5): python build_exe.py   (run from the dw_convert folder)

A one-folder PyInstaller build (dist/dw_convert/: the exe and its _internal/ folder; quicker to start than
one-file builds and less often flagged by antivirus tools) of dw_convert.py with the two porters and the
committed data they need (us_files.json, the data porter's snapshot). PyInstaller runs from its own
environment in .build/ (gitignored), created on the first run; the porters stay standard library only.
"""

import os
import subprocess
import sys
import venv
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BUILD = HERE / ".build"
PYINSTALLER = "pyinstaller==6.11.1"
SEP = ";" if os.name == "nt" else ":"


def build_python() -> Path:
    py = BUILD / "venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if not py.is_file():
        print(f"creating {BUILD / 'venv'} with {PYINSTALLER}")
        venv.create(BUILD / "venv", with_pip=True)
        subprocess.check_call([str(py), "-m", "pip", "install", "--quiet", PYINSTALLER])
    return py


def main() -> int:
    py = build_python()
    data = [
        (HERE / "dwconvert" / "us_files.json", "dwconvert"),
        (ROOT / "data_porter" / "dwdata" / "snapshot" / "us.json", "dwdata/snapshot"),
    ]
    cmd = [str(py), "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--console",
           "--name", "dw_convert",
           "--distpath", str(HERE / "dist"), "--workpath", str(BUILD / "work"), "--specpath", str(BUILD),
           "--paths", str(HERE), "--paths", str(ROOT / "asset_porter"), "--paths", str(ROOT / "data_porter"),
           # every family and group (imported through their registries)
           "--collect-submodules", "dwporter", "--collect-submodules", "dwdata",
           # optional speed-ups the release doesn't need (the movies are skipped)
           "--exclude-module", "numpy", "--exclude-module", "PIL", "--exclude-module", "tkinter"]
    for src, dest in data:
        cmd += ["--add-data", f"{src}{SEP}{dest}"]
    cmd.append(str(HERE / "dw_convert.py"))
    print(" ".join(cmd))
    subprocess.check_call(cmd, cwd=HERE)
    exe = HERE / "dist" / "dw_convert" / ("dw_convert.exe" if os.name == "nt" else "dw_convert")
    print(f"built {exe}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
