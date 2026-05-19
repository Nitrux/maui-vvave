#include "vvave.h"

#include "services/local/taginfo.h"

#include <MauiKit4/FileBrowsing/fmstatic.h>
#include <MauiKit4/FileBrowsing/tagging.h>

#include <QDir>
#include <QDirIterator>
#include <QColor>
#include <QDebug>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSet>
#include <QSettings>
#include <QFutureWatcher>
#include <QTimer>
#include <QtConcurrent>
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
constexpr int kTrackCacheVersion = 1;
constexpr int kParallelParseThreshold = 12;

struct CachedTrackEntry
{
    FMH::MODEL model;
    qint64 size = -1;
    qint64 modifiedMs = -1;
};

struct LoadedTrackCache
{
    QHash<QString, CachedTrackEntry> entries;
    bool valid = false;
};

struct PendingTrackParse
{
    int row = -1;
    QString fileUrl;
    QString absoluteFilePath;
    qint64 size = -1;
    qint64 modifiedMs = -1;
};

struct ParsedTrackResult
{
    int row = -1;
    QString fileUrl;
    CachedTrackEntry entry;
};

struct CollectionScanStats
{
    int totalTracks = 0;
    int reusedTracks = 0;
    int parsedTracks = 0;
    qint64 elapsedMs = 0;
};

struct ScanResult
{
    FMH::MODEL_LIST tracks;
    CollectionScanStats stats;
};

CollectionScanStats s_lastScanStats;

const QSet<QString> &audioSuffixes()
{
    static const QSet<QString> kAudioSuffixes = {
        QStringLiteral("mp3"), QStringLiteral("flac"), QStringLiteral("ogg"), QStringLiteral("oga"), QStringLiteral("opus"),
        QStringLiteral("wav"), QStringLiteral("m4a"), QStringLiteral("aac"), QStringLiteral("wma"), QStringLiteral("aiff"),
        QStringLiteral("ape"), QStringLiteral("alac"), QStringLiteral("mp2"), QStringLiteral("mp1")};

    return kAudioSuffixes;
}

