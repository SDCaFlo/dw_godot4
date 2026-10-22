"""Asset families: one converter per kind of game data, each following specs/<name>.md."""

from . import alltim, card_all, etctim, maps, mmd_files, stdtim, tim_files, tmd_files

FAMILIES = {
    card_all.NAME: card_all,
    alltim.NAME: alltim,
    etctim.NAME: etctim,
    stdtim.NAME: stdtim,
    tim_files.NAME: tim_files,
    tmd_files.NAME: tmd_files,
    mmd_files.NAME: mmd_files,
    maps.NAME: maps,
}
