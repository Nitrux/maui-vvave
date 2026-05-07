#include "vvave.h"

#include "services/local/taginfo.h"

#include <MauiKit4/FileBrowsing/fmstatic.h>
#include <MauiKit4/FileBrowsing/tagging.h>

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QSet>
#include <QSettings>
#include <QTimer>
#include <algorithm>
#include <limits>

#include "utils/bae.h"

Q_GLOBAL_STATIC(vvave, vvaveInstance)

namespace
{
FMH::MODEL_LIST s_cachedTracks;
bool s_trackCacheValid = false;

void invalidateTrackCache()
{
    s_trackCacheValid = false;
    s_cachedTracks.clear();
}

bool isAudioFile(const QString &path)
{
    static const QSet<QString> kAudioSuffixes = {
        QStringLiteral("mp3"), QStringLiteral("flac"), QStringLiteral("ogg"), QStringLiteral("oga"), QStringLiteral("opus"),
        QStringLiteral("wav"), QStringLiteral("m4a"), QStringLiteral("aac"), QStringLiteral("wma"), QStringLiteral("aiff"),
        QStringLiteral("ape"), QStringLiteral("alac"), QStringLiteral("mp2"), QStringLiteral("mp1")};

    const QFileInfo info(path);
    return info.exists() && info.isFile() && kAudioSuffixes.contains(info.suffix().toLower());
}

int trackNumberForSort(const FMH::MODEL &track)
{
    bool ok = false;
    const int value = track.value(FMH::MODEL_KEY::TRACK).toInt(&ok);
    return (ok && value > 0) ? value : std::numeric_limits<int>::max();
}
}

FMH::MODEL vvave::trackInfo(const QUrl &url)
{
    const QFileInfo fileInfo(url.toLocalFile());
    if (!fileInfo.exists() || !fileInfo.isFile()) {
        return FMH::MODEL();
    }

    TagInfo info(fileInfo.absoluteFilePath());

    int track = 0;
    QString genre = BAE::SLANG[BAE::W::UNKNOWN];
    QString album = BAE::SLANG[BAE::W::UNKNOWN];
    QString title = fileInfo.completeBaseName();
    QString artist = BAE::SLANG[BAE::W::UNKNOWN];
    int duration = 0;
    uint year = 0;
    QString comment = BAE::SLANG[BAE::W::UNKNOWN];

    // If TagLib cannot parse a file, still expose it in the library
    // using filename-based fallback metadata.
    if (!info.isNull()) {
        track = info.getTrack();
        genre = info.getGenre();
        album = info.getAlbum();
        title = info.getTitle();
        artist = info.getArtist();
        duration = info.getDuration();
        year = info.getYear();
        comment = info.getComment();
    }

    const auto sourceUrl = FMStatic::parentDir(url).toString();

    return FMH::MODEL{{FMH::MODEL_KEY::URL, url.toString()},
                      {FMH::MODEL_KEY::TRACK, QString::number(track)},
                      {FMH::MODEL_KEY::TITLE, title},
                      {FMH::MODEL_KEY::ARTIST, artist},
                      {FMH::MODEL_KEY::ALBUM, album},
                      {FMH::MODEL_KEY::COMMENT, comment},
                      {FMH::MODEL_KEY::DURATION, QString::number(duration)},
                      {FMH::MODEL_KEY::GENRE, genre},
                      {FMH::MODEL_KEY::SOURCE, sourceUrl},
                      {FMH::MODEL_KEY::RELEASEDATE, QString::number(year)}};
}

