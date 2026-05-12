#pragma once
#include <QObject>
#include <QList>
#include <QPair>
#include <QSharedPointer>
#include <QStringList>
#include <QUrl>
#include <QVector>

class OrgKdeVvaveActionsInterface;

namespace AppInstance
{
QVector<QPair<QSharedPointer<OrgKdeVvaveActionsInterface>, QStringList>> appInstances(const QString& preferredService);

bool attachToExistingInstance(const QList<QUrl>& inputUrls, const QString& preferredService = QString());

bool registerService();
}

class Server : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.vvave.Actions")

public:
    explicit Server(QObject *parent = nullptr);
    void setQmlObject(QObject  *object);

public Q_SLOTS:
    /**
           * Tries to raise/activate the Dolphin window.
           */
    void activateWindow();

    /** Stores all settings and quits Dolphin. */
    void quit();

    void openFiles(const QStringList &urls);
    /**
                * Determines if a URL is open in any tab.
                * @note Use of QString instead of QUrl is required to be callable via DBus.
                *
                * @param url URL to look for
                * @returns true if url is currently open in a tab, false otherwise.
                */
    bool isUrlOpen(const QString &url);


private:
    QObject* m_qmlObject = nullptr;
    QStringList filterFiles(const QStringList &urls);

};
