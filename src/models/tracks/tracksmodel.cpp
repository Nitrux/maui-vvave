#include "tracksmodel.h"

#include "services/local/metadataeditor.h"
#include "utils/bae.h"
#include "vvave.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QUrl>

#include <MauiKit4/FileBrowsing/tagging.h>

namespace
{
QString artworkCacheBase(const QString &artist, const QString &album)
{
    QString name = artist + QStringLiteral("_") + album;
    BAE::fixArtworkImageFileName(name);
    return name;
}

void removeCachedAlbumArtwork(const QString &artist, const QString &album)
{
    if (artist.isEmpty() || album.isEmpty())
        return;

    const auto baseName = artworkCacheBase(artist, album);
    QDir cacheDir(BAE::CachePath.toLocalFile());
    const auto entries = cacheDir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
    for (const auto &entry : entries) {
        const auto entryBaseName = entry.completeBaseName();
        if (entryBaseName == baseName || entryBaseName == baseName + QStringLiteral("_highres"))
            QFile::remove(entry.absoluteFilePath());
    }
}

QString cacheAlbumArtwork(const QString &sourceValue, const QString &artist, const QString &album)
{
    const QUrl sourceUrl(sourceValue);
    const QString sourcePath = sourceUrl.isLocalFile() ? sourceUrl.toLocalFile() : sourceValue;
    const QFileInfo sourceInfo(sourcePath);
    if (!sourceInfo.exists() || !sourceInfo.isFile() || artist.isEmpty() || album.isEmpty())
        return QString();

    auto extension = sourceInfo.suffix().toLower();
    if (extension == QStringLiteral("jpeg"))
        extension = QStringLiteral("jpg");
    if (extension != QStringLiteral("jpg") && extension != QStringLiteral("png"))
        return QString();

    QDir cacheDir(BAE::CachePath.toLocalFile());
    if (!cacheDir.exists() && !cacheDir.mkpath(QStringLiteral(".")))
        return QString();

    QFile sourceFile(sourcePath);
    if (!sourceFile.open(QIODevice::ReadOnly))
        return QString();
    const auto imageData = sourceFile.readAll();
    sourceFile.close();
    if (imageData.isEmpty())
        return QString();

    const auto baseName = artworkCacheBase(artist, album);
    const auto cachedPath = cacheDir.filePath(baseName + QStringLiteral(".") + extension);
    const auto highResolutionPath = cacheDir.filePath(baseName + QStringLiteral("_highres.") + extension);

    removeCachedAlbumArtwork(artist, album);

    QSaveFile cachedFile(cachedPath);
    if (!cachedFile.open(QIODevice::WriteOnly)
            || cachedFile.write(imageData) != imageData.size()
            || !cachedFile.commit())
        return QString();

    QSaveFile highResolutionFile(highResolutionPath);
    if (highResolutionFile.open(QIODevice::WriteOnly)
            && highResolutionFile.write(imageData) == imageData.size())
        highResolutionFile.commit();

    return cachedPath;
}
}

TracksModel::TracksModel(QObject *parent)
    : MauiList(parent)
{
    qRegisterMetaType<TracksModel *>("const TracksModel*");
}

void TracksModel::componentComplete()
{
    m_componentCompleted = true;
    connect(this, &TracksModel::queryChanged, this, &TracksModel::setList);
    connect(vvave::instance(), &vvave::collectionChanged, this, &TracksModel::setList);
    connect(vvave::instance(), &vvave::trackMetadataChanged, this, &TracksModel::syncTrackMetadata);
    if (m_autoPopulate) {
        reload(true);
    }
}

const FMH::MODEL_LIST &TracksModel::items() const
{
    return this->list;
}

void TracksModel::setQuery(const QString &query)
{
    if (this->query == query) {
        return;
    }

    this->query = query;
    Q_EMIT this->queryChanged();
}

QString TracksModel::getQuery() const
{
    return this->query;
}

int TracksModel::limit() const
{
    return m_limit;
}

void TracksModel::setList()
{
    reload(false);
}

