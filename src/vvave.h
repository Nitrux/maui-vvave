#pragma once

#include <QColor>
#include <QObject>
#include <QStringList>

#include <MauiKit4/Core/fmh.h>

class vvave : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList sources READ sourcesModel NOTIFY sourcesChanged FINAL)
    Q_PROPERTY(QList<QUrl> folders READ folders NOTIFY sourcesChanged FINAL)
    Q_PROPERTY(bool fetchArtwork READ fetchArtwork WRITE setFetchArtwork NOTIFY fetchArtworkChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged FINAL)

public:
    explicit vvave(QObject *parent = nullptr);
    static vvave *instance();
    static FMH::MODEL_LIST localTracks();
    static FMH::MODEL_LIST albums();
    static FMH::MODEL_LIST artists();
    static FMH::MODEL_LIST tracksForTag(const QString &tag);
    static FMH::MODEL_LIST tracksFromQuery(const QString &query);

    bool fetchArtwork() const;

    QList<QUrl> folders();

    bool scanning() const;

public Q_SLOTS:
    void addSources(const QList<QUrl> &paths);
    bool removeSource(const QString &source);

    void scanDir(const QList<QUrl> &paths);
    void rescan();

    static QStringList sources();
    static QVariantList sourcesModel();

    void setFetchArtwork(bool fetchArtwork);
    static FMH::MODEL trackInfo(const QUrl &url);

    QString artworkUrl(const QString &artist, const QString &album);
    QColor artworkAccent(const QString &artist, const QString &album);

    /**
     * @brief Get tracks matching a lightweight query.
     * Supported forms:
     * - "vvave://all"
     * - "vvave://artist/<url-encoded-artist>"
     * - "vvave://album/<url-encoded-album>/<url-encoded-artist>"
     * - "#<tag>"
     */
    QVariantList getTracks(const QString &query);

private:
    bool m_fetchArtwork = false;
    bool m_scanning = false;

Q_SIGNALS:
    void sourceAdded(QUrl source);
    void sourceRemoved(QUrl source);

    void collectionChanged();
    void sourcesChanged();
    void fetchArtworkChanged(bool fetchArtwork);
    void scanningChanged(bool scanning);
};
