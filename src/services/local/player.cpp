#include "player.h"

#include <MauiKit4/Audio/mediaplayer.h>
#include <QTime>

#include "powermanagementinterface.h"

Player::Player(QObject *parent)
    : MediaPlayer(parent)
    , m_power(new PowerManagementInterface(this))

{
    auto vvave_preferredOutput = qgetenv("VVAVE_DEFAULT_OUTPUT");
    if(!vvave_preferredOutput.isEmpty())
        setPreferredOutput(QString::fromLocal8Bit(vvave_preferredOutput));

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
