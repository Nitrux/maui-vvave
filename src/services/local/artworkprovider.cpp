#include "artworkprovider.h"

#include "../../utils/bae.h"
#include "taginfo.h"
#include "vvave.h"

#include <MauiKit4/FileBrowsing/downloader.h>

#include <QCache>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QPointer>
#include <QQueue>
#include <QSet>
#include <QTimer>
#include <QUrl>

#include <algorithm>
#include <memory>

namespace
{
constexpr qint64 kMissingArtworkRetryMs = 10 * 60 * 1000;
constexpr int kArtworkFetchTimeoutMs = 4000;
constexpr int kHighResolutionArtworkFetchTimeoutMs = 30000;
constexpr int kMaxConcurrentArtworkFetches = 2;
constexpr int kMinOnlineFetchEdge = 56;

struct ArtworkRequestData
{
    QString cacheKey;
    QString type;
    QString artist;
    QString album;
    FMH::MODEL_KEY modelKey = FMH::MODEL_KEY::ID;
    bool valid = false;
    bool unknownMetadata = false;
};

// Cost unit: KB of raw pixel data. Capped at 64 MB to prevent unbounded growth.
QCache<QString, QImage> s_sessionArtworkCache(64 * 1024);
QHash<QString, qint64> s_missingArtworkCooldownUntil;
QHash<QString, QList<QPointer<AsyncImageResponse>>> s_pendingResponses;
QSet<QString> s_inFlightFetches;
QQueue<ArtworkRequestData> s_fetchQueue;
int s_activeFetches = 0;

int artworkCostKb(const QImage &img)
{
    return static_cast<int>(std::max(qint64(1), img.sizeInBytes() / 1024));
}

QString normalizedArtworkField(const QString &value)
{
    return value.trimmed().toCaseFolded();
}

QString cacheKeyForRequest(const QString &type, const QString &artist, const QString &album)
{
    return type + QStringLiteral("\x1f") + normalizedArtworkField(artist) + QStringLiteral("\x1f") + normalizedArtworkField(album);
}

bool isUnknownMetadataValue(const QString &value)
{
    const QString normalized = value.trimmed();
    if (normalized.isEmpty()) {
        return true;
    }

    if (normalized.compare(BAE::SLANG[BAE::W::UNKNOWN], Qt::CaseInsensitive) == 0) {
        return true;
    }

    return normalized.compare(QStringLiteral("UNKNOWN"), Qt::CaseInsensitive) == 0;
}

ArtworkRequestData parseArtworkRequest(const QString &id)
{
    ArtworkRequestData request;

    const auto parts = id.split(QStringLiteral(":"), Qt::KeepEmptyParts);
    if (parts.isEmpty()) {
        return request;
    }

    request.type = parts[0];

    if (parts.length() >= 2) {
        request.artist = QUrl::fromPercentEncoding(parts[1].toUtf8());
    }

    if (parts.length() >= 3) {
        QString albumPayload = parts[2];
        for (int i = 3; i < parts.length(); ++i) {
            albumPayload += QStringLiteral(":");
            albumPayload += parts[i];
        }
        request.album = QUrl::fromPercentEncoding(albumPayload.toUtf8());
    }

    const bool artistArtwork = request.type == QStringLiteral("artist") || request.type == QStringLiteral("focusArtist");
    const bool albumArtwork = request.type == QStringLiteral("album") || request.type == QStringLiteral("focusAlbum");
    request.unknownMetadata = (artistArtwork && isUnknownMetadataValue(request.artist))
        || (albumArtwork && (isUnknownMetadataValue(request.artist) || isUnknownMetadataValue(request.album)));

    request.modelKey = artistArtwork ? FMH::MODEL_KEY::ARTIST : FMH::MODEL_KEY::ALBUM;
    request.cacheKey = cacheKeyForRequest(request.type, request.artist, request.album);
    request.valid = !request.type.isEmpty();
    return request;
}

bool shouldSkipFetchForRecentMiss(const QString &cacheKey)
{
    const auto expiry = s_missingArtworkCooldownUntil.value(cacheKey, 0);
    if (expiry <= 0) {
        return false;
    }

    if (expiry <= QDateTime::currentMSecsSinceEpoch()) {
        s_missingArtworkCooldownUntil.remove(cacheKey);
        return false;
    }

    return true;
}

bool shouldDeferOnlineFetch(const QSize &requestedSize)
{
    if (!requestedSize.isValid()) {
        return false;
    }

    if (requestedSize.width() <= 0 || requestedSize.height() <= 0) {
        return false;
    }

    const int shortEdge = requestedSize.width() < requestedSize.height() ? requestedSize.width() : requestedSize.height();
    return shortEdge > 0 && shortEdge < kMinOnlineFetchEdge;
}

bool hasLivePendingResponses(const QString &cacheKey)
{
    const auto pending = s_pendingResponses.value(cacheKey);
    for (const auto &response : pending) {
        if (response) {
            return true;
        }
    }

    return false;
}

void removeInvalidArtworkFile(const QString &localPath)
{
    if (localPath.isEmpty()) {
        return;
    }

    const QFileInfo info(localPath);
    if (!info.exists() || !info.isFile()) {
        return;
    }

    QFile::remove(localPath);
}

void completePendingResponses(const QString &cacheKey, const QImage &image, bool rememberMiss)
{
    if (!image.isNull()) {
        s_sessionArtworkCache.insert(cacheKey, new QImage(image), artworkCostKb(image));
        s_missingArtworkCooldownUntil.remove(cacheKey);
    } else if (rememberMiss) {
        s_missingArtworkCooldownUntil.insert(cacheKey, QDateTime::currentMSecsSinceEpoch() + kMissingArtworkRetryMs);
    }

    const auto pending = s_pendingResponses.take(cacheKey);
    // Missing artwork completes as an image error so Maui.IconItem reveals the delegate iconSource.
    for (const auto &response : pending) {
        if (response) {
            response->complete(image);
        }
    }

    s_inFlightFetches.remove(cacheKey);
}

void processArtworkQueue();

void startArtworkFetch(const ArtworkRequestData &request)
{
    FMH::MODEL data = {{FMH::MODEL_KEY::ARTIST, request.artist}, {FMH::MODEL_KEY::ALBUM, request.album}};
    auto artworkFetcher = new ArtworkFetcher;
    QPointer<ArtworkFetcher> guardedFetcher(artworkFetcher);
    const auto settled = std::make_shared<bool>(false);

    auto finalizeFetch = [cacheKey = request.cacheKey, settled, guardedFetcher](const QImage &image, bool rememberMiss) {
        if (*settled) {
            return;
        }

        *settled = true;

        if (guardedFetcher) {
            guardedFetcher->deleteLater();
        }

        completePendingResponses(cacheKey, image, rememberMiss);
        s_activeFetches = std::max(0, s_activeFetches - 1);

        QTimer::singleShot(0, vvave::instance(), [] {
            processArtworkQueue();
        });
    };

    QObject::connect(artworkFetcher, &ArtworkFetcher::artworkReady, vvave::instance(), [finalizeFetch](QUrl url) {
        if (url.isEmpty() || !url.isLocalFile()) {
            finalizeFetch(QImage(), true);
            return;
        }

        const auto localPath = url.toLocalFile();
        const auto fetchedImage = QImage(localPath);
        if (fetchedImage.isNull()) {
            removeInvalidArtworkFile(localPath);
            finalizeFetch(QImage(), true);
            return;
        }

        finalizeFetch(fetchedImage, false);
    });

    const int fetchTimeout = request.type.startsWith(QStringLiteral("focus"))
        ? kHighResolutionArtworkFetchTimeoutMs
        : kArtworkFetchTimeoutMs;
    QTimer::singleShot(fetchTimeout, vvave::instance(), [finalizeFetch]() {
        finalizeFetch(QImage(), true);
    });

    s_activeFetches++;
    artworkFetcher->fetch(data,
                          request.modelKey == FMH::MODEL_KEY::ALBUM ? PULPO::ONTOLOGY::ALBUM : PULPO::ONTOLOGY::ARTIST,
                          request.type.startsWith(QStringLiteral("focus")));
}

void processArtworkQueue()
{
    while (s_activeFetches < kMaxConcurrentArtworkFetches && !s_fetchQueue.isEmpty()) {
        const auto request = s_fetchQueue.dequeue();

        if (!s_inFlightFetches.contains(request.cacheKey)) {
            continue;
        }

        if (!hasLivePendingResponses(request.cacheKey)) {
            s_pendingResponses.remove(request.cacheKey);
            s_inFlightFetches.remove(request.cacheKey);
            continue;
        }

        startArtworkFetch(request);
    }
}
}

