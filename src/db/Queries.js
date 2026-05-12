var GET = {
    // Lightweight non-SQL query tokens interpreted by vvave::tracksFromQuery().
    allTracks: "vvave://all",
    albumTracks_: "vvave://album/%1/%2",
    artistTracks_: "vvave://artist/%1",
    playlistTracks_: "#%1",

    // Backward-compat aliases used by some views/components.
    mostPlayedTracks: "vvave://all",
    favoriteTracks: "vvave://all",
    newTracks: "vvave://all",
    randomTracks: "vvave://all",
    randomTracks_: "vvave://all",
    oldTracks: "vvave://all",
    recentTracks: "vvave://all",
    recentTracks_: "vvave://all",
    recentArtists: "vvave://all",
    recentAlbums: "vvave://all",
    neverPlayedTracks: "vvave://all",
    neverPlayedTracks_: "vvave://all"
}

var INSERT = {}
var UPDATE = {}
