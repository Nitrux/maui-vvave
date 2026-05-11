#include "artworkprovider.h"

#include "../../utils/bae.h"
#include "taginfo.h"
#include "vvave.h"

#include <MauiKit4/FileBrowsing/downloader.h>

#include <QDebug>
#include <QDateTime>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <QUrl>

#include <memory>

namespace
{
constexpr qint64 kMissingArtworkRetryMs = 10 * 60 * 1000;

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

QHash<QString, QImage> s_sessionArtworkCache;
QHash<QString, qint64> s_missingArtworkCooldownUntil;
QHash<QString, QList<QPointer<AsyncImageResponse>>> s_pendingResponses;
QSet<QString> s_inFlightFetches;

QImage fallbackArtwork()
{
    static QImage fallback(QStringLiteral(":/assets/cover.png"));
    if (!fallback.isNull()) {
        return fallback;
    }

    QImage transparent(1, 1, QImage::Format_ARGB32_Premultiplied);
    transparent.fill(Qt::transparent);
    return transparent;
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

    request.unknownMetadata = (request.type == QStringLiteral("artist") && isUnknownMetadataValue(request.artist))
        || (request.type == QStringLiteral("album")
            && (isUnknownMetadataValue(request.artist) || isUnknownMetadataValue(request.album)));

    request.modelKey = request.type == QStringLiteral("artist") ? FMH::MODEL_KEY::ARTIST : FMH::MODEL_KEY::ALBUM;
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

void completePendingResponses(const QString &cacheKey, const QImage &image, bool rememberMiss)
{
    if (!image.isNull()) {
        s_sessionArtworkCache.insert(cacheKey, image);
        s_missingArtworkCooldownUntil.remove(cacheKey);
    } else if (rememberMiss) {
        s_missingArtworkCooldownUntil.insert(cacheKey, QDateTime::currentMSecsSinceEpoch() + kMissingArtworkRetryMs);
    }

    const auto pending = s_pendingResponses.take(cacheKey);
    const QImage finalImage = image.isNull() ? fallbackArtwork() : image;

    for (const auto &response : pending) {
        if (response) {
            response->complete(finalImage);
        }
    }

    s_inFlightFetches.remove(cacheKey);
}
}

void AsyncImageResponse::finishWithImage(const QImage &image)
{
    if (m_completed) {
        return;
    }

    if (!image.isNull()) {
        m_image = image;
    } else {
        m_image = QImage(":/assets/cover.png");
        if (m_image.isNull()) {
            m_image = QImage(1, 1, QImage::Format_ARGB32_Premultiplied);
            m_image.fill(Qt::transparent);
        }
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
    qDebug() << "[ARTWORK] request id=" << id << "requestedSize=" << requestedSize;
    const auto request = parseArtworkRequest(id);
    if (!request.valid) {
        qWarning() << "[ARTWORK] invalid request id, using cover fallback";
        finishWithImage(fallbackArtwork());
        return;
    }

    qDebug() << "[ARTWORK] parsed type=" << request.type << "artist=" << request.artist << "album=" << request.album;

    if (request.unknownMetadata) {
        qDebug() << "[ARTWORK] unknown metadata, using cover fallback";
        finishWithImage(fallbackArtwork());
        return;
    }

    const auto cachedImageIt = s_sessionArtworkCache.constFind(request.cacheKey);
    if (cachedImageIt != s_sessionArtworkCache.constEnd() && !cachedImageIt.value().isNull()) {
        qDebug() << "[ARTWORK] session-cache hit for" << request.cacheKey;
        finishWithImage(cachedImageIt.value());
        return;
    }

    FMH::MODEL data = {{FMH::MODEL_KEY::ARTIST, request.artist}, {FMH::MODEL_KEY::ALBUM, request.album}};

    if (BAE::artworkCache(data, request.modelKey)) {
        const auto cachedPath = QUrl(data[FMH::MODEL_KEY::ARTWORK]).toLocalFile();
        const auto cachedImage = QImage(cachedPath);
        qDebug() << "[ARTWORK] cache-hit path=" << cachedPath << "isNull=" << cachedImage.isNull();
        if (cachedImage.isNull()) {
            qWarning() << "[ARTWORK] cached image failed to decode, using cover fallback";
            finishWithImage(fallbackArtwork());
        } else {
            s_sessionArtworkCache.insert(request.cacheKey, cachedImage);
            finishWithImage(cachedImage);
        }
        return;
    }

    if (!vvave::instance()->fetchArtwork()) {
        qDebug() << "[ARTWORK] cache-miss and fetch disabled, using cover fallback";
        finishWithImage(fallbackArtwork());
        return;
    }

    if (shouldSkipFetchForRecentMiss(request.cacheKey)) {
        qDebug() << "[ARTWORK] recent miss cached, using cover fallback for" << request.cacheKey;
        finishWithImage(fallbackArtwork());
        return;
    }

    s_pendingResponses[request.cacheKey].append(QPointer<AsyncImageResponse>(this));

    if (s_inFlightFetches.contains(request.cacheKey)) {
        qDebug() << "[ARTWORK] fetch already in flight for" << request.cacheKey;
        return;
    }

    s_inFlightFetches.insert(request.cacheKey);

    qDebug() << "[ARTWORK] cache-miss, fetching online for" << request.artist << request.album;
    auto artworkFetcher = new ArtworkFetcher;
    QPointer<ArtworkFetcher> guardedFetcher(artworkFetcher);
    const auto settled = std::make_shared<bool>(false);

    auto finalizeFetch = [cacheKey = request.cacheKey, settled](const QImage &image, bool rememberMiss) {
        if (*settled) {
            return;
        }

        *settled = true;
        completePendingResponses(cacheKey, image, rememberMiss);
    };

    connect(artworkFetcher, &ArtworkFetcher::artworkReady, vvave::instance(), [finalizeFetch, guardedFetcher](QUrl url) {
        qDebug() << "[ARTWORK] fetch-finished url=" << url;
        if (guardedFetcher) {
            guardedFetcher->deleteLater();
        }

        if (url.isEmpty() || !url.isLocalFile()) {
            qWarning() << "[ARTWORK] non-local/empty fetch result, using cover fallback";
            finalizeFetch(QImage(), true);
            return;
        }

        const auto localPath = url.toLocalFile();
        const auto fetchedImage = QImage(localPath);
        qDebug() << "[ARTWORK] loaded fetched path=" << localPath
                 << "exists=" << QFileInfo::exists(localPath)
                 << "isNull=" << fetchedImage.isNull();
        if (fetchedImage.isNull()) {
            qWarning() << "[ARTWORK] fetched image failed to decode, using cover fallback";
            finalizeFetch(QImage(), true);
            return;
        }

        finalizeFetch(fetchedImage, false);
    });

    QTimer::singleShot(4000, vvave::instance(), [finalizeFetch, guardedFetcher]() {
        qWarning() << "[ARTWORK] fetch timeout reached, using cover fallback";
        if (guardedFetcher) {
            guardedFetcher->deleteLater();
        }
        finalizeFetch(QImage(), true);
    });

    artworkFetcher->fetch(data, request.modelKey == FMH::MODEL_KEY::ALBUM ? PULPO::ONTOLOGY::ALBUM : PULPO::ONTOLOGY::ARTIST);
}

QQuickTextureFactory *AsyncImageResponse::textureFactory() const
{
    if (!m_image.isNull()) {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    QImage fallback(":/assets/cover.png");
    if (fallback.isNull()) {
        fallback = QImage(1, 1, QImage::Format_ARGB32_Premultiplied);
        fallback.fill(Qt::transparent);
    }
    return QQuickTextureFactory::textureFactoryForImage(fallback);
}

QQuickImageResponse *ArtworkProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    AsyncImageResponse *response = new AsyncImageResponse(id, requestedSize);
    return response;
}

void ArtworkFetcher::fetch(FMH::MODEL data, PULPO::ONTOLOGY ontology)
{
    qDebug() << "[ARTWORK] fetch-start ontology=" << static_cast<int>(ontology) << "track=" << data;
    PULPO::REQUEST request;
    request.track = data;
    request.ontology = ontology;
    request.services = {PULPO::SERVICES::LastFm, PULPO::SERVICES::Spotify};
    request.info = {PULPO::INFO::ARTWORK};
    QPointer<ArtworkFetcher> self(this);
    request.callback = [self](PULPO::REQUEST request, PULPO::RESPONSES responses) {
        if (!self) {
            return;
        }

        qDebug() << "[ARTWORK] fetch-callback responses=" << responses.size() << "track=" << request.track;

        bool requestedDownload = false;

        for (const auto &res : responses) {
            if (res.context == PULPO::PULPO_CONTEXT::IMAGE) {
                auto imageUrl = res.value.toString();
                qDebug() << "[ARTWORK] response image-url=" << imageUrl;

                if (!imageUrl.isEmpty()) {
                    requestedDownload = true;
                    auto downloader = new FMH::Downloader;
                    QObject::connect(downloader, &FMH::Downloader::fileSaved, [self, downloader](QString path) mutable {
                        downloader->deleteLater();
                        if (!self) {
                            return;
                        }
                        qDebug() << "[ARTWORK] download-saved path=" << path;
                        Q_EMIT self->artworkReady(QUrl::fromLocalFile(path));
                    });
                    QObject::connect(downloader, &FMH::Downloader::warning, [self, downloader](const QString &message) mutable {
                        downloader->deleteLater();
                        if (!self) {
                            return;
                        }
                        qWarning() << "[ARTWORK] download-warning:" << message << "using cover fallback";
                        Q_EMIT self->artworkReady(QUrl(":/assets/cover.png"));
                    });

                    const auto format = res.value.toUrl().fileName().endsWith(".png") ? ".png" : ".jpg";
                    QString name = !request.track[FMH::MODEL_KEY::ALBUM].isEmpty() ? request.track[FMH::MODEL_KEY::ARTIST] + "_" + request.track[FMH::MODEL_KEY::ALBUM] : request.track[FMH::MODEL_KEY::ARTIST];

                    BAE::fixArtworkImageFileName(name);

                    downloader->downloadFile(QUrl(imageUrl), QUrl(BAE::CachePath.toString() + name + format));
                    qDebug() << "[ARTWORK] downloading for album=" << request.track[FMH::MODEL_KEY::ALBUM]
                             << "target=" << BAE::CachePath.toString() + name + format;
                    break;
                }
            }
        }

        if (!requestedDownload) {
            qWarning() << "[ARTWORK] no downloadable image in responses, using cover fallback";
            Q_EMIT self->artworkReady(QUrl(":/assets/cover.png"));
        }
    };

    auto pulpo = new Pulpo;
    QObject::connect(pulpo, &Pulpo::finished, pulpo, &Pulpo::deleteLater);
    QObject::connect(pulpo, &Pulpo::error, this, [this, pulpo]() {
        qWarning() << "[ARTWORK] pulpo request error, using cover fallback";
        Q_EMIT this->artworkReady(QUrl(":/assets/cover.png"));
        pulpo->deleteLater();
    });

    pulpo->request(request);
}
