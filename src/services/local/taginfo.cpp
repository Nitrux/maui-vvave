/*
   Vvave - tiny music player
   Copyright (C) 2017  Camilo Higuita
   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3 of the License, or
   (at your option) any later version.
   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software Foundation,
   Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

 */

#include "taginfo.h"
#include "../../utils/bae.h"

#include <QFile>
#include <QMimeDatabase>
#include <QUrl>

#include <taglib/fileref.h>
#include <taglib/tag.h>
#include <taglib/taglib.h>
#include <taglib/tvariant.h>

using namespace BAE;

TagInfo::TagInfo(const QString &url, QObject *parent)
    : QObject(parent)
{
    this->setFile(url);
}

TagInfo::TagInfo(QObject *parent)
    : QObject(parent)
{}

TagInfo::~TagInfo()
{
    delete this->file;
}

bool TagInfo::isNull() const
{
    return !this->file || this->file->isNull() || !this->file->tag();
}

QString TagInfo::getAlbum() const
{
    if (isNull()) {
        return SLANG[W::UNKNOWN];
    }

    const auto value = QString::fromStdWString(file->tag()->album().toWString());
    return !value.isEmpty() ? value : SLANG[W::UNKNOWN];
}

QString TagInfo::getTitle() const
{
    if (isNull()) {
        return fileName();
    }

    const auto value = QString::fromStdWString(file->tag()->title().toWString());
    return !value.isEmpty() ? value : fileName();
}

QString TagInfo::getArtist() const
{
    if (isNull()) {
        return SLANG[W::UNKNOWN];
    }

    const auto value = QString::fromStdWString(file->tag()->artist().toWString());
    return !value.isEmpty() ? value : SLANG[W::UNKNOWN];
}

int TagInfo::getTrack() const
{
    return isNull() ? 0 : static_cast<signed int>(file->tag()->track());
}

QString TagInfo::getGenre() const
{
    if (isNull()) {
        return SLANG[W::UNKNOWN];
    }

    const auto value = QString::fromStdWString(file->tag()->genre().toWString());
    return !value.isEmpty() ? value : SLANG[W::UNKNOWN];
}

QString TagInfo::fileName() const
{
    return QFileInfo(path).fileName();
}

uint TagInfo::getYear() const
{
    return isNull() ? 0 : file->tag()->year();
}

void TagInfo::setFile(const QString &url)
{
    this->path = url;
    QFileInfo _file(this->path);

    delete this->file;
    this->file = nullptr;

    if (_file.isReadable() && _file.exists()) {
        this->file = new TagLib::FileRef(TagLib::FileName(path.toUtf8()));
    } else {
        this->file = new TagLib::FileRef();
    }
}

int TagInfo::getDuration() const
{
    if (isNull()) {
        return 0;
    }

    const auto properties = file->audioProperties();
    if (!properties)
        return 0;

#if TAGLIB_MAJOR_VERSION >= 2
    return properties->lengthInSeconds();
#else
    return properties->length();
#endif
}

QString TagInfo::getArtwork() const
{
    if (isNull())
        return QString();

    const auto pictures = file->complexProperties("PICTURE");
    if (pictures.isEmpty())
        return QString();

    const TagLib::VariantMap *selectedPicture = &pictures.front();
    for (const auto &picture : pictures) {
        if (picture.value("pictureType").toString() == TagLib::String("Front Cover")) {
            selectedPicture = &picture;
            break;
        }
    }

    const auto bytes = selectedPicture->value("data").toByteVector();
    if (bytes.isEmpty())
        return QString();

    QByteArray imageData(bytes.data(), static_cast<qsizetype>(bytes.size()));
    auto mimeType = QString::fromStdString(selectedPicture->value("mimeType").toString().to8Bit(true));
    if (mimeType.isEmpty())
        mimeType = QMimeDatabase().mimeTypeForData(imageData).name();
    if (mimeType.isEmpty())
        return QString();

    return QStringLiteral("data:") + mimeType + QStringLiteral(";base64,")
           + QString::fromLatin1(imageData.toBase64());
}

