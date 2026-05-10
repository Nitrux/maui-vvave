#include "artworkprovider.h"

#include "../../utils/bae.h"
#include "taginfo.h"
#include "vvave.h"

#include <MauiKit4/FileBrowsing/downloader.h>

#include <QDebug>
#include <QFileInfo>
#include <QImage>
#include <QPointer>
#include <QTimer>
#include <QUrl>

void AsyncImageResponse::finishWithImage(const QImage &image)
{
    if (m_completed) {
        return;
    }

    m_image = image;
    m_completed = true;
    Q_EMIT this->finished();
}

AsyncImageResponse::AsyncImageResponse(const QString &id, const QSize &requestedSize)
    : m_id(id)
    , m_requestedSize(requestedSize)
{
    qDebug() << "[ARTWORK] request id=" << id << "requestedSize=" << requestedSize;
    const auto parts = id.split(":", Qt::KeepEmptyParts);

    if (parts.isEmpty()) {
        qWarning() << "[ARTWORK] invalid request id, using cover fallback";
        finishWithImage(QImage(":/assets/cover.png"));
        return;
    }

    const auto type = parts[0];

    QString artist, album;

    if (parts.length() >= 2)
        artist = QUrl::fromPercentEncoding(parts[1].toUtf8());

    if (parts.length() >= 3) {
        QString albumPayload = parts[2];
        for (int i = 3; i < parts.length(); ++i) {
            albumPayload += ":";
            albumPayload += parts[i];
        }
        album = QUrl::fromPercentEncoding(albumPayload.toUtf8());
    }

    qDebug() << "[ARTWORK] parsed type=" << type << "artist=" << artist << "album=" << album;

    const auto isUnknownMetadata = [](const QString &value) {
        const QString normalized = value.trimmed();
        if (normalized.isEmpty()) {
            return true;
        }

        if (normalized.compare(BAE::SLANG[BAE::W::UNKNOWN], Qt::CaseInsensitive) == 0) {
            return true;
        }

        return normalized.compare(QStringLiteral("UNKNOWN"), Qt::CaseInsensitive) == 0;
    };

    const bool unknownArtist = isUnknownMetadata(artist);
    const bool unknownAlbum = isUnknownMetadata(album);

    if ((type == "artist" && unknownArtist) || (type == "album" && (unknownArtist || unknownAlbum))) {
        qDebug() << "[ARTWORK] unknown metadata, using cover fallback";
        finishWithImage(QImage(":/assets/cover.png"));
        return;
    }

    FMH::MODEL_KEY m_type = FMH::MODEL_KEY::ID;
    if (type == "artist") {
        m_type = FMH::MODEL_KEY::ARTIST;
    } else {
        m_type = FMH::MODEL_KEY::ALBUM;
    }

    FMH::MODEL data = {{FMH::MODEL_KEY::ARTIST, artist}, {FMH::MODEL_KEY::ALBUM, album}};

    if (BAE::artworkCache(data, m_type)) {
        const auto cachedPath = QUrl(data[FMH::MODEL_KEY::ARTWORK]).toLocalFile();
        const auto cachedImage = QImage(cachedPath);
        qDebug() << "[ARTWORK] cache-hit path=" << cachedPath << "isNull=" << cachedImage.isNull();
        if (cachedImage.isNull()) {
            qWarning() << "[ARTWORK] cached image failed to decode, using cover fallback";
            finishWithImage(QImage(":/assets/cover.png"));
        } else {
            finishWithImage(cachedImage);
        }
    } else if (vvave::instance()->fetchArtwork()) {
        qDebug() << "[ARTWORK] cache-miss, fetching online for" << artist << album;
        auto m_artworkFetcher = new ArtworkFetcher;
        QPointer<ArtworkFetcher> guardedFetcher(m_artworkFetcher);
        connect(m_artworkFetcher, &ArtworkFetcher::finished, m_artworkFetcher, &ArtworkFetcher::deleteLater);

        connect(m_artworkFetcher, &ArtworkFetcher::artworkReady, [this, m_artworkFetcher](QUrl url) {
            qDebug() << "[ARTWORK] fetch-finished url=" << url;
            if (url.isEmpty() || !url.isLocalFile()) {
                qWarning() << "[ARTWORK] non-local/empty fetch result, using cover fallback";
                finishWithImage(QImage(":/assets/cover.png"));
            } else {
                const auto localPath = url.toLocalFile();
                const auto fetchedImage = QImage(localPath);
                qDebug() << "[ARTWORK] loaded fetched path=" << localPath
                         << "exists=" << QFileInfo::exists(localPath)
                         << "isNull=" << fetchedImage.isNull();
                if (fetchedImage.isNull()) {
                    qWarning() << "[ARTWORK] fetched image failed to decode, using cover fallback";
                    finishWithImage(QImage(":/assets/cover.png"));
                } else {
                    finishWithImage(fetchedImage);
                }
            }

            m_artworkFetcher->deleteLater();
        });

        QTimer::singleShot(4000, this, [this, guardedFetcher]() {
            if (m_completed) {
                return;
            }

            qWarning() << "[ARTWORK] fetch timeout reached, using cover fallback";
            if (guardedFetcher) {
                guardedFetcher->deleteLater();
            }
            finishWithImage(QImage(":/assets/cover.png"));
        });

        m_artworkFetcher->fetch(data, m_type == FMH::MODEL_KEY::ALBUM ? PULPO::ONTOLOGY::ALBUM : PULPO::ONTOLOGY::ARTIST);
    } else {
        qDebug() << "[ARTWORK] cache-miss and fetch disabled, using cover fallback";
        finishWithImage(QImage(":/assets/cover.png"));
    }
}

QQuickTextureFactory *AsyncImageResponse::textureFactory() const
{
    return QQuickTextureFactory::textureFactoryForImage(m_image);
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
    request.callback = [&](PULPO::REQUEST request, PULPO::RESPONSES responses) {
        qDebug() << "[ARTWORK] fetch-callback responses=" << responses.size() << "track=" << request.track;

        bool requestedDownload = false;

        for (const auto &res : responses) {
            if (res.context == PULPO::PULPO_CONTEXT::IMAGE) {
                auto imageUrl = res.value.toString();
                qDebug() << "[ARTWORK] response image-url=" << imageUrl;

                if (!imageUrl.isEmpty()) {
                    requestedDownload = true;
                    auto downloader = new FMH::Downloader;
                    QObject::connect(downloader, &FMH::Downloader::fileSaved, [&, downloader](QString path) mutable {
                        downloader->deleteLater();
                        qDebug() << "[ARTWORK] download-saved path=" << path;
                        Q_EMIT this->artworkReady(QUrl::fromLocalFile(path));
                    });
                    QObject::connect(downloader, &FMH::Downloader::warning, [&, downloader](const QString &message) mutable {
                        downloader->deleteLater();
                        qWarning() << "[ARTWORK] download-warning:" << message << "using cover fallback";
                        Q_EMIT this->artworkReady(QUrl(":/assets/cover.png"));
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
            Q_EMIT this->artworkReady(QUrl(":/assets/cover.png"));
        }
    };

    auto pulpo = new Pulpo;
    QObject::connect(pulpo, &Pulpo::finished, pulpo, &Pulpo::deleteLater);
    QObject::connect(pulpo, &Pulpo::error, [this, pulpo]() {
        qWarning() << "[ARTWORK] pulpo request error, using cover fallback";
        Q_EMIT this->artworkReady(QUrl(":/assets/cover.png"));
        pulpo->deleteLater();
    });

    pulpo->request(request);
}
