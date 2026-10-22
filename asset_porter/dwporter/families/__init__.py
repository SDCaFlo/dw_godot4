"""Asset families: one converter per kind of game data, each following specs/<name>.md."""

from . import alltim, card_all

FAMILIES = {
    card_all.NAME: card_all,
    alltim.NAME: alltim,
}