QString TagInfo::getComment() const
{
    if (isNull()) {
        return SLANG[W::UNKNOWN];
    }

    const auto value = QString::fromStdWString(file->tag()->comment().toWString());
    return !value.isEmpty() ? value : SLANG[W::UNKNOWN];
}

void TagInfo::setComment(const QString &comment)
{
    if (isNull()) {
        return;
    }

    this->file->tag()->setComment(comment.toStdString());
    this->file->save();
}

void TagInfo::setAlbum(const QString &album)
{
    if (isNull()) {
        return;
    }

    this->file->tag()->setAlbum(album.toStdString());
    this->file->save();
}

void TagInfo::setTitle(const QString &title)
{
    if (isNull()) {
        return;
    }

    this->file->tag()->setTitle(title.toStdString());
    this->file->save();
}

void TagInfo::setTrack(const int &track)
{
    if (isNull()) {
        return;
    }

    this->file->tag()->setTrack(static_cast<unsigned int>(track));
    this->file->save();
}

void TagInfo::setYear(const int &year)
{
    if (isNull()) {
        return;
    }

    this->file->tag()->setYear(static_cast<unsigned int>(year));
    this->file->save();
}

void TagInfo::setArtist(const QString &artist)
{
    if (isNull()) {
        return;
    }

    this->file->tag()->setArtist(artist.toStdString());
    this->file->save();
}

void TagInfo::setGenre(const QString &genre)
{
    if (isNull()) {
        return;
    }

    this->file->tag()->setGenre(genre.toStdString());
    this->file->save();
}


bool TagInfo::updateMetadata(const QVariantMap &data)
{

    if (isNull()) {
        return false;
    }

    auto *tag = file->tag();
    tag->setTitle(TagLib::String(data.value(QStringLiteral("title")).toString().toStdWString()));
    tag->setArtist(TagLib::String(data.value(QStringLiteral("artist")).toString().toStdWString()));
    tag->setAlbum(TagLib::String(data.value(QStringLiteral("album")).toString().toStdWString()));
    tag->setTrack(data.value(QStringLiteral("track")).toUInt());
    tag->setGenre(TagLib::String(data.value(QStringLiteral("genre")).toString().toStdWString()));
    tag->setYear(data.value(QStringLiteral("releasedate")).toUInt());
    tag->setComment(TagLib::String(data.value(QStringLiteral("comment")).toString().toStdWString()));

    const auto artworkAction = data.value(QStringLiteral("artworkAction"), QStringLiteral("keep")).toString();
    if (artworkAction == QStringLiteral("replace")) {
        const auto artworkValue = data.value(QStringLiteral("artworkUrl")).toString();
        const QUrl artworkUrl(artworkValue);
        const QString artworkPath = artworkUrl.isLocalFile() ? artworkUrl.toLocalFile() : artworkValue;
        QFile artworkFile(artworkPath);
        if (!artworkFile.open(QIODevice::ReadOnly)) {
            return false;
        }

        const auto imageData = artworkFile.readAll();
        const auto mimeType = QMimeDatabase().mimeTypeForData(imageData).name();
        if (mimeType != QStringLiteral("image/jpeg") && mimeType != QStringLiteral("image/png")) {
            return false;
        }

        TagLib::VariantMap picture;
        picture.insert("data", TagLib::ByteVector(imageData.constData(), static_cast<unsigned int>(imageData.size())));
        picture.insert("description", TagLib::String("Album artwork"));
        picture.insert("pictureType", TagLib::String("Front Cover"));
        picture.insert("mimeType", TagLib::String(mimeType.toStdString()));

        TagLib::List<TagLib::VariantMap> pictures;
        pictures.append(picture);
        if (!file->setComplexProperties("PICTURE", pictures)) {
            return false;
        }
    } else if (artworkAction == QStringLiteral("remove")) {
        if (!file->setComplexProperties("PICTURE", {})) {
            return false;
        }
    }

    const bool saved = file->save();
    return saved;
}
