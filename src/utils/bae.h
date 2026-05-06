#ifndef BAE_H
#define BAE_H

#include <QDirIterator>
#include <QFileInfo>
#include <QStandardPaths>
#include <QString>

#include <MauiKit4/Core/fmh.h>

namespace BAE
{
enum class W : uint_fast8_t { UNKNOWN };

static const QMap<W, QString> SLANG = {{W::UNKNOWN, "UNKNOWN"}};

const static QUrl CachePath = QUrl::fromLocalFile(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + "/vvave/");

static inline void fixArtworkImageFileName(QString &title)
{
    title.replace("/", "_");
    title.replace(".", "_");
    title.replace("+", "_");
    title.replace("&", "_");
}

static inline bool artworkCache(FMH::MODEL &track, const FMH::MODEL_KEY &type = FMH::MODEL_KEY::ID)
{
    QDirIterator it(CachePath.toLocalFile(), QDir::Files, QDirIterator::NoIteratorFlags);
    while (it.hasNext()) {
        const auto file = QUrl::fromLocalFile(it.next());
        const auto fileName = QFileInfo(file.toLocalFile()).baseName();
        switch (type) {
        case FMH::MODEL_KEY::ALBUM: {
            QString name = track[FMH::MODEL_KEY::ARTIST] + "_" + track[FMH::MODEL_KEY::ALBUM];
            fixArtworkImageFileName(name);

            if (fileName == name) {
                track.insert(FMH::MODEL_KEY::ARTWORK, file.toString());
                return true;
            }

            continue;
        }

        case FMH::MODEL_KEY::ARTIST: {
            auto name = track[FMH::MODEL_KEY::ARTIST];
            fixArtworkImageFileName(name);

            if (fileName == name) {
                track.insert(FMH::MODEL_KEY::ARTWORK, file.toString());
                return true;
            }

            continue;
        }
        default:
            break;
        }
    }

    return false;
}
}

#endif // BAE_H
