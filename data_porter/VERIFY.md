# Verifying the data porter output (human checks)

The converter runs its own checks on every run (`python -m dwdata convert all`: every group must end with `N/N checks passed`) and `python -m unittest discover -s tests -t .` must pass. Those prove the values were parsed and linked correctly. What they cannot prove is that they *mean* what the spec says; that is what these checks are for. Compare with what you know of the game, a wiki, or the game itself.

Sections are added as groups are converted (see `PROGRESS.md`).

## General checks for any table

- Open the table's JSON: field names are readable, references show names next to ids (`"moves": [{"id": 46, "name": "Spit Fire"}]`), nothing looks like garbage (huge numbers, negative counts, names in the wrong place).
- Pick 2–3 records you know (e.g. Agumon, Spit Fire, Meat) and compare them with the game.
- Open `output/catalog.json`: every table has a purpose line and a spec.

## Reporting a problem

Note the table, the record id and what you expected vs. saw. The table's `source` says which decomp file and line the value came from.
