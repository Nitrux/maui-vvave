/*
   SPDX-FileCopyrightText: 2019 (c) Matthieu Gallien <matthieu_gallien@yahoo.fr>

   SPDX-License-Identifier: LGPL-3.0-or-later
 */

#include "powermanagementinterface.h"

#include <KLocalizedString>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

#include <QString>
#include <QDebug>
#include <QGuiApplication>

namespace
{
bool sessionBusServiceAvailable(const QString &serviceName)
{
    auto *interface = QDBusConnection::sessionBus().interface();
    return interface && interface->isServiceRegistered(serviceName).value();
}
}

class PowerManagementInterfacePrivate
{
public:

    bool mPreventSleep = false;

    bool mInhibitedSleep = false;

    uint mInhibitSleepCookie = 0;

};

PowerManagementInterface::PowerManagementInterface(QObject *parent) : QObject(parent), d(std::make_unique<PowerManagementInterfacePrivate>())
{
    auto sessionBus = QDBusConnection::sessionBus();

    sessionBus.connect(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                       QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
                       QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                       QStringLiteral("HasInhibitChanged"), this, SLOT(hostSleepInhibitChanged()));
}

PowerManagementInterface::~PowerManagementInterface() = default;

bool PowerManagementInterface::preventSleep() const
{
    return d->mPreventSleep;
}

bool PowerManagementInterface::sleepInhibited() const
{
    return d->mInhibitedSleep;
}

void PowerManagementInterface::setPreventSleep(bool value)
{
    if (d->mPreventSleep == value) {
        return;
    }

    if (value) {
        inhibitSleepPlasmaWorkspace();
        inhibitSleepGnomeWorkspace();
        d->mPreventSleep = true;
    } else {
        uninhibitSleepPlasmaWorkspace();
        uninhibitSleepGnomeWorkspace();
        d->mPreventSleep = false;
    }

    Q_EMIT preventSleepChanged();
}

void PowerManagementInterface::retryInhibitingSleep()
{
    if (d->mPreventSleep && !d->mInhibitedSleep) {
        inhibitSleepPlasmaWorkspace();
        inhibitSleepGnomeWorkspace();
    }
}

void PowerManagementInterface::hostSleepInhibitChanged()
{
}

void PowerManagementInterface::inhibitDBusCallFinishedPlasmaWorkspace(QDBusPendingCallWatcher *aWatcher)
{
    QDBusPendingReply<uint> reply = *aWatcher;
    if (reply.isError()) {
    } else {
        d->mInhibitSleepCookie = reply.argumentAt<0>();
        d->mInhibitedSleep = true;

        Q_EMIT sleepInhibitedChanged();
    }
    aWatcher->deleteLater();
}

void PowerManagementInterface::uninhibitDBusCallFinishedPlasmaWorkspace(QDBusPendingCallWatcher *aWatcher)
{
    QDBusPendingReply<> reply = *aWatcher;
    if (reply.isError()) {
        qDebug() << "PowerManagementInterface::uninhibitDBusCallFinished" << reply.error();
    } else {
        d->mInhibitedSleep = false;

        Q_EMIT sleepInhibitedChanged();
    }
    aWatcher->deleteLater();
}

void PowerManagementInterface::inhibitDBusCallFinishedGnomeWorkspace(QDBusPendingCallWatcher *aWatcher)
{
    QDBusPendingReply<uint> reply = *aWatcher;
    if (reply.isError()) {
        qDebug() << "PowerManagementInterface::inhibitDBusCallFinishedGnomeWorkspace" << reply.error();
    } else {
        d->mInhibitSleepCookie = reply.argumentAt<0>();
        d->mInhibitedSleep = true;

        Q_EMIT sleepInhibitedChanged();
    }
    aWatcher->deleteLater();
}

void PowerManagementInterface::uninhibitDBusCallFinishedGnomeWorkspace(QDBusPendingCallWatcher *aWatcher)
{
    QDBusPendingReply<> reply = *aWatcher;
    if (reply.isError()) {
        qDebug() << "PowerManagementInterface::uninhibitDBusCallFinished" << reply.error();
    } else {
        d->mInhibitedSleep = false;

        Q_EMIT sleepInhibitedChanged();
    }
    aWatcher->deleteLater();
}

