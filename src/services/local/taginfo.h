#pragma once

#include <QObject>
#include <QString>

namespace TagLib
{
class FileRef;
}
class TagInfo : public QObject
{
    Q_OBJECT
public:
    TagInfo(const QString &url, QObject *parent = nullptr);
    TagInfo(QObject *parent = nullptr);

    ~TagInfo();
    bool isNull();
    QString getAlbum() const;
    QString getTitle() const;
    QString getArtist() const;
    int getTrack() const;
    QString getGenre() const;
    QString fileName() const;
    QString getComment() const;
    int getDuration() const;
    uint getYear() const;

    void setFile(const QString &url);
    void setAlbum(const QString &album);
    void setTitle(const QString &title);
    void setTrack(const int &track);
    void setYear(const int &year);
    void setArtist(const QString &artist);
    void setGenre(const QString &genre);
    void setComment(const QString &comment);

private:
    TagLib::FileRef *file = nullptr;
    QString path;
};