FMH::MODEL_LIST vvave::localTracks()
{
    if (s_trackCacheValid) {
        return s_cachedTracks;
    }

    FMH::MODEL_LIST tracks;
    QSet<QString> seenUrls;

    for (const auto &source : QUrl::fromStringList(vvave::sources())) {
        if (!source.isLocalFile()) {
            continue;
        }

        const auto sourcePath = source.toLocalFile();
        QFileInfo sourceInfo(sourcePath);

        if (!sourceInfo.exists()) {
            continue;
        }

        if (sourceInfo.isFile()) {
            const auto normalizedUrl = QUrl::fromLocalFile(sourceInfo.absoluteFilePath()).toString();
            if (!isAudioFile(sourceInfo.absoluteFilePath()) || seenUrls.contains(normalizedUrl)) {
                continue;
            }

            seenUrls.insert(normalizedUrl);
            auto model = vvave::trackInfo(QUrl::fromLocalFile(sourceInfo.absoluteFilePath()));
            if (!model.isEmpty()) {
                tracks << model;
            }
            continue;
        }

        QDirIterator it(sourcePath, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const auto filePath = it.next();
            if (!isAudioFile(filePath)) {
                continue;
            }

            const auto fileUrl = QUrl::fromLocalFile(filePath).toString();
            if (seenUrls.contains(fileUrl)) {
                continue;
            }

            seenUrls.insert(fileUrl);
            auto model = vvave::trackInfo(QUrl::fromLocalFile(filePath));
            if (!model.isEmpty()) {
                tracks << model;
            }
        }
    }

    s_cachedTracks = tracks;
    s_trackCacheValid = true;
    return s_cachedTracks;
}

FMH::MODEL_LIST vvave::tracksForTag(const QString &tag)
{
    FMH::MODEL_LIST tracks;
    if (tag.isEmpty()) {
        return tracks;
    }

    const auto urls = Tagging::getInstance()->getTagUrls(tag, {}, true, 99999, "audio");
    for (const auto &url : urls) {
        if (!url.isLocalFile() || !isAudioFile(url.toLocalFile())) {
            continue;
        }

        auto model = vvave::trackInfo(url);
        if (!model.isEmpty()) {
            tracks << model;
        }
    }

    return tracks;
}

FMH::MODEL_LIST vvave::tracksFromQuery(const QString &query)
{
    if (query.startsWith(QLatin1Char('#'))) {
        auto tag = query;
        tag.remove(0, 1);
        return tracksForTag(tag);
    }

    if (query == QStringLiteral("vvave://all") || query.isEmpty()) {
        return localTracks();
    }

    if (query.startsWith(QStringLiteral("vvave://artist/"))) {
        const auto encodedArtist = query.mid(QStringLiteral("vvave://artist/").size());
        const auto artist = QUrl::fromPercentEncoding(encodedArtist.toUtf8());

        FMH::MODEL_LIST filtered;
        for (const auto &track : localTracks()) {
            if (track[FMH::MODEL_KEY::ARTIST].compare(artist, Qt::CaseInsensitive) == 0) {
                filtered << track;
            }
        }

        return filtered;
    }

    if (query.startsWith(QStringLiteral("vvave://album/"))) {
        const auto payload = query.mid(QStringLiteral("vvave://album/").size());
        const auto parts = payload.split(QLatin1Char('/'));

        if (parts.size() >= 2) {
            const auto album = QUrl::fromPercentEncoding(parts.at(0).toUtf8());
            const auto artist = QUrl::fromPercentEncoding(parts.at(1).toUtf8());

            FMH::MODEL_LIST filtered;
            for (const auto &track : localTracks()) {
                if (track[FMH::MODEL_KEY::ALBUM].compare(album, Qt::CaseInsensitive) == 0
                    && track[FMH::MODEL_KEY::ARTIST].compare(artist, Qt::CaseInsensitive) == 0) {
                    filtered << track;
                }
            }

            std::stable_sort(filtered.begin(), filtered.end(), [](const FMH::MODEL &a, const FMH::MODEL &b) {
                const int trackA = trackNumberForSort(a);
                const int trackB = trackNumberForSort(b);

                if (trackA != trackB) {
                    return trackA < trackB;
                }

                const QString titleA = a.value(FMH::MODEL_KEY::TITLE);
                const QString titleB = b.value(FMH::MODEL_KEY::TITLE);
                const int titleCompare = QString::localeAwareCompare(titleA, titleB);
                if (titleCompare != 0) {
                    return titleCompare < 0;
                }

                return QString::localeAwareCompare(a.value(FMH::MODEL_KEY::URL), b.value(FMH::MODEL_KEY::URL)) < 0;
            });

            return filtered;
        }
    }

    // Backward compatibility fallback for older query strings.
    return localTracks();
}