void PowerManagementInterface::inhibitSleepPlasmaWorkspace()
{
    if (!sessionBusServiceAvailable(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"))) {
        return;
    }

    auto sessionBus = QDBusConnection::sessionBus();

    auto inhibitCall = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                                                      QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
                                                      QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                                                      QStringLiteral("Inhibit"));

    inhibitCall.setArguments({{QGuiApplication::desktopFileName()}, {i18nc("explanation for sleep inhibit during play of music", "Playing music")}});

    auto asyncReply = sessionBus.asyncCall(inhibitCall);

    auto replyWatcher = new QDBusPendingCallWatcher(asyncReply, this);

    QObject::connect(replyWatcher, &QDBusPendingCallWatcher::finished,
                     this, &PowerManagementInterface::inhibitDBusCallFinishedPlasmaWorkspace);
}

void PowerManagementInterface::uninhibitSleepPlasmaWorkspace()
{
    if (!sessionBusServiceAvailable(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"))) {
        return;
    }

    auto sessionBus = QDBusConnection::sessionBus();

    auto uninhibitCall = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                                                      QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
                                                      QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                                                      QStringLiteral("UnInhibit"));

    uninhibitCall.setArguments({{d->mInhibitSleepCookie}});

    auto asyncReply = sessionBus.asyncCall(uninhibitCall);

    auto replyWatcher = new QDBusPendingCallWatcher(asyncReply, this);

    QObject::connect(replyWatcher, &QDBusPendingCallWatcher::finished,
                     this, &PowerManagementInterface::uninhibitDBusCallFinishedPlasmaWorkspace);
}

void PowerManagementInterface::inhibitSleepGnomeWorkspace()
{
    if (!sessionBusServiceAvailable(QStringLiteral("org.gnome.SessionManager"))) {
        return;
    }

    auto sessionBus = QDBusConnection::sessionBus();

    auto inhibitCall = QDBusMessage::createMethodCall(QStringLiteral("org.gnome.SessionManager"),
                                                      QStringLiteral("/org/gnome/SessionManager"),
                                                      QStringLiteral("org.gnome.SessionManager"),
                                                      QStringLiteral("Inhibit"));

    // See: https://gitlab.gnome.org/GNOME/gnome-session/-/blob/master/gnome-session/org.gnome.SessionManager.xml
    // The last argument are flag settings to specify what should be inhibited:
    //    1  = Inhibit logging out
    //    2  = Inhibit user switching
    //    4  = Inhibit suspending the session or computer
    //    8  = Inhibit the session being marked as idle
    //    16 = Inhibit auto-mounting removable media for the session
    inhibitCall.setArguments({{QCoreApplication::applicationName()}, {uint(0)},
                              {i18nc("explanation for sleep inhibit during play of music", "Playing music")}, {uint(12)}});

    auto asyncReply = sessionBus.asyncCall(inhibitCall);

    auto replyWatcher = new QDBusPendingCallWatcher(asyncReply, this);

    QObject::connect(replyWatcher, &QDBusPendingCallWatcher::finished,
                     this, &PowerManagementInterface::inhibitDBusCallFinishedGnomeWorkspace);
}

void PowerManagementInterface::uninhibitSleepGnomeWorkspace()
{
    if (!sessionBusServiceAvailable(QStringLiteral("org.gnome.SessionManager"))) {
        return;
    }

    auto sessionBus = QDBusConnection::sessionBus();

    auto uninhibitCall = QDBusMessage::createMethodCall(QStringLiteral("org.gnome.SessionManager"),
                                                        QStringLiteral("/org/gnome/SessionManager"),
                                                        QStringLiteral("org.gnome.SessionManager"),
                                                        QStringLiteral("UnInhibit"));

    uninhibitCall.setArguments({{d->mInhibitSleepCookie}});

    auto asyncReply = sessionBus.asyncCall(uninhibitCall);

    auto replyWatcher = new QDBusPendingCallWatcher(asyncReply, this);

    QObject::connect(replyWatcher, &QDBusPendingCallWatcher::finished,
                     this, &PowerManagementInterface::uninhibitDBusCallFinishedGnomeWorkspace);
}
