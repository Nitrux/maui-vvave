#include "albumsmodel.h"

#include "vvave.h"

#include <algorithm>
#include <QSet>

AlbumsModel::AlbumsModel(QObject *parent)
    : MauiList(parent)
{
    qRegisterMetaType<FMH::MODEL_LIST>("FMH::MODEL_LIST");
    qRegisterMetaType<FMH::MODEL>("FMH::MODEL");
}

void AlbumsModel::componentComplete()
{
    connect(vvave::instance(), &vvave::sourceRemoved, this, &AlbumsModel::setList);
    connect(vvave::instance(), &vvave::sourceAdded, this, &AlbumsModel::setList);
    connect(this, &AlbumsModel::queryChanged, this, &AlbumsModel::setList);
    setList();
}

const FMH::MODEL_LIST &AlbumsModel::items() const
{
    return this->list;
}

void AlbumsModel::setQuery(const QUERY &query)
{
    if (this->query == query)
        return;

    this->query = query;
    Q_EMIT this->queryChanged();
}

AlbumsModel::QUERY AlbumsModel::getQuery() const
{
    return this->query;
}

void AlbumsModel::setList()
{
    Q_EMIT this->preListChanged();
    this->list.clear();

    const auto tracks = vvave::localTracks();

    if (this->query == AlbumsModel::QUERY::ALBUMS) {
        QSet<QString> seen;
        for (const auto &track : tracks) {
            const auto album = track[FMH::MODEL_KEY::ALBUM];
            const auto artist = track[FMH::MODEL_KEY::ARTIST];

            const auto key = album + QStringLiteral("\x1f") + artist;
            if (album.isEmpty() || artist.isEmpty() || seen.contains(key)) {
                continue;
            }

            seen.insert(key);
            this->list << FMH::MODEL{{FMH::MODEL_KEY::ALBUM, album}, {FMH::MODEL_KEY::ARTIST, artist}};
        }

    } else if (this->query == AlbumsModel::QUERY::ARTISTS) {
        QSet<QString> seen;
        for (const auto &track : tracks) {
            const auto artist = track[FMH::MODEL_KEY::ARTIST];
            if (artist.isEmpty() || seen.contains(artist)) {
                continue;
            }

            seen.insert(artist);
            this->list << FMH::MODEL{{FMH::MODEL_KEY::ARTIST, artist}};
        }
    }

    std::sort(this->list.begin(), this->list.end(), [this](const FMH::MODEL &a, const FMH::MODEL &b) {
        const auto key = this->query == AlbumsModel::QUERY::ALBUMS ? FMH::MODEL_KEY::ALBUM : FMH::MODEL_KEY::ARTIST;
        return a[key].compare(b[key], Qt::CaseInsensitive) < 0;
    });

    Q_EMIT this->postListChanged();
    Q_EMIT this->countChanged();
}

void AlbumsModel::refresh()
{
    this->setList();
}

int AlbumsModel::indexOfName(const QString &query)
{
    const auto it = std::find_if(this->items().constBegin(), this->items().constEnd(), [&](const FMH::MODEL &item) -> bool {
        return item[this->query == AlbumsModel::QUERY::ALBUMS ? FMH::MODEL_KEY::ALBUM : FMH::MODEL_KEY::ARTIST].startsWith(query, Qt::CaseInsensitive);
    });

    if (it != this->items().constEnd())
        return (std::distance(this->items().constBegin(), it));
    else
        return -1;
}
