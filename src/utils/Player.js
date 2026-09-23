.import org.mauikit.filebrowsing as FB

.import org.maui.vvave as Vvave

function playlistPage()
{
    return root && root.mainPlaylist ? root.mainPlaylist : null
}

function playlistView()
{
    const page = playlistPage()
    return page && page.listView ? page.listView : null
}

function playlistCount()
{
    const page = playlistPage()
    const list = page && page.listModel ? page.listModel.list : null
    return list && list.count !== undefined ? Math.max(0, Number(list.count) || 0) : 0
}

function positionPlaylistAtEnd()
{
    const view = playlistView()
    if (view && view.positionViewAtEnd)
        view.positionViewAtEnd()
}

function positionPlaylistAtBeginning()
{
    const view = playlistView()
    if (view && view.positionViewAtBeginning)
        view.positionViewAtBeginning()
}

function playTrack()
{
    const nextSource = currentTrack && currentTrack.url ? currentTrack.url : ""
    const previousSource = player.source ? player.source : ""
    const switchingSource = String(previousSource) !== String(nextSource)

    if (!nextSource) {
        player.stop()
        return
    }

    // MediaPlayer::play() resumes paused playback without reloading source.
    // Stop first when changing tracks so the new source is always played.
    if (switchingSource)
        player.stop()

    player.source = nextSource
    player.play()
}

function queueTracks(tracks)
{
    if(tracks && tracks.length > 0)
    {
        const wasEmpty = playlistCount() === 0
        appendTracksAt(tracks, currentTrackIndex+1)

        if (wasEmpty && playlistCount() > 0)
        {
            positionPlaylistAtBeginning()
            playAt(0)
        }
        // root.notify("", "Queue", tracks.length + " tracks added put on queue")
        // This freezes the whole UI. It should probably be a toast popup instead.
        // Something similar AbstractApplicationWindow::showPassiveNotification() from Kirigami would be less flow-breaking.
    }
}

function setLyrics(lyrics)
{
    currentTrack.lyrics = lyrics
    infoView.lyricsText.text = lyrics
}

function stop()
{
    player.stop()
}

function changeCurrentIndex(index)
{
    root.playlistManager.changeCurrentIndex(index)
}

function nextTrack()
{
    root.playlistManager.next()
}

function previousTrack()
{
    root.playlistManager.previous()
}

function playAt(index)
{
    root.playlistManager.play(index)
}

function quickPlay(track)
{
    //    root.pageStack.currentIndex = 0
    appendTrack(track)
    const index = playlistCount() - 1
    if (index >= 0)
        playAt(index)
    positionPlaylistAtEnd()
}

function appendTracksAt(tracks, at)
{
    for(var i in tracks)
    {
        mainPlaylist.listModel.list.appendAt(tracks[i], parseInt(at)+parseInt(i))
    }
}

function appendUrls(urls)
{
    mainPlaylist.listModel.list.appendUrls(urls)
}

function appendUrlsAt(urls, at)
{
    mainPlaylist.listModel.list.insertUrls(urls, at)
}

function appendTrack(track)
{
    if(track)
    {
        root.playlistManager.append(track)
        if(sync === true)
        {
            FB.Tagging.tagUrl(track.url, syncPlaylist)
        }
    }
}

function addTrack(track)
{
    if(track)
    {
        appendTrack(track)
        positionPlaylistAtEnd()
    }
}

function appendAll(tracks)
{
    for(var track of tracks)
        appendTrack(track)

    positionPlaylistAtEnd()

    if (tracks.length > 1 && root.playlistManager.playMode === Vvave.Playlist.Shuffle)
    {
        root.playlistManager.shuffleRange(
            playlistCount() - tracks.length,
            playlistCount())
    }
}

function playAll(tracks)
{
    sync = false
    syncPlaylist = ""

    player.stop()
    root.playlistManager.clear()
    appendAll(tracks)

    if (!tracks || tracks.length === 0)
        return

    positionPlaylistAtBeginning()
    playAt(0)
}

function appendAllModel(model)
{
    mainPlaylist.listModel.list.copy(model)
    positionPlaylistAtEnd()

    if (model.count > 1 && root.playlistManager.playMode === Vvave.Playlist.Shuffle)
    {
        root.playlistManager.shuffleRange(
            playlistCount() - model.count,
            playlistCount())
    }
}

function playQuery(query)
{
    const tracks = Vvave.Vvave.getTracks(query)
    playAll(tracks)
}

function playAllModel(model)
{
    sync = false
    syncPlaylist = ""

    player.stop()
    root.playlistManager.clear()
    appendAllModel(model)

    if (!model || model.count === 0)
        return

    positionPlaylistAtBeginning()
    playAt(0)
}

function shuffleAllModel(model)
{
    sync = false
    syncPlaylist = ""

    player.stop()
    root.playlistManager.clear()
    appendAllModel(model)

    if (!model || model.count === 0)
        return

    positionPlaylistAtBeginning()
    root.playlistManager.playMode = Vvave.Playlist.Shuffle
    playAt(0)
}
