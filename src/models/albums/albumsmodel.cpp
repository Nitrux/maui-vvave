#include "albumsmodel.h"

#include "vvave.h"

#include <algorithm>

AlbumsModel::AlbumsModel(QObject *parent)
    : MauiList(parent)
{
    qRegisterMetaType<FMH::MODEL_LIST>("FMH::MODEL_LIST");
    qRegisterMetaType<FMH::MODEL>("FMH::MODEL");
}

void AlbumsModel::componentComplete()
{
    m_componentCompleted = true;
    connect(vvave::instance(), &vvave::collectionChanged, this, &AlbumsModel::setList);
    connect(this, &AlbumsModel::queryChanged, this, &AlbumsModel::setList);
    if (m_autoPopulate) {
        reload(true);
    }
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

bool AlbumsModel::autoPopulate() const
{
    return m_autoPopulate;
}

void AlbumsModel::setAutoPopulate(bool autoPopulate)
{
    if (m_autoPopulate == autoPopulate) {
        return;
    }

    m_autoPopulate = autoPopulate;
    Q_EMIT autoPopulateChanged(m_autoPopulate);

    if (m_componentCompleted && m_autoPopulate) {
        reload(true);
    }
}

void AlbumsModel::setList()
{
    reload(false);
}

void AlbumsModel::reload(bool force)
{
    if (!force && !m_autoPopulate) {
        return;
    }

    Q_EMIT this->preListChanged();
    this->list.clear();

    if (this->query == AlbumsModel::QUERY::ALBUMS) {
        this->list = vvave::albums();
    } else if (this->query == AlbumsModel::QUERY::ARTISTS) {
        this->list = vvave::artists();
    }

    Q_EMIT this->postListChanged();
    Q_EMIT this->countChanged();
}

void AlbumsModel::refresh()
{
    this->reload(true);
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
