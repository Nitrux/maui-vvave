#include "player.h"

#include <MauiKit4/Audio/mediaplayer.h>
#include <QFileInfo>
#include <QProcessEnvironment>
#include <QTime>

#include "powermanagementinterface.h"

Player::Player(QObject *parent)
    : MediaPlayer(parent)
    , m_power(new PowerManagementInterface(this))

{
   connect(this, &MediaPlayer::stateChanged, [this]() {
       if (state() == MediaPlayer::Playing)
           this->m_power->setPreventSleep(true);
       else
           this->m_power->setPreventSleep(false);

       Q_EMIT this->playingChanged();
   });
}


QString Player::transformTime(int value)
{
    QString tStr;
    if (value) {
        QTime time((value / 3600) % 60, (value / 60) % 60, value % 60, (value * 1000) % 1000);
        QString format = "mm:ss";
        if (value > 3600)
            format = "hh:mm:ss";
        tStr = time.toString(format);
    }

    return tStr.isEmpty() ? "00:00" : tStr;
}

bool Player::getPlaying() const {
    return state() == MediaPlayer::Playing;
}

bool Player::isOutputLikelyAvailable(const QString &output) const
{
    const QString key = output.trimmed().toLower();
    if (key.isEmpty()) {
        return false;
    }

    const auto env = QProcessEnvironment::systemEnvironment();
    auto runtimeDir = env.value(QStringLiteral("PIPEWIRE_RUNTIME_DIR"));
    if (runtimeDir.isEmpty()) {
        runtimeDir = env.value(QStringLiteral("XDG_RUNTIME_DIR"));
    }
    if (runtimeDir.isEmpty()) {
        runtimeDir = env.value(QStringLiteral("USERPROFILE"));
    }

    auto existsInRuntime = [&runtimeDir](const QString &relativePath) -> bool {
        return !runtimeDir.isEmpty() && QFileInfo::exists(runtimeDir + relativePath);
    };

    if (key == QStringLiteral("pipewire")) {
        const auto remote = env.value(QStringLiteral("PIPEWIRE_REMOTE"), QStringLiteral("pipewire-0"));
        return existsInRuntime(QStringLiteral("/") + remote) || existsInRuntime(QStringLiteral("/pipewire-0"));
    }

    if (key == QStringLiteral("pulse") || key == QStringLiteral("pulseaudio")) {
        const auto pulseServer = env.value(QStringLiteral("PULSE_SERVER"));
        if (pulseServer.startsWith(QStringLiteral("unix:"))) {
            return QFileInfo::exists(pulseServer.mid(5));
        }
        return existsInRuntime(QStringLiteral("/pulse/native"));
    }

    if (key == QStringLiteral("jack")) {
        return existsInRuntime(QStringLiteral("/jack/default/jack_0"));
    }

    if (key == QStringLiteral("alsa")) {
        return QFileInfo::exists(QStringLiteral("/dev/snd"));
    }

    if (key == QStringLiteral("oss")) {
        return QFileInfo::exists(QStringLiteral("/dev/dsp"));
    }

    // For unknown backends, don't hide valid plugin choices.
    return true;
}