void AsyncImageResponse::finishWithImage(const QImage &image)
{
    if (m_completed) {
        return;
    }

    if (!image.isNull()) {
        m_image = image;
        m_errorString.clear();
    } else {
        m_image = QImage();
        m_errorString.clear();
    }
    m_completed = true;
    Q_EMIT this->finished();
}

void AsyncImageResponse::complete(const QImage &image)
{
    finishWithImage(image);
}

AsyncImageResponse::AsyncImageResponse(const QString &id, const QSize &requestedSize)
    : m_id(id)
    , m_requestedSize(requestedSize)
{
    const auto request = parseArtworkRequest(id);
    if (!request.valid) {
        finishWithImage(QImage());
        return;
    }

    if (request.unknownMetadata) {
        finishWithImage(QImage());
        return;
    }

    const bool highResolutionRequest = request.type.startsWith(QStringLiteral("focus"));

    const QImage *cachedImagePtr = s_sessionArtworkCache.object(request.cacheKey);
    if (cachedImagePtr && !cachedImagePtr->isNull()) {
        finishWithImage(*cachedImagePtr);
        return;
    }

    FMH::MODEL data = {{FMH::MODEL_KEY::ARTIST, request.artist}, {FMH::MODEL_KEY::ALBUM, request.album}};
    const QString cacheSuffix = highResolutionRequest ? QStringLiteral("_highres") : QString();

    if (BAE::artworkCache(data, request.modelKey, cacheSuffix)) {
        const auto cachedPath = QUrl(data[FMH::MODEL_KEY::ARTWORK]).toLocalFile();
        const auto cachedImage = QImage(cachedPath);
        if (cachedImage.isNull()) {
            removeInvalidArtworkFile(cachedPath);
            if (!highResolutionRequest) {
                finishWithImage(QImage());
                return;
            }
        } else {
            s_sessionArtworkCache.insert(request.cacheKey, new QImage(cachedImage), artworkCostKb(cachedImage));
            finishWithImage(cachedImage);
            return;
        }
    }

    if (!vvave::instance()->fetchArtwork()) {
        finishWithImage(QImage());
        return;
    }

    if (shouldDeferOnlineFetch(m_requestedSize)) {
        finishWithImage(QImage());
        return;
    }

    if (shouldSkipFetchForRecentMiss(request.cacheKey)) {
        finishWithImage(QImage());
        return;
    }

    s_pendingResponses[request.cacheKey].append(QPointer<AsyncImageResponse>(this));

    if (s_inFlightFetches.contains(request.cacheKey)) {
        return;
    }

    s_inFlightFetches.insert(request.cacheKey);
    if (highResolutionRequest) {
        s_fetchQueue.prepend(request);
    } else {
        s_fetchQueue.enqueue(request);
    }
    processArtworkQueue();
}

