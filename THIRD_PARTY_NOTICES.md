# Third-party notices

## References (not included in this repository)

- **dw_decomp**, the decompilation of the US release of Digimon World: https://github.com/SydMontague/dw_decomp (fork of https://github.com/jype0/dw_decomp), MIT licence. The port reproduces its logic in GDScript and Python; the data porter's committed snapshot (`data_porter/dwdata/snapshot/us.json`) records the layout of its tables and about 200 constants taken from its code. Copyright (c) its contributors.
- **DW1ModelConverter** by SydMontague, MIT licence (Copyright (c) 2023 SydMontague): its model and map converter was read as a reference and its output used to cross-check the asset porter.
- **PSXPrev**, BSD 2-Clause licence (Copyright (c) 2023, PSXPrev Contributors): read as a reference for the TIM / TMD formats.

## Bundled in the release builds

- **Godot Engine**, MIT licence (Copyright (c) 2014-present Godot Engine contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur), with its third-party components: https://godotengine.org/license
- **Python**, PSF License Agreement: `tools/dw_convert/_internal/` holds the Python runtime of `dw_convert.exe`. https://docs.python.org/3/license.html
- **PyInstaller** bootloader, GPL 2.0 with the bootloader exception (programs built with it may use any licence). https://pyinstaller.org/en/stable/license.html
