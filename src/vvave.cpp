#include "vvave.h"

#include "services/local/taginfo.h"

#include <MauiKit4/FileBrowsing/fmstatic.h>
#include <MauiKit4/FileBrowsing/tagging.h>

#include <QDir>
#include <QDirIterator>
#include <QColor>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QSet>
#include <QSettings>
#include <QTimer>
#include <array>
#include <algorithm>
#include <limits>

#include "utils/bae.h"

Q_GLOBAL_STATIC(vvave, vvaveInstance)

namespace
{
FMH::MODEL_LIST s_cachedTracks;
FMH::MODEL_LIST s_cachedAlbums;
FMH::MODEL_LIST s_cachedArtists;
QHash<QString, QList<int>> s_artistTrackRows;
QHash<QString, QList<int>> s_albumTrackRows;
QHash<QString, int> s_trackRowByUrl;
bool s_trackCacheValid = false;
bool s_collectionIndexesValid = false;

const QSet<QString> &audioSuffixes()
{
    static const QSet<QString> kAudioSuffixes = {
        QStringLiteral("mp3"), QStringLiteral("flac"), QStringLiteral("ogg"), QStringLiteral("oga"), QStringLiteral("opus"),
        QStringLiteral("wav"), QStringLiteral("m4a"), QStringLiteral("aac"), QStringLiteral("wma"), QStringLiteral("aiff"),
        QStringLiteral("ape"), QStringLiteral("alac"), QStringLiteral("mp2"), QStringLiteral("mp1")};

    return kAudioSuffixes;
}

QString normalizeLookupValue(const QString &value)
{
    return value.trimmed().toCaseFolded();
}

QString artistLookupKey(const QString &artist)
{
    return normalizeLookupValue(artist);
}

QString albumLookupKey(const QString &album, const QString &artist)
{
    return normalizeLookupValue(album) + QStringLiteral("\x1f") + normalizeLookupValue(artist);
}

void invalidateTrackCache()
{
    s_trackCacheValid = false;
    s_collectionIndexesValid = false;
    s_cachedTracks.clear();
    s_cachedAlbums.clear();
    s_cachedArtists.clear();
    s_artistTrackRows.clear();
    s_albumTrackRows.clear();
    s_trackRowByUrl.clear();
}

bool hasAudioSuffix(const QString &suffix)
{
    return audioSuffixes().contains(suffix.toLower());
}

bool isAudioFile(const QString &path)
{
    const QFileInfo info(path);
    return info.exists() && info.isFile() && hasAudioSuffix(info.suffix());
}

int trackNumberForSort(const FMH::MODEL &track)
{
    bool ok = false;
    const int value = track.value(FMH::MODEL_KEY::TRACK).toInt(&ok);
    return (ok && value > 0) ? value : std::numeric_limits<int>::max();
}

bool trackListSortLess(const FMH::MODEL &a, const FMH::MODEL &b)
{
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
}

FMH::MODEL_LIST tracksForRows(const QList<int> &rows)
{
    FMH::MODEL_LIST tracks;
    tracks.reserve(rows.size());

    for (const auto row : rows) {
        if (row >= 0 && row < s_cachedTracks.size()) {
            tracks << s_cachedTracks.at(row);
        }
    }

    return tracks;
}

void ensureCollectionIndexes()
{
    if (s_collectionIndexesValid) {
        return;
    }

    if (!s_trackCacheValid) {
        return;
    }

    QSet<QString> seenArtists;
    QSet<QString> seenAlbums;

    for (int i = 0; i < s_cachedTracks.size(); ++i) {
        const auto &track = s_cachedTracks.at(i);
        const auto artist = track[FMH::MODEL_KEY::ARTIST];
        const auto album = track[FMH::MODEL_KEY::ALBUM];
        const auto url = track[FMH::MODEL_KEY::URL];

        if (!url.isEmpty()) {
            s_trackRowByUrl.insert(url, i);
        }

        const auto normalizedArtist = artistLookupKey(artist);
        if (!normalizedArtist.isEmpty()) {
            s_artistTrackRows[normalizedArtist] << i;

            if (!seenArtists.contains(normalizedArtist)) {
                seenArtists.insert(normalizedArtist);
                s_cachedArtists << FMH::MODEL{{FMH::MODEL_KEY::ARTIST, artist}};
            }
        }

        const auto normalizedAlbum = albumLookupKey(album, artist);
        if (!album.isEmpty() && !normalizedArtist.isEmpty()) {
            s_albumTrackRows[normalizedAlbum] << i;

            if (!seenAlbums.contains(normalizedAlbum)) {
                seenAlbums.insert(normalizedAlbum);
                s_cachedAlbums << FMH::MODEL{{FMH::MODEL_KEY::ALBUM, album}, {FMH::MODEL_KEY::ARTIST, artist}};
            }
        }
    }

    for (auto it = s_albumTrackRows.begin(); it != s_albumTrackRows.end(); ++it) {
        auto &rows = it.value();
        std::stable_sort(rows.begin(), rows.end(), [](int left, int right) {
            return trackListSortLess(s_cachedTracks.at(left), s_cachedTracks.at(right));
        });
    }

    std::sort(s_cachedAlbums.begin(), s_cachedAlbums.end(), [](const FMH::MODEL &a, const FMH::MODEL &b) {
        const int albumCompare = a[FMH::MODEL_KEY::ALBUM].compare(b[FMH::MODEL_KEY::ALBUM], Qt::CaseInsensitive);
        if (albumCompare != 0) {
            return albumCompare < 0;
        }

        return a[FMH::MODEL_KEY::ARTIST].compare(b[FMH::MODEL_KEY::ARTIST], Qt::CaseInsensitive) < 0;
    });

    std::sort(s_cachedArtists.begin(), s_cachedArtists.end(), [](const FMH::MODEL &a, const FMH::MODEL &b) {
        return a[FMH::MODEL_KEY::ARTIST].compare(b[FMH::MODEL_KEY::ARTIST], Qt::CaseInsensitive) < 0;
    });

    s_collectionIndexesValid = true;
}

QColor clampAccentColor(const QColor &color)
{
    QColor hslColor = color.toHsl();

    qreal hue = hslColor.hslHueF();
    if (hue < 0.0) {
        hue = 0.55;
    }

    const qreal saturation = std::clamp<qreal>(qreal(hslColor.hslSaturationF()), qreal(0.35), qreal(0.95));
    const qreal lightness = std::clamp<qreal>(qreal(hslColor.lightnessF()), qreal(0.35), qreal(0.62));

    QColor result;
    result.setHslF(hue, saturation, lightness, 1.0);
    return result;
}

QColor fallbackAccentColor()
{
    return QColor(QStringLiteral("#f84172"));
}

QColor accentFromArtwork(const QImage &sourceImage)
{
    if (sourceImage.isNull()) {
        return fallbackAccentColor();
    }

    const QImage image = sourceImage.convertToFormat(QImage::Format_ARGB32)
                             .scaled(96, 96, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);

    if (image.isNull()) {
        return fallbackAccentColor();
    }

    struct Bucket
    {
        double weight = 0.0;
        double red = 0.0;
        double green = 0.0;
        double blue = 0.0;
        double saturation = 0.0;
        double lightness = 0.0;
    };

    constexpr int hueBuckets = 24;
    constexpr int saturationBuckets = 6;
    constexpr int lightnessBuckets = 6;
    constexpr int bucketCount = hueBuckets * saturationBuckets * lightnessBuckets;

    std::array<Bucket, bucketCount> buckets;

    auto bucketIndexFor = [=](const QColor &color) {
        int hue = color.hslHue();
        if (hue < 0) {
            hue = 0;
        }

        const int hueIndex = std::clamp(hue / 15, 0, hueBuckets - 1);
        const int saturationIndex = std::clamp(int(color.hslSaturationF() * saturationBuckets), 0, saturationBuckets - 1);
        const int lightnessIndex = std::clamp(int(color.lightnessF() * lightnessBuckets), 0, lightnessBuckets - 1);

        return hueIndex + (saturationIndex * hueBuckets) + (lightnessIndex * hueBuckets * saturationBuckets);
    };

    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            const QColor color = image.pixelColor(x, y).toHsl();
            if (color.alpha() < 24) {
                continue;
            }

            const double saturation = color.hslSaturationF();
            const double lightness = color.lightnessF();

            if (lightness <= 0.02 || lightness >= 0.98) {
                continue;
            }

            if (saturation < 0.06 && (lightness <= 0.18 || lightness >= 0.82)) {
                continue;
            }

            const double vividness = std::clamp((saturation - 0.08) / 0.92, 0.0, 1.0);
            const double midtoneBalance = 1.0 - std::min(1.0, std::abs(lightness - 0.52) / 0.52);
            const double weight = 0.12 + (vividness * vividness * 0.7) + (midtoneBalance * 0.18);

            auto &bucket = buckets[bucketIndexFor(color)];
            bucket.weight += weight;
            bucket.red += color.redF() * weight;
            bucket.green += color.greenF() * weight;
            bucket.blue += color.blueF() * weight;
            bucket.saturation += saturation * weight;
            bucket.lightness += lightness * weight;
        }
    }

    double bestScore = 0.0;
    QColor bestColor;

    for (const auto &bucket : buckets) {
        if (bucket.weight <= 0.0) {
            continue;
        }

        const double avgSaturation = bucket.saturation / bucket.weight;
        const double avgLightness = bucket.lightness / bucket.weight;

        if (avgSaturation < 0.12) {
            continue;
        }

        const double score = bucket.weight * (0.4 + (avgSaturation * 0.9)) * (1.0 - std::min(0.85, std::abs(avgLightness - 0.5)));
        if (score <= bestScore) {
            continue;
        }

        bestScore = score;
        bestColor.setRgbF(bucket.red / bucket.weight, bucket.green / bucket.weight, bucket.blue / bucket.weight, 1.0);
    }

    if (!bestColor.isValid()) {
        return fallbackAccentColor();
    }

    return clampAccentColor(bestColor);
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
            it.next();
            const auto fileInfo = it.fileInfo();
            if (!fileInfo.isFile() || !hasAudioSuffix(fileInfo.suffix())) {
                continue;
            }

            const auto absoluteFilePath = fileInfo.absoluteFilePath();
            const auto fileUrl = QUrl::fromLocalFile(absoluteFilePath).toString();
            if (seenUrls.contains(fileUrl)) {
                continue;
            }

            seenUrls.insert(fileUrl);
            auto model = vvave::trackInfo(QUrl::fromLocalFile(absoluteFilePath));
            if (!model.isEmpty()) {
                tracks << model;
            }
        }
    }

    s_cachedTracks = tracks;
    s_trackCacheValid = true;
    ensureCollectionIndexes();
    return s_cachedTracks;
}

