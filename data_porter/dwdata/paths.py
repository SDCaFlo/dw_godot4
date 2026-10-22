"""Default locations, relative to the data_porter folder."""

from pathlib import Path

PORTER_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = PORTER_ROOT.parent.parent

DEFAULT_INPUT = PROJECT_ROOT / "external-resources" / "dw_decomp"
DEFAULT_OUTPUT = PORTER_ROOT / "output"
SPECS_DIR = PORTER_ROOT / "specs"