QString AsyncImageResponse::errorString() const
{
    return m_errorString;
}

QQuickTextureFactory *AsyncImageResponse::textureFactory() const
{
    if (m_image.isNull()) {
        return nullptr;
    }

    return QQuickTextureFactory::textureFactoryForImage(m_image);
}

QQuickImageResponse *ArtworkProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    AsyncImageResponse *response = new AsyncImageResponse(id, requestedSize);
    return response;
}

void ArtworkFetcher::fetch(FMH::MODEL data, PULPO::ONTOLOGY ontology, bool highResolution)
{
    PULPO::REQUEST request;
    request.track = data;
    request.ontology = ontology;
    request.services = {PULPO::SERVICES::LastFm, PULPO::SERVICES::Spotify};
    request.info = {PULPO::INFO::ARTWORK};
    QPointer<ArtworkFetcher> self(this);
    request.callback = [self, highResolution](PULPO::REQUEST request, PULPO::RESPONSES responses) {
        if (!self) {
            return;
        }

        bool requestedDownload = false;

        for (const auto &res : responses) {
            if (res.context == PULPO::PULPO_CONTEXT::IMAGE) {
                auto imageUrl = res.value.toUrl();

                if (highResolution && imageUrl.host().endsWith(QStringLiteral("freetls.fastly.net"))) {
                    auto path = imageUrl.path();
                    const QString marker = QStringLiteral("/i/u/");
                    const auto sizeStart = path.indexOf(marker);
                    const auto valueStart = sizeStart + marker.size();
                    const auto sizeEnd = path.indexOf(QChar('/'), valueStart);
                    if (sizeStart >= 0 && sizeEnd > valueStart) {
                        path.replace(valueStart, sizeEnd - valueStart, QStringLiteral("ar0"));
                        imageUrl.setPath(path);
                    }
                }

                if (!imageUrl.isEmpty()) {
                    requestedDownload = true;
                    auto downloader = new FMH::Downloader(self.data());
                    QObject::connect(self.data(), &QObject::destroyed, downloader, &FMH::Downloader::stop);
                    QObject::connect(downloader, &FMH::Downloader::fileSaved, [self, downloader](QString path) mutable {
                        downloader->deleteLater();
                        if (!self) {
                            return;
                        }
                        Q_EMIT self->artworkReady(QUrl::fromLocalFile(path));
                    });
                    QObject::connect(downloader, &FMH::Downloader::warning, [self, downloader](const QString &message) mutable {
                        downloader->deleteLater();
                        if (!self) {
                            return;
                        }
                        Q_UNUSED(message)
                        Q_EMIT self->artworkReady(QUrl());
                    });

                    const auto format = imageUrl.fileName().endsWith(".png") ? ".png" : ".jpg";
                    QString name = !request.track[FMH::MODEL_KEY::ALBUM].isEmpty() ? request.track[FMH::MODEL_KEY::ARTIST] + "_" + request.track[FMH::MODEL_KEY::ALBUM] : request.track[FMH::MODEL_KEY::ARTIST];

                    BAE::fixArtworkImageFileName(name);
                    if (highResolution) {
                        name += QStringLiteral("_highres");
                    }

                    downloader->downloadFile(imageUrl, QUrl(BAE::CachePath.toString() + name + format));
                    break;
                }
            }
        }

        if (!requestedDownload) {
            Q_EMIT self->artworkReady(QUrl());
        }
    };

    auto pulpo = new Pulpo;
    QObject::connect(pulpo, &Pulpo::finished, pulpo, &Pulpo::deleteLater);
    QObject::connect(pulpo, &Pulpo::error, this, [this, pulpo]() {
        Q_EMIT this->artworkReady(QUrl());
        pulpo->deleteLater();
    });

    pulpo->request(request);
}
