"""Asset families: one converter per kind of game data, each following specs/<name>.md."""

from . import alltim, card_all, etctim, stdtim, tim_files

FAMILIES = {
    card_all.NAME: card_all,
    alltim.NAME: alltim,
    etctim.NAME: etctim,
    stdtim.NAME: stdtim,
    tim_files.NAME: tim_files,
}
