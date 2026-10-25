"""Asset families: one converter per kind of game data, each following specs/<name>.md."""

from . import alltim, atr_files, card_all, efe, etctim, maps, mmd_files, mmm_dat, movies, music, scripts, sound, stdtim, tim_files, tmd_files

FAMILIES = {
    card_all.NAME: card_all,
    alltim.NAME: alltim,
    etctim.NAME: etctim,
    stdtim.NAME: stdtim,
    tim_files.NAME: tim_files,
    tmd_files.NAME: tmd_files,
    mmd_files.NAME: mmd_files,
    maps.NAME: maps,
    atr_files.NAME: atr_files,
    scripts.NAME: scripts,
    sound.NAME: sound,
    music.NAME: music,
    mmm_dat.NAME: mmm_dat,
    efe.NAME: efe,
    movies.NAME: movies,
}
