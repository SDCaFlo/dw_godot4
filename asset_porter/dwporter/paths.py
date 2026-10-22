"""Default locations, relative to the asset_porter folder."""

from pathlib import Path

PORTER_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = PORTER_ROOT.parent.parent

DEFAULT_INPUT = PROJECT_ROOT / "external-resources" / "game_dumped_files"
DEFAULT_OUTPUT = PORTER_ROOT / "output"
SPECS_DIR = PORTER_ROOT / "specs"

SECTOR_SIZE = 0x800
