/*
   SPDX-FileCopyrightText: 2019 (c) Matthieu Gallien <matthieu_gallien@yahoo.fr>

   SPDX-License-Identifier: LGPL-3.0-or-later
 */

#include "powermanagementinterface.h"

#include <KLocalizedString>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>
#include <QVariantMap>

#include <utility>

namespace
{
constexpr auto PortalService = "org.freedesktop.portal.Desktop";
constexpr auto PortalPath = "/org/freedesktop/portal/desktop";
constexpr auto InhibitInterface = "org.freedesktop.portal.Inhibit";
constexpr auto RequestInterface = "org.freedesktop.portal.Request";
}

class PowerManagementInterfacePrivate
{
public:
    bool mPreventSleep = false;
    bool mInhibitedSleep = false;
    bool mInhibitPending = false;
    QString mRequestHandle;
};

PowerManagementInterface::PowerManagementInterface(QObject *parent)
    : QObject(parent)
    , d(std::make_unique<PowerManagementInterfacePrivate>())
{
}

PowerManagementInterface::~PowerManagementInterface()
{
    if (!d->mRequestHandle.isEmpty())
        closeRequest(d->mRequestHandle);
}

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
    if (d->mPreventSleep == value)
        return;

    d->mPreventSleep = value;
    Q_EMIT preventSleepChanged();

    if (value) {
        requestInhibit();
    } else {
        if (!d->mRequestHandle.isEmpty()) {
            const auto handle = std::exchange(d->mRequestHandle, QString{});
            closeRequest(handle);
        }

        if (d->mInhibitedSleep) {
            d->mInhibitedSleep = false;
            Q_EMIT sleepInhibitedChanged();
        }
    }
}

void PowerManagementInterface::retryInhibitingSleep()
{
    if (d->mPreventSleep && !d->mInhibitedSleep && !d->mInhibitPending)
        requestInhibit();
}

void PowerManagementInterface::inhibitCallFinished(QDBusPendingCallWatcher *watcher)
{
    const QDBusPendingReply<QDBusObjectPath> reply = *watcher;
    watcher->deleteLater();
    d->mInhibitPending = false;

    if (reply.isError()) {
        qWarning() << "Could not acquire portal inhibition:" << reply.error().message();
        return;
    }

    const auto handle = reply.value().path();
    if (handle.isEmpty()) {
        qWarning() << "Portal returned an empty inhibition handle";
        return;
    }

    if (!d->mPreventSleep) {
        closeRequest(handle);
        return;
    }

    d->mRequestHandle = handle;
    d->mInhibitedSleep = true;
    Q_EMIT sleepInhibitedChanged();
}

void PowerManagementInterface::requestInhibit()
{
    if (d->mInhibitPending || !d->mRequestHandle.isEmpty())
        return;

    auto call = QDBusMessage::createMethodCall(
        QString::fromLatin1(PortalService), QString::fromLatin1(PortalPath),
        QString::fromLatin1(InhibitInterface), QStringLiteral("Inhibit"));
    call.setArguments({QString{}, uint(12),
                       QVariantMap{{QStringLiteral("reason"),
                                    i18nc("explanation for sleep inhibit during play of music", "Playing music")}}});

    d->mInhibitPending = true;
    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished,
            this, &PowerManagementInterface::inhibitCallFinished);
}

void PowerManagementInterface::closeRequest(const QString &handle)
{
    auto call = QDBusMessage::createMethodCall(
        QString::fromLatin1(PortalService), handle,
        QString::fromLatin1(RequestInterface), QStringLiteral("Close"));
    QDBusConnection::sessionBus().asyncCall(call);
}
