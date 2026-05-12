#pragma once

#include "../service.h"
#include <QObject>

class spotify : public Service
{
    Q_OBJECT

private:
    inline static const QString API = "https://api.spotify.com/v1/search?q=";
    inline static constexpr const char *CLIENT_ID_ENV = "VVAVE_SPOTIFY_CLIENT_ID";
    inline static constexpr const char *CLIENT_SECRET_ENV = "VVAVE_SPOTIFY_CLIENT_SECRET";

public:
    explicit spotify();
    void set(const PULPO::REQUEST &request) override final;

protected:
    virtual void parseArtist(const QByteArray &array) override final;
    virtual void parseAlbum(const QByteArray &array) override final;
    virtual void parseTrack(const QByteArray &array) override final;
};
