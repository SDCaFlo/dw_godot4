"""Data groups: one converter per kind of game data, each following specs/<name>.md."""

from . import digimon, items, moves, text

GROUPS = {
    text.NAME: text,
    moves.NAME: moves,
    digimon.NAME: digimon,
    items.NAME: items,
}
