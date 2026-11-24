/*
   SPDX-FileCopyrightText: 2019 (c) Matthieu Gallien <matthieu_gallien@yahoo.fr>

SPDX-License-Identifier: LGPL-3.0-or-later
*/

#pragma once

#include <QObject>
#include <QString>

#include <memory>

class QDBusPendingCallWatcher;
class PowerManagementInterfacePrivate;

class PowerManagementInterface : public QObject
{

    Q_OBJECT

    Q_PROPERTY(bool preventSleep
                   READ preventSleep
                       WRITE setPreventSleep
                           NOTIFY preventSleepChanged)

    Q_PROPERTY(bool sleepInhibited
                   READ sleepInhibited
                       NOTIFY sleepInhibitedChanged)

public:

    explicit PowerManagementInterface(QObject *parent = nullptr);

    ~PowerManagementInterface() override;

    [[nodiscard]] bool preventSleep() const;

    [[nodiscard]] bool sleepInhibited() const;

Q_SIGNALS:

    void preventSleepChanged();

    void sleepInhibitedChanged();

public Q_SLOTS:

    void setPreventSleep(bool value);

    void retryInhibitingSleep();

private Q_SLOTS:

    void inhibitCallFinished(QDBusPendingCallWatcher *watcher);

private:

    void requestInhibit();

    void closeRequest(const QString &handle);

    std::unique_ptr<PowerManagementInterfacePrivate> d;

};