void TracksModel::syncTrackMetadata(const QVariantMap &data)
{
    const QUrl targetUrl(data.value(QStringLiteral("url")).toString());
    if (targetUrl.isEmpty()) {
        return;
    }

    for (int index = 0; index < this->list.size(); ++index) {
        if (QUrl(this->list.at(index).value(FMH::MODEL_KEY::URL)) == targetUrl) {
            this->update(data, index);
        }
    }
}

void TracksModel::reload(bool force)
{
    if (!force && !m_autoPopulate) {
        return;
    }

    Q_EMIT this->preListChanged();
    this->list.clear();

    const auto effectiveQuery = query.isEmpty() ? QStringLiteral("vvave://all") : query;
    auto data = vvave::tracksFromQuery(effectiveQuery);

    if (m_limit > 0 && data.count() > m_limit) {
        data = data.mid(0, m_limit);
    }

    this->list = data;

    Q_EMIT this->postListChanged();
    Q_EMIT this->countChanged();
}

bool TracksModel::append(const QVariantMap &item)
{
    if (item.isEmpty())
        return false;

    Q_EMIT this->preItemAppended();
    this->list << FMH::toModel(item);
    Q_EMIT this->postItemAppended();
    Q_EMIT this->countChanged();

    return true;
}

bool TracksModel::appendUrl(const QUrl &url)
{
    return append(FMH::toMap(vvave::trackInfo(url)));
}

bool TracksModel::insertUrl(const QString &url, const int &index)
{
    return appendAt(FMH::toMap(vvave::trackInfo(QUrl(url))), index);
}

bool TracksModel::insertUrls(const QStringList &urls, const int &index)
{
    if (urls.isEmpty()) {
        return false;
    }

    int inserted = 0;
    for (const auto &url : urls) {
        if (this->insertUrl(url, index + inserted)) {
            inserted++;
        }
    }

    return inserted > 0;
}

bool TracksModel::appendUrls(const QStringList &urls)
{
    bool inserted = false;
    for (const auto &url : QUrl::fromStringList(urls)) {
        inserted = this->appendUrl(url) || inserted;
    }

    return inserted;
}

bool TracksModel::appendAt(const QVariantMap &item, const int &at)
{
    if (item.isEmpty())
        return false;

    if (at > this->list.size() || at < 0)
        return false;

    Q_EMIT this->preItemAppendedAt(at);
    this->list.insert(at, FMH::toModel(item));
    Q_EMIT this->postItemAppended();
    Q_EMIT this->countChanged();
    return true;
}

bool TracksModel::appendQuery(const QString &query)
{
    const auto queryData = vvave::tracksFromQuery(query);
    if (queryData.isEmpty()) {
        return false;
    }

    Q_EMIT this->preItemsAppended(queryData.count());
    this->list << queryData;
    Q_EMIT this->postItemAppended();
    Q_EMIT this->countChanged();
    return true;
}

void TracksModel::copy(const TracksModel *list)
{
    if (!list) {
        return;
    }

    Q_EMIT this->preItemsAppended(list->getCount());
    this->list << list->items();
    Q_EMIT this->postItemAppended();
    Q_EMIT this->countChanged();
}

void TracksModel::clear()
{
    Q_EMIT this->preListChanged();
    this->list.clear();
    Q_EMIT this->postListChanged();
    Q_EMIT this->countChanged();
}

bool TracksModel::fav(const int &index, const bool &value)
{
    if (index >= this->list.size() || index < 0)
        return false;

    auto item = this->list[index];

    if (value)
        Tagging::getInstance()->fav(QUrl(item[FMH::MODEL_KEY::URL]));
    else
        Tagging::getInstance()->unFav(QUrl(item[FMH::MODEL_KEY::URL]));

    return true;
}

bool TracksModel::countUp(const int &index)
{
    if (index >= this->list.size() || index < 0) {
        return false;
    }

    auto item = this->list[index];
    const auto nextCount = item[FMH::MODEL_KEY::COUNT].toInt() + 1;
    this->list[index][FMH::MODEL_KEY::COUNT] = QString::number(nextCount);
    Q_EMIT this->updateModel(index, {FMH::MODEL_KEY::COUNT});
    return true;
}

