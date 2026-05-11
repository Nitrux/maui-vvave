#pragma once

#include <QObject>

#include <MauiKit4/Core/mauilist.h>

class AlbumsModel : public MauiList
{
    Q_OBJECT
    Q_PROPERTY(AlbumsModel::QUERY query READ getQuery WRITE setQuery NOTIFY queryChanged())
    Q_PROPERTY(bool autoPopulate READ autoPopulate WRITE setAutoPopulate NOTIFY autoPopulateChanged)

public:
    enum QUERY : uint_fast8_t { ARTISTS = FMH::MODEL_KEY::ARTIST, ALBUMS = FMH::MODEL_KEY::ALBUM };
    Q_ENUM(QUERY)

    explicit AlbumsModel(QObject *parent = nullptr);

    void componentComplete() override;

    const FMH::MODEL_LIST &items() const override;

    void setQuery(const AlbumsModel::QUERY &query);
    AlbumsModel::QUERY getQuery() const;
    bool autoPopulate() const;
    void setAutoPopulate(bool autoPopulate);

private:
    FMH::MODEL_LIST list;
    bool m_autoPopulate = true;
    bool m_componentCompleted = false;

    void setList();
    void reload(bool force = false);

    AlbumsModel::QUERY query = AlbumsModel::QUERY::ALBUMS;

public Q_SLOTS:
    void refresh();
    int indexOfName(const QString &query);

Q_SIGNALS:
    void queryChanged();
    void autoPopulateChanged(bool autoPopulate);
};
