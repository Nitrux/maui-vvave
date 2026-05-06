#include "playlistsmodel.h"

#include "vvave.h"

#include <MauiKit4/FileBrowsing/tagging.h>
#include <numeric>

PlaylistsModel::PlaylistsModel(QObject *parent)
    : MauiList(parent)
{
    m_tagging = Tagging::getInstance();

    connect(m_tagging, &Tagging::tagged, [this](QVariantMap tag) {
        Q_EMIT this->preItemAppended();
        this->list << this->packPlaylist(tag.value("tag").toString());
        Q_EMIT this->postItemAppended();
    });

    connect(m_tagging, &Tagging::urlTagged, [this](QString, QString tag) {
        const auto index = this->indexOf(FMH::MODEL_KEY::PLAYLIST, tag);
        if (index < 0 || index >= this->list.count()) {
            return;
        }

        auto item = this->list[index];
        item[FMH::MODEL_KEY::PREVIEW] = playlistArtworkPreviews(tag);
        this->list[index] = item;
        Q_EMIT this->updateModel(index, {});
    });
}

PlaylistsModel::~PlaylistsModel()
{
    m_tagging->disconnect();
    m_tagging = nullptr;
}

const FMH::MODEL_LIST &PlaylistsModel::items() const
{
    return this->list;
}

void PlaylistsModel::setList()
{
    Q_EMIT this->preListChanged();
    this->list = this->tags();
    Q_EMIT this->postListChanged();
}

FMH::MODEL PlaylistsModel::packPlaylist(const QString &playlist)
{
    return FMH::MODEL{{FMH::MODEL_KEY::KEY, playlist},
                      {FMH::MODEL_KEY::PLAYLIST, playlist},
                      {FMH::MODEL_KEY::ICON, "tag"},
                      {FMH::MODEL_KEY::TYPE, "personal"},
                      {FMH::MODEL_KEY::PREVIEW, playlistArtworkPreviews(playlist)}};
}

QString PlaylistsModel::playlistArtworkPreviews(const QString &playlist)
{
    QStringList previews;
    const auto urls = Tagging::getInstance()->getTagUrls(playlist, {}, true, 4, "audio");

    for (const auto &url : urls) {
        const auto track = vvave::trackInfo(url);
        if (track.isEmpty()) {
            continue;
        }

        previews << QString("image://artwork/album:%1:%2").arg(track[FMH::MODEL_KEY::ARTIST], track[FMH::MODEL_KEY::ALBUM]);
    }

    return previews.join(",");
}

FMH::MODEL_LIST PlaylistsModel::tags()
{
    FMH::MODEL_LIST res;
    const auto tags = Tagging::getInstance()->getUrlsTags(true);

    return std::accumulate(tags.constBegin(), tags.constEnd(), res, [this](FMH::MODEL_LIST &list, const QVariant &item) {
        const auto map = item.toMap();
        auto packed = packPlaylist(map.value("tag").toString());
        packed[FMH::MODEL_KEY::ICON] = map.value("icon").toString();

        if (list.count() < m_limit) {
            list << packed;
        }

        return list;
    });
}

void PlaylistsModel::insert(const QString &playlist)
{
    if (playlist.isEmpty())
        return;

    Tagging::getInstance()->tag(playlist);
}

void PlaylistsModel::addTrack(const QString &playlist, const QStringList &urls)
{
    for (const auto &url : urls)
        Tagging::getInstance()->tagUrl(url, playlist);
}

void PlaylistsModel::removeTrack(const QString &playlist, const QString &url)
{
    Tagging::getInstance()->removeUrlTag(url, playlist);
}

void PlaylistsModel::removePlaylist(const int &index)
{
    if (index >= this->list.size() || index < 0) {
        return;
    }

    if (Tagging::getInstance()->removeTag(this->list.at(index)[FMH::MODEL_KEY::PLAYLIST], true)) {
        Q_EMIT this->preItemRemoved(index);
        this->list.removeAt(index);
        Q_EMIT this->postItemRemoved();
    }
}

void PlaylistsModel::componentComplete()
{
    this->setList();
}

int PlaylistsModel::limit() const
{
    return m_limit;
}

void PlaylistsModel::setLimit(int newLimit)
{
    if (m_limit == newLimit)
        return;

    m_limit = newLimit;
    Q_EMIT limitChanged();
}