bool TracksModel::remove(const int &index)
{
    if (index >= this->list.size() || index < 0)
        return false;

    Q_EMIT this->preItemRemoved(index);
    this->list.removeAt(index);
    Q_EMIT this->postItemRemoved();

    return true;
}

bool TracksModel::erase(const int &index)
{
    return remove(index);
}

bool TracksModel::removeMissing(const int &index)
{
    return erase(index);
}

void TracksModel::refresh()
{
    this->reload(true);
}

bool TracksModel::update(const QVariantMap &data, const int &index)
{
    if (index >= this->list.size() || index < 0)
        return false;

    auto newData = this->list[index];
    QVector<int> roles;
    const auto keys = data.keys();
    for (const auto &key : keys) {
        if (newData[FMH::MODEL_NAME_KEY[key]] != data[key].toString()) {
            newData.insert(FMH::MODEL_NAME_KEY[key], data[key].toString());
            roles << FMH::MODEL_NAME_KEY[key];
        }
    }

    this->list[index] = newData;
    Q_EMIT this->updateModel(index, roles);
    return true;
}

bool TracksModel::updateMetadata(const QVariantMap &data, const int &index)
{
    if (index < 0 || index >= this->list.size()) {
        return false;
    }

    QVariantMap modelData = data;
    modelData.remove(QStringLiteral("artworkAction"));
    modelData.remove(QStringLiteral("artworkUrl"));
    const auto model = FMH::toModel(modelData);
    const QUrl url(model[FMH::MODEL_KEY::URL]);
    if (!url.isLocalFile() || url.toLocalFile().isEmpty()) {
        return false;
    }

    MetadataEditor editor;
    editor.setUrl(url);
    if (!editor.save(data)) {
        return false;
    }

    const auto previous = this->list.at(index);
    const auto artworkAction = data.value(QStringLiteral("artworkAction"), QStringLiteral("keep")).toString();
    const auto artist = model[FMH::MODEL_KEY::ARTIST];
    const auto album = model[FMH::MODEL_KEY::ALBUM];

    if (artworkAction == QStringLiteral("replace")) {
        removeCachedAlbumArtwork(previous[FMH::MODEL_KEY::ARTIST], previous[FMH::MODEL_KEY::ALBUM]);
        const auto cachedPath = cacheAlbumArtwork(data.value(QStringLiteral("artworkUrl")).toString(), artist, album);
        modelData.insert(QStringLiteral("artwork"), cachedPath.isEmpty()
                         ? data.value(QStringLiteral("artworkUrl")).toString()
                         : QUrl::fromLocalFile(cachedPath).toString());
    } else if (artworkAction == QStringLiteral("remove")) {
        removeCachedAlbumArtwork(previous[FMH::MODEL_KEY::ARTIST], previous[FMH::MODEL_KEY::ALBUM]);
        removeCachedAlbumArtwork(artist, album);
        modelData.insert(QStringLiteral("artwork"), QString());
    }

    if (!this->update(modelData, index)) {
        return false;
    }
    vvave::updateTrackMetadata(modelData);
    return true;
}

bool TracksModel::move(const int &index, const int &to)
{
    if (index >= this->list.size() || index < 0)
        return false;

    if (to >= this->list.size() || to < 0)
        return false;

    this->list.move(index, to);
    Q_EMIT this->itemMoved(index, to);
    return true;
}

QStringList TracksModel::urls() const
{
    return FMH::modelToList(this->list, FMH::MODEL_KEY::URL);
}

void TracksModel::setLimit(int limit)
{
    if (m_limit == limit)
        return;

    m_limit = limit;
    Q_EMIT limitChanged(m_limit);

    if (m_componentCompleted && m_autoPopulate) {
        reload(true);
    }
}

bool TracksModel::autoPopulate() const
{
    return m_autoPopulate;
}

void TracksModel::setAutoPopulate(bool autoPopulate)
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
