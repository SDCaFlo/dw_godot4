"""Entry point of the bundled dw_convert.exe (build_exe.py): python -m dwconvert's commands."""

import multiprocessing
import sys

from dwconvert.__main__ import main

if __name__ == "__main__":
    # The asset porter's music family renders tracks in a process pool; in a frozen exe each worker starts
    # this exe again, and freeze_support() makes it run the worker instead of the command line.
    multiprocessing.freeze_support()
    sys.exit(main())