const QStringList &audioNameFilters()
{
    static const QStringList kAudioNameFilters = [] {
        QStringList filters;
        const auto suffixes = audioSuffixes().values();
        filters.reserve(suffixes.size());

        for (const auto &suffix : suffixes) {
            filters << (QStringLiteral("*.") + suffix);
        }

        filters.sort(Qt::CaseInsensitive);
        return filters;
    }();

    return kAudioNameFilters;
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

QUrl normalizeSourceUrl(const QUrl &source)
{
    QString localPath;

    if (source.isLocalFile()) {
        localPath = source.toLocalFile();
    } else if (source.scheme().isEmpty()) {
        localPath = source.toString();
    } else {
        return {};
    }

    localPath = QDir::cleanPath(localPath.trimmed());
    if (localPath.isEmpty()) {
        return {};
    }

    QFileInfo info(localPath);
    if (info.isRelative()) {
        localPath = QDir::cleanPath(QDir::current().absoluteFilePath(localPath));
    } else {
        localPath = info.absoluteFilePath();
    }

    if (localPath.isEmpty()) {
        return {};
    }

    return QUrl::fromLocalFile(localPath).adjusted(QUrl::NormalizePathSegments | QUrl::StripTrailingSlash);
}

QString normalizedSourceKey(const QUrl &source)
{
    return source.toString(QUrl::FullyEncoded | QUrl::NormalizePathSegments | QUrl::StripTrailingSlash);
}

QList<QUrl> sanitizeSourceList(const QList<QUrl> &sources, bool *changed = nullptr)
{
    QList<QUrl> sanitized;
    QSet<QString> seenKeys;
    bool modified = false;

    for (const auto &source : sources) {
        const auto normalized = normalizeSourceUrl(source);
        if (!normalized.isValid()) {
            modified = true;
            continue;
        }

        const auto key = normalizedSourceKey(normalized);
        if (seenKeys.contains(key)) {
            modified = true;
            continue;
        }

        seenKeys.insert(key);
        sanitized << normalized;

        if (normalized != source) {
            modified = true;
        }
    }

    if (changed) {
        *changed = modified;
    }

    return sanitized;
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

QString collectionCacheFilePath()
{
    return QDir(BAE::CachePath.toLocalFile()).filePath(QStringLiteral("collection-cache-v1.json"));
}

qint64 fileModifiedMs(const QFileInfo &fileInfo)
{
    return fileInfo.lastModified().toMSecsSinceEpoch();
}

QJsonObject modelToJson(const FMH::MODEL &model)
{
    QJsonObject object;

    for (auto it = model.constBegin(); it != model.constEnd(); ++it) {
        const auto keyName = FMH::MODEL_NAME.value(it.key());
        if (!keyName.isEmpty()) {
            object.insert(keyName, it.value());
        }
    }

    return object;
}

FMH::MODEL modelFromJson(const QJsonObject &object)
{
    FMH::MODEL model;

    for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
        const auto keyIt = FMH::MODEL_NAME_KEY.constFind(it.key());
        if (keyIt != FMH::MODEL_NAME_KEY.constEnd()) {
            model.insert(keyIt.value(), it.value().toString());
        }
    }

    return model;
}

LoadedTrackCache loadTrackCache()
{
    LoadedTrackCache cache;
    QFile file(collectionCacheFilePath());

    if (!file.exists() || !file.open(QIODevice::ReadOnly)) {
        return cache;
    }

    const auto document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject()) {
        return cache;
    }

    const auto root = document.object();
    if (root.value(QStringLiteral("version")).toInt() != kTrackCacheVersion) {
        return cache;
    }

    cache.valid = true;

    const auto tracksValue = root.value(QStringLiteral("tracks"));
    if (!tracksValue.isArray()) {
        return cache;
    }

    const auto tracks = tracksValue.toArray();
    for (const auto &trackValue : tracks) {
        if (!trackValue.isObject()) {
            continue;
        }

        const auto trackObject = trackValue.toObject();
        const auto modelValue = trackObject.value(QStringLiteral("model"));
        if (!modelValue.isObject()) {
            continue;
        }

        CachedTrackEntry entry;
        entry.model = modelFromJson(modelValue.toObject());
        entry.size = trackObject.value(QStringLiteral("size")).toVariant().toLongLong();
        entry.modifiedMs = trackObject.value(QStringLiteral("modifiedMs")).toVariant().toLongLong();

        const auto url = entry.model.value(FMH::MODEL_KEY::URL);
        if (!url.isEmpty()) {
            cache.entries.insert(url, entry);
        }
    }

    return cache;
}

void saveTrackCache(const QHash<QString, CachedTrackEntry> &entries)
{
    QSaveFile file(collectionCacheFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }

    QJsonArray tracks;
    auto urls = entries.keys();
    std::sort(urls.begin(), urls.end(), [](const QString &left, const QString &right) {
        return QString::localeAwareCompare(left, right) < 0;
    });

    for (const auto &url : urls) {
        const auto entry = entries.value(url);
        if (entry.model.isEmpty()) {
            continue;
        }

        QJsonObject trackObject;
        trackObject.insert(QStringLiteral("size"), QString::number(entry.size));
        trackObject.insert(QStringLiteral("modifiedMs"), QString::number(entry.modifiedMs));
        trackObject.insert(QStringLiteral("model"), modelToJson(entry.model));
        tracks.append(trackObject);
    }

    QJsonObject root;
    root.insert(QStringLiteral("version"), kTrackCacheVersion);
    root.insert(QStringLiteral("tracks"), tracks);

    if (file.write(QJsonDocument(root).toJson(QJsonDocument::Compact)) == -1) {
        file.cancelWriting();
        return;
    }

    file.commit();
}

bool canReuseCachedTrack(const CachedTrackEntry &entry, const QFileInfo &fileInfo)
{
    return !entry.model.isEmpty() && entry.size == fileInfo.size() && entry.modifiedMs == fileModifiedMs(fileInfo);
}

ParsedTrackResult parseTrackEntry(const PendingTrackParse &pendingParse)
{
    ParsedTrackResult result;
    result.row = pendingParse.row;
    result.fileUrl = pendingParse.fileUrl;
    result.entry.size = pendingParse.size;
    result.entry.modifiedMs = pendingParse.modifiedMs;
    result.entry.model = vvave::trackInfo(QUrl::fromLocalFile(pendingParse.absoluteFilePath));
    return result;
}

