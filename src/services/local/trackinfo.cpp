#include "trackinfo.h"

TrackInfo::TrackInfo(QObject *parent) : QObject(parent)
{
    connect(this, &TrackInfo::trackChanged, this, &TrackInfo::getInfo);
}

QString TrackInfo::albumWiki() const
{
    return m_albumWiki;
}

QString TrackInfo::artistWiki() const
{
    return m_artistWiki;
}

QString TrackInfo::trackWiki() const
{
    return m_trackWiki;
}

QString TrackInfo::lyrics() const
{
    return m_lyrics;
}

QVariantMap TrackInfo::track() const
{
    return m_track;
}

void TrackInfo::setTrack(QVariantMap track)
{
    if (m_track == track)
        return;

    m_track = track;
    Q_EMIT trackChanged(m_track);
}

void TrackInfo::getInfo()
{
    if (m_track.isEmpty())
        return;

    const auto artist = m_track.value("artist").toString();
    const auto album = m_track.value("album").toString();
    const auto title = m_track.value("title").toString();

    const bool artistChanged = artist != m_artist;
    const bool albumChanged = album != m_album;
    const bool titleChanged = title != m_title;

    m_artist = artist;
    m_album = album;
    m_title = title;

    // VVave scope is local playback and web artwork only; avoid extra web metadata requests.
    if (artistChanged) {
        m_artistWiki.clear();
        Q_EMIT this->artistWikiChanged(m_artistWiki);
    }

    if (albumChanged) {
        m_albumWiki.clear();
        Q_EMIT this->albumWikiChanged(m_albumWiki);
    }

    if (titleChanged) {
        m_lyrics.clear();
        Q_EMIT this->lyricsChanged(m_lyrics);
    }
}

void TrackInfo::getAlbumInfo()
{
    m_albumWiki.clear();
    Q_EMIT this->albumWikiChanged(m_albumWiki);
}

void TrackInfo::getArtistInfo()
{
    m_artistWiki.clear();
    Q_EMIT this->artistWikiChanged(m_artistWiki);
}

void TrackInfo::getTrackInfo()
{
    m_lyrics.clear();
    Q_EMIT this->lyricsChanged(m_lyrics);
}
