#include "lastfmService.h"

using namespace PULPO;

lastfm::lastfm()
{
    this->scope.insert(ONTOLOGY::ALBUM, {INFO::ARTWORK, INFO::WIKI, INFO::TAGS});
    this->scope.insert(ONTOLOGY::ARTIST, {INFO::WIKI, INFO::TAGS});
    this->scope.insert(ONTOLOGY::TRACK, {INFO::TAGS, INFO::WIKI, INFO::ARTWORK, INFO::METADATA});
    connect(this, &lastfm::arrayReady, this, &lastfm::parse);
}

lastfm::~lastfm()
{
    qDebug() << "DELETING LASTFM INSTANCE";
}

void lastfm::set(const PULPO::REQUEST &request)
{
    this->request = request;

    if (!scopePass()) {
        ERROR(this->request)
    }

    auto url = this->API;

    QUrl encodedArtist(this->request.track[FMH::MODEL_KEY::ARTIST]);
    encodedArtist.toEncoded(QUrl::FullyEncoded);

    switch (this->request.ontology) {
    case PULPO::ONTOLOGY::ARTIST: {
        url.append("?method=artist.getinfo");
        url.append(KEY);
        url.append("&artist=" + encodedArtist.toString());
        break;
    }

    case PULPO::ONTOLOGY::ALBUM: {
        QUrl encodedAlbum(this->request.track[FMH::MODEL_KEY::ALBUM]);
        encodedAlbum.toEncoded(QUrl::FullyEncoded);

        url.append("?method=album.getinfo");
        url.append(KEY);
        url.append("&artist=" + encodedArtist.toString());
        url.append("&album=" + encodedAlbum.toString());
        break;
    }

    case PULPO::ONTOLOGY::TRACK: {
        QUrl encodedTrack(this->request.track[FMH::MODEL_KEY::TITLE]);
        encodedTrack.toEncoded(QUrl::FullyEncoded);

        url.append("?method=track.getinfo");
        url.append(KEY);
        url.append("&artist=" + encodedArtist.toString());
        url.append("&track=" + encodedTrack.toString());
        url.append("&format=json");
        break;
    }
    }

    qDebug() << "[lastfm service]: " << url;

    this->retrieve(url);
}

void lastfm::parseArtist(const QByteArray &array)
{
    QString xmlData(array);
    QDomDocument doc;

    if (!doc.setContent(xmlData)) {
        qDebug() << "LASTFM XML FAILED 1" << this->request.track;
        ERROR(this->request);
    }

    if (doc.documentElement().toElement().attributes().namedItem("status").nodeValue() != "ok") {
        qDebug() << "LASTFM XML FAILED 2" << this->request.track;
        ERROR(this->request);
    }

    const QDomNodeList nodeList = doc.documentElement().namedItem("artist").childNodes();

    for (int i = 0; i < nodeList.count(); i++) {
        QDomNode n = nodeList.item(i);

        if (n.isElement()) {
            // Here retrieve the artist wiki (bio)
            if (this->request.info.contains(INFO::WIKI)) {
                if (n.nodeName() == "bio") {
                    auto artistWiki = n.childNodes().item(3).toElement().text();

                    this->responses << PULPO::RESPONSE{PULPO_CONTEXT::WIKI, artistWiki};
                }
            }
        }
    }

    Q_EMIT this->responseReady(this->request, this->responses);
}

void lastfm::parseAlbum(const QByteArray &array)
{
    QString xmlData(array);
    QDomDocument doc;

    if (!doc.setContent(xmlData)) {
        qDebug() << "LASTFM XML FAILED 1" << this->request.track;
        ERROR(this->request);
    }

    if (doc.documentElement().toElement().attributes().namedItem("status").nodeValue() != "ok") {
        qDebug() << "LASTFM XML FAILED 2" << this->request.track;
        ERROR(this->request);
    }

    const auto nodeList = doc.documentElement().namedItem("album").childNodes();

    for (int i = 0; i < nodeList.count(); i++) {
        QDomNode n = nodeList.item(i);

        if (n.isElement()) {
            // Here retrieve the artist image
            if (n.nodeName() == "image" && n.hasAttributes()) {
                if (this->request.info.contains(INFO::ARTWORK)) {
                    const auto imgSize = n.attributes().namedItem("size").nodeValue();

                    if (imgSize == "large" && n.isElement()) {
                        const auto albumArt_url = n.toElement().text();
                        this->responses << PULPO::RESPONSE{PULPO_CONTEXT::IMAGE, albumArt_url};

                        if (this->request.info.size() == 1)
                            break;
                        else
                            continue;

                    } else
                        continue;

                } else
                    continue;
            }

            if (n.nodeName() == "wiki") {
                if (this->request.info.contains(INFO::WIKI)) {
                    const auto albumWiki = n.childNodes().item(1).toElement().text();
                    // qDebug()<<"Fetching AlbumWiki LastFm[]";

                    this->responses << PULPO::RESPONSE{PULPO_CONTEXT::WIKI, albumWiki};

                    if (this->request.info.size() == 1)
                        break;
                    else
                        continue;

                } else
                    continue;
            }

            if (n.nodeName() == "tags") {
                if (this->request.info.contains(INFO::TAGS)) {
                    auto tagsList = n.toElement().childNodes();
                    QStringList albumTags;
                    for (int j = 0; j < tagsList.count(); j++) {
                        QDomNode m = tagsList.item(j);
                        albumTags << m.childNodes().item(0).toElement().text();
                    }

                    this->responses << PULPO::RESPONSE{PULPO_CONTEXT::TAG, albumTags};

                    if (this->request.info.size() == 1)
                        break;
                    else
                        continue;

                } else
                    continue;
            }
        }
    }

    Q_EMIT this->responseReady(this->request, this->responses);
}