bool enqueueFileForScan(const QFileInfo &fileInfo,
                        const QHash<QString, CachedTrackEntry> &cachedEntries,
                        QHash<QString, CachedTrackEntry> &updatedEntries,
                        QVector<FMH::MODEL> &trackSlots,
                        QVector<PendingTrackParse> &pendingParses,
                        QSet<QString> &seenUrls,
                        int &reusedTracks,
                        bool &cacheDirty)
{
    if (!fileInfo.exists() || !fileInfo.isFile()) {
        return false;
    }

    const auto absoluteFilePath = fileInfo.absoluteFilePath();
    const auto fileUrl = QUrl::fromLocalFile(absoluteFilePath).toString();
    if (seenUrls.contains(fileUrl)) {
        return false;
    }

    seenUrls.insert(fileUrl);
    trackSlots.append(FMH::MODEL());
    const int row = trackSlots.size() - 1;

    const auto cachedIt = cachedEntries.constFind(fileUrl);
    if (cachedIt != cachedEntries.constEnd() && canReuseCachedTrack(cachedIt.value(), fileInfo)) {
        const auto entry = cachedIt.value();
        trackSlots[row] = entry.model;
        updatedEntries.insert(fileUrl, entry);
        reusedTracks++;
        return true;
    }

    cacheDirty = true;
    pendingParses.append(PendingTrackParse{
        row,
        fileUrl,
        absoluteFilePath,
        fileInfo.size(),
        fileModifiedMs(fileInfo),
    });
    return true;
}

FMH::MODEL_LIST materializeTrackList(const QVector<FMH::MODEL> &trackSlots)
{
    FMH::MODEL_LIST tracks;
    tracks.reserve(trackSlots.size());

    for (const auto &track : trackSlots) {
        if (!track.isEmpty()) {
            tracks << track;
        }
    }

    return tracks;
}

QVector<ParsedTrackResult> parsePendingTracks(const QVector<PendingTrackParse> &pendingParses)
{
    if (pendingParses.isEmpty()) {
        return {};
    }

    if (pendingParses.size() < kParallelParseThreshold) {
        QVector<ParsedTrackResult> parsedResults;
        parsedResults.reserve(pendingParses.size());
        for (const auto &pendingParse : pendingParses) {
            parsedResults.append(parseTrackEntry(pendingParse));
        }
        return parsedResults;
    }

    return QtConcurrent::blockingMapped(pendingParses, [](const PendingTrackParse &pendingParse) {
        return parseTrackEntry(pendingParse);
    });
}

void applyParsedTracks(const QVector<ParsedTrackResult> &parsedResults,
                       QVector<FMH::MODEL> &trackSlots,
                       QHash<QString, CachedTrackEntry> &updatedEntries)
{
    for (const auto &result : parsedResults) {
        if (result.row < 0 || result.row >= trackSlots.size()) {
            continue;
        }

        if (result.entry.model.isEmpty()) {
            continue;
        }

        trackSlots[result.row] = result.entry.model;
        updatedEntries.insert(result.fileUrl, result.entry);
    }
}

void logScanSummary(const CollectionScanStats &stats)
{
    qInfo().nospace() << "[COLLECTION] scanned " << stats.totalTracks << " tracks in " << stats.elapsedMs
                      << " ms (reused=" << stats.reusedTracks << ", parsed=" << stats.parsedTracks << ")";
}

void resetScanStats()
{
    s_lastScanStats = {};
}

void updateScanStats(const CollectionScanStats &stats)
{
    s_lastScanStats = stats;
}

const CollectionScanStats &lastScanStats()
{
    return s_lastScanStats;
}