FMH::MODEL_LIST vvave::albums()
{
    localTracks();
    ensureCollectionIndexes();
    return s_cachedAlbums;
}

FMH::MODEL_LIST vvave::artists()
{
    localTracks();
    ensureCollectionIndexes();
    return s_cachedArtists;
}

FMH::MODEL_LIST vvave::tracksForTag(const QString &tag)
{
    FMH::MODEL_LIST tracks;
    if (tag.isEmpty()) {
        return tracks;
    }

    localTracks();
    ensureCollectionIndexes();

    const auto urls = Tagging::getInstance()->getTagUrls(tag, {}, true, 99999, "audio");
    for (const auto &url : urls) {
        if (!url.isLocalFile() || !isAudioFile(url.toLocalFile())) {
            continue;
        }

        const auto normalizedUrl = QUrl::fromLocalFile(QFileInfo(url.toLocalFile()).absoluteFilePath()).toString();
        const auto rowIt = s_trackRowByUrl.constFind(normalizedUrl);

        FMH::MODEL model;
        if (rowIt != s_trackRowByUrl.constEnd() && rowIt.value() >= 0 && rowIt.value() < s_cachedTracks.size()) {
            model = s_cachedTracks.at(rowIt.value());
        } else {
            model = vvave::trackInfo(url);
        }

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
        localTracks();
        ensureCollectionIndexes();
        return tracksForRows(s_artistTrackRows.value(artistLookupKey(artist)));
    }

    if (query.startsWith(QStringLiteral("vvave://album/"))) {
        const auto payload = query.mid(QStringLiteral("vvave://album/").size());
        const auto parts = payload.split(QLatin1Char('/'));

        if (parts.size() >= 2) {
            const auto album = QUrl::fromPercentEncoding(parts.at(0).toUtf8());
            const auto artist = QUrl::fromPercentEncoding(parts.at(1).toUtf8());
            localTracks();
            ensureCollectionIndexes();
            return tracksForRows(s_albumTrackRows.value(albumLookupKey(album, artist)));
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

QColor vvave::artworkAccent(const QString &artist, const QString &album)
{
    QString localPath = artworkUrl(artist, album);

    if (localPath.isEmpty() && !artist.isEmpty()) {
        FMH::MODEL data = {{FMH::MODEL_KEY::ARTIST, artist}, {FMH::MODEL_KEY::ALBUM, album}};
        if (BAE::artworkCache(data, FMH::MODEL_KEY::ARTIST)) {
            localPath = QUrl(data[FMH::MODEL_KEY::ARTWORK]).toLocalFile();
        }
    }

    if (localPath.isEmpty()) {
        return fallbackAccentColor();
    }

    const QImage image(localPath);
    return accentFromArtwork(image);
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

    scanDir(urls);

    for (const auto &path : newUrls) {
        Q_EMIT sourceAdded(path);
    }

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
    Q_EMIT collectionChanged();
    return true;
}

void vvave::scanDir(const QList<QUrl> &paths)
{
    Q_UNUSED(paths)
    invalidateTrackCache();
    Q_EMIT collectionChanged();

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
