"""Data groups: one converter per kind of game data, each following specs/<name>.md."""

from . import digimon, evolution, font, items, moves, systems, text

GROUPS = {
    text.NAME: text,
    font.NAME: font,
    moves.NAME: moves,
    digimon.NAME: digimon,
    items.NAME: items,
    evolution.NAME: evolution,
    systems.NAME: systems,
}