QString vvave::artworkUrl(const QString &artist, const QString &album)
{
    FMH::MODEL data = {{FMH::MODEL_KEY::ARTIST, artist}, {FMH::MODEL_KEY::ALBUM, album}};
    if (BAE::artworkCache(data, FMH::MODEL_KEY::ALBUM)) {
        return QUrl(data[FMH::MODEL_KEY::ARTWORK]).toLocalFile();
    }

    return QString();
}

QVariantList vvave::getTracks(const QString &query)
{
    return FMH::toMapList(vvave::tracksFromQuery(query));
}

vvave *vvave::instance()
{
    return vvaveInstance();
}

vvave::vvave(QObject *parent)
    : QObject(parent)
{
    qRegisterMetaType<QList<QUrl> *>("QList<QUrl>&");

    QDir dirPath(BAE::CachePath.toLocalFile());
    if (!dirPath.exists()) {
        dirPath.mkpath(".");
    }
}

void vvave::setFetchArtwork(bool fetchArtwork)
{
    if (m_fetchArtwork == fetchArtwork) {
        return;
    }

    m_fetchArtwork = fetchArtwork;
    Q_EMIT fetchArtworkChanged(m_fetchArtwork);
}

bool vvave::fetchArtwork() const
{
    return m_fetchArtwork;
}

void vvave::addSources(const QList<QUrl> &paths)
{
    auto urls = QUrl::fromStringList(sources());
    QList<QUrl> newUrls;

    for (const auto &path : paths) {
        if (!urls.contains(path)) {
            newUrls << path;
            Q_EMIT sourceAdded(path);
        }
    }

    if (newUrls.isEmpty()) {
        return;
    }

    urls << newUrls;

    QSettings settings;
    settings.beginGroup("SETTINGS");
    settings.setValue("SOURCES", QVariant::fromValue(QUrl::toStringList(urls)));
    settings.endGroup();

    invalidateTrackCache();
    scanDir(urls);
    Q_EMIT sourcesChanged();
}

bool vvave::removeSource(const QString &source)
{
    auto urls = this->sources();
    if (!urls.contains(source)) {
        return false;
    }

    urls.removeOne(source);

    QSettings settings;
    settings.beginGroup("SETTINGS");
    settings.setValue("SOURCES", QVariant::fromValue(urls));
    settings.endGroup();

    invalidateTrackCache();
    Q_EMIT this->sourceRemoved(QUrl(source));
    Q_EMIT sourcesChanged();
    return true;
}

void vvave::scanDir(const QList<QUrl> &paths)
{
    Q_UNUSED(paths)
    invalidateTrackCache();

    m_scanning = true;
    Q_EMIT scanningChanged(m_scanning);

    QTimer::singleShot(0, this, [this]() {
        m_scanning = false;
        Q_EMIT scanningChanged(m_scanning);
    });
}

void vvave::rescan()
{
    scanDir(QUrl::fromStringList(sources()));
}

QStringList vvave::sources()
{
    QSettings settings;
    settings.beginGroup("SETTINGS");
    auto data = settings.value("SOURCES").toStringList();
    settings.endGroup();

    if (data.isEmpty()) {
        data << FMStatic::MusicPath;
    }

    return data;
}

QVariantList vvave::sourcesModel()
{
    QVariantList res;
    const auto urls = QUrl::fromStringList(sources());
    for (const auto &url : urls) {
        if (FMStatic::fileExists(url)) {
            res << FMStatic::getFileInfo(url);
        }
    }

    return res;
}

QList<QUrl> vvave::folders()
{
    return QUrl::fromStringList(sources());
}

bool vvave::scanning() const
{
    return m_scanning;
}
