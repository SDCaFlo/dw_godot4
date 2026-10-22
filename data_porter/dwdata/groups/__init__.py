"""Data groups: one converter per kind of game data, each following specs/<name>.md."""

from . import text

GROUPS = {
    text.NAME: text,
}