void collectAudioFilesFromSource(const QFileInfo &sourceInfo,
                                 const QHash<QString, CachedTrackEntry> &cachedEntries,
                                 QHash<QString, CachedTrackEntry> &updatedEntries,
                                 QVector<FMH::MODEL> &trackSlots,
                                 QVector<PendingTrackParse> &pendingParses,
                                 QSet<QString> &seenUrls,
                                 int &reusedTracks,
                                 bool &cacheDirty)
{
    if (!sourceInfo.exists()) {
        return;
    }

    if (sourceInfo.isFile()) {
        const auto normalizedUrl = QUrl::fromLocalFile(sourceInfo.absoluteFilePath()).toString();
        if (!isAudioFile(sourceInfo.absoluteFilePath()) || seenUrls.contains(normalizedUrl)) {
            return;
        }

        enqueueFileForScan(sourceInfo, cachedEntries, updatedEntries, trackSlots, pendingParses, seenUrls, reusedTracks, cacheDirty);
        return;
    }

    QDirIterator it(sourceInfo.absoluteFilePath(), audioNameFilters(), QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        enqueueFileForScan(it.fileInfo(), cachedEntries, updatedEntries, trackSlots, pendingParses, seenUrls, reusedTracks, cacheDirty);
    }
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

// Runs entirely on a background thread — must not read or write any global state.
// Receives source URLs as a parameter to avoid touching QSettings from the worker.
ScanResult performScanWork(const QList<QUrl> &sourceUrls)
{
    QElapsedTimer timer;
    timer.start();

    auto loadedCache = loadTrackCache();
    auto updatedCacheEntries = QHash<QString, CachedTrackEntry>();
    updatedCacheEntries.reserve(loadedCache.entries.size() > 128 ? loadedCache.entries.size() : 128);

    QVector<FMH::MODEL> trackSlots;
    trackSlots.reserve(loadedCache.entries.size() > 128 ? loadedCache.entries.size() : 128);
    QVector<PendingTrackParse> pendingParses;
    pendingParses.reserve(128);

    QSet<QString> seenUrls;
    bool cacheDirty = !loadedCache.valid;
    int reusedTracks = 0;

    for (const auto &source : sourceUrls) {
        if (!source.isLocalFile()) {
            continue;
        }

        QFileInfo sourceInfo(source.toLocalFile());
        collectAudioFilesFromSource(sourceInfo,
                                    loadedCache.entries,
                                    updatedCacheEntries,
                                    trackSlots,
                                    pendingParses,
                                    seenUrls,
                                    reusedTracks,
                                    cacheDirty);
    }

    const bool loadedCacheValid = loadedCache.valid;
    const int loadedCacheEntryCount = static_cast<int>(loadedCache.entries.size());
    { QHash<QString, CachedTrackEntry> tmp; loadedCache.entries.swap(tmp); }

    const auto parsedResults = parsePendingTracks(pendingParses);
    applyParsedTracks(parsedResults, trackSlots, updatedCacheEntries);

    const int parsedTracks = static_cast<int>(pendingParses.size());
    const auto tracks = materializeTrackList(trackSlots);

    CollectionScanStats stats;
    stats.totalTracks = tracks.size();
    stats.reusedTracks = reusedTracks;
    stats.parsedTracks = parsedTracks;
    stats.elapsedMs = timer.elapsed();

    if (loadedCacheValid && stats.parsedTracks == 0 && updatedCacheEntries.size() == loadedCacheEntryCount) {
        cacheDirty = false;
    }

    if (updatedCacheEntries.size() != loadedCacheEntryCount) {
        cacheDirty = true;
    }

    if (cacheDirty) {
        saveTrackCache(updatedCacheEntries);
    }

    return ScanResult{tracks, stats};
}

FMH::MODEL_LIST vvave::localTracks()
{
    if (s_trackCacheValid) {
        return s_cachedTracks;
    }

    // Cache is not ready. Trigger a background scan if one isn't already running;
    // callers will receive the data through collectionChanged → setList.
    auto *inst = instance();
    if (!inst->m_scanning && !inst->m_scanScheduled && !sources().isEmpty()) {
        inst->rescan();
    }

    return {};
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
        const int separator = payload.lastIndexOf(QLatin1Char('/'));

        if (separator > 0 && separator < (payload.size() - 1)) {
            const auto encodedAlbum = payload.left(separator);
            const auto encodedArtist = payload.mid(separator + 1);
            const auto album = QUrl::fromPercentEncoding(encodedAlbum.toUtf8());
            const auto artist = QUrl::fromPercentEncoding(encodedArtist.toUtf8());
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
    bool changed = false;
    auto urls = sanitizeSourceList(QUrl::fromStringList(sources()), &changed);
    auto incoming = sanitizeSourceList(paths);
    QList<QUrl> newUrls;
    QSet<QString> seenKeys;

    for (const auto &url : urls) {
        seenKeys.insert(normalizedSourceKey(url));
    }

    for (const auto &path : incoming) {
        const auto key = normalizedSourceKey(path);
        if (!seenKeys.contains(key)) {
            newUrls << path;
            seenKeys.insert(key);
        }
    }

    if (newUrls.isEmpty() && !changed) {
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
    auto urls = sanitizeSourceList(QUrl::fromStringList(this->sources()));
    const auto target = normalizeSourceUrl(QUrl::fromUserInput(source));

    if (!target.isValid()) {
        return false;
    }

    const auto targetKey = normalizedSourceKey(target);
    const auto removeIt = std::find_if(urls.begin(), urls.end(), [&](const QUrl &url) {
        return normalizedSourceKey(url) == targetKey;
    });

    if (removeIt == urls.end()) {
        return false;
    }

    urls.erase(removeIt);

    QSettings settings;
    settings.beginGroup("SETTINGS");
    settings.setValue("SOURCES", QVariant::fromValue(QUrl::toStringList(urls)));
    settings.endGroup();

    scanDir(urls);
    Q_EMIT this->sourceRemoved(target);
    Q_EMIT sourcesChanged();
    return true;
}

void vvave::scanDir(const QList<QUrl> &paths)
{
    Q_UNUSED(paths)
    invalidateTrackCache();
    resetScanStats();

    if (m_scanScheduled) {
        return;
    }

    m_scanning = true;
    Q_EMIT scanningChanged(m_scanning);
    m_scanScheduled = true;

    // Snapshot source URLs on the main thread before handing off to the worker.
    const QList<QUrl> sourceUrls = QUrl::fromStringList(sources());

    auto *watcher = new QFutureWatcher<ScanResult>(this);
    connect(watcher, &QFutureWatcher<ScanResult>::finished, this, [this, watcher]() {
        auto result = watcher->result();
        watcher->deleteLater();

        // Apply results back on the main thread — all global state stays main-thread-only.
        s_cachedTracks = std::move(result.tracks);
        s_trackCacheValid = true;
        s_collectionIndexesValid = false;
        ensureCollectionIndexes();
        updateScanStats(result.stats);
        logScanSummary(lastScanStats());

        m_scanScheduled = false;
        m_scanning = false;
        Q_EMIT scanningChanged(m_scanning);
        Q_EMIT collectionChanged();

        const auto &stats = result.stats;
        Q_EMIT scanFinished(stats.totalTracks, stats.reusedTracks, stats.parsedTracks, stats.elapsedMs);
    });

    watcher->setFuture(QtConcurrent::run([sourceUrls]() -> ScanResult {
        return performScanWork(sourceUrls);
    }));
}

void vvave::rescan()
{
    scanDir(QUrl::fromStringList(sources()));
}

QStringList vvave::sources()
{
    QSettings settings;
    settings.beginGroup("SETTINGS");
    const auto stored = settings.value("SOURCES").toStringList();
    settings.endGroup();

    QList<QUrl> loaded = QUrl::fromStringList(stored);
    if (loaded.isEmpty()) {
        loaded << normalizeSourceUrl(QUrl::fromUserInput(FMStatic::MusicPath));
    }

    bool changed = false;
    auto sanitized = sanitizeSourceList(loaded, &changed);
    if (sanitized.isEmpty()) {
        const auto fallback = normalizeSourceUrl(QUrl::fromUserInput(FMStatic::MusicPath));
        if (fallback.isValid()) {
            sanitized << fallback;
            changed = true;
        }
    }

    const auto result = QUrl::toStringList(sanitized);
    if (changed || result != stored) {
        QSettings writableSettings;
        writableSettings.beginGroup("SETTINGS");
        writableSettings.setValue("SOURCES", QVariant::fromValue(result));
        writableSettings.endGroup();
    }

    return result;
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
