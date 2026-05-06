#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDebug>
#include <QCommandLineParser>
#include <QIcon>
#include <QApplication>
#include <QSurfaceFormat>
#include <QDate>
#include <QGuiApplication>

#include <KLocalizedString>

#include "kde/mpris2/mpris2.h"
#include "kde/mpris2/mediaplayer2player.h"

#include <MauiKit4/FileBrowsing/fmstatic.h>
#include <MauiKit4/Core/mauiapp.h>
#include <MauiKit4/FileBrowsing/moduleinfo.h>
#include <MauiKit4/Audio/moduleinfo.h>

#include <taglib/taglib.h>

#include "../vvave_version.h"

#include "vvave.h"

#include "services/local/artworkprovider.h"
#include "services/local/player.h"
#include "services/local/playlist.h"
#include "services/local/trackinfo.h"
#include "services/local/metadataeditor.h"

#include "models/albums/albumsmodel.h"
#include "models/playlists/playlistsmodel.h"
#include "models/tracks/tracksmodel.h"

#include "kde/server.h"

#define VVAVE_URI "org.maui.vvave"

Q_DECL_EXPORT int main(int argc, char *argv[])
{
    qDebug() << "APP LOADING SPEED TESTS" << 0;

    QSurfaceFormat format;
    format.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(format);

    QApplication app(argc, argv);

    qDebug() << "APP LOADING SPEED TESTS" << 2;

    app.setOrganizationName(QStringLiteral("Maui"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("maui-vvave"), QIcon(QStringLiteral(":/assets/vvave.png"))));
    QGuiApplication::setDesktopFileName(QStringLiteral("org.maui.vvave"));

    KLocalizedString::setApplicationDomain("vvave");
    KAboutData about(QStringLiteral("vvave"),
                     i18n("Vvave"),
                     VVAVE_VERSION_STRING,
                     i18n("Organize and listen to your music."),
                     KAboutLicense::LGPL_V3,
                     i18n("© %1 Made by Nitrux | Built with MauiKit", QString::number(QDate::currentDate().year())),
                     QString(GIT_BRANCH) + "/" + QString(GIT_COMMIT_HASH));

    about.addAuthor("Camilo Higuita", i18n("Developer"), QStringLiteral("milo.h@aol.com"));
    about.addAuthor("Will Chen", i18n("Developer"), QStringLiteral("intralexical@gmail.com"));
    about.addAuthor(QStringLiteral("Uri Herrera"), i18n("Developer"), QStringLiteral("uri_herrera@nxos.org"));

    about.setHomepage("https://nxos.org");
    about.setProductName("nitrux/vvave");
    about.setBugAddress("https://invent.kde.org/maui/vvave/-/issues");
    about.setOrganizationDomain(VVAVE_URI);
    about.setProgramLogo(app.windowIcon());
    about.setDesktopFileName("org.maui.vvave");

    about.addComponent("TagLib",
                       "",
                       QString("%1.%2.%3").arg(QString::number(TAGLIB_MAJOR_VERSION),QString::number(TAGLIB_MINOR_VERSION),QString::number(TAGLIB_PATCH_VERSION)),
                       "https://taglib.org/api/index.html");

    const auto FBData = MauiKitFileBrowsing::aboutData();
    about.addComponent(FBData.name(), MauiKitFileBrowsing::buildVersion(), FBData.version(), FBData.webAddress());

    const auto AudioData = MauiKitAudio::aboutData();
    about.addComponent(AudioData.name(), MauiKitAudio::buildVersion(), AudioData.version(), AudioData.webAddress());

    // about.addCredit(MauiKitAudio::credit());

    KAboutData::setApplicationData(about);

    MauiApp::instance()->setIconName("qrc:/assets/vvave.png");

    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    parser.process(app);
    about.processCommandLine(&parser);

    const QStringList args = parser.positionalArguments();
    QStringList paths;

    if (!args.isEmpty())
    {
        for(const auto &path : args)
            paths << QUrl::fromUserInput(path).toString();
    }

    if (AppInstance::attachToExistingInstance(QUrl::fromStringList(paths)))
    {
        // Successfully attached to an existing Vvave instance.
        return 0;
    }

    AppInstance::registerService();

    auto server =  std::make_unique<Server>();

    QQmlApplicationEngine engine;
    const QUrl url(QStringLiteral("qrc:/qt/qml/app/maui/vvave/main.qml"));

    qDebug() << "APP LOADING SPEED TESTS" << 3;

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app, [url, args, &server](QObject *obj, const QUrl &objUrl)
        {
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);

            server->setQmlObject(obj);

            if (!args.isEmpty())
                server->openFiles(args);

        }, Qt::QueuedConnection);

    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));

    qmlRegisterSingletonInstance<vvave>(VVAVE_URI, 1, 0, "Vvave", vvave::instance());
    qmlRegisterSingletonInstance<Server>(VVAVE_URI, 1, 0, "Server", server.get());

    qmlRegisterType<TracksModel>(VVAVE_URI, 1, 0, "Tracks");
    qmlRegisterType<AlbumsModel>(VVAVE_URI, 1, 0, "Albums");
    qmlRegisterType<Player>(VVAVE_URI, 1, 0, "Player");
    qmlRegisterType<Playlist>(VVAVE_URI, 1, 0, "Playlist");
    qmlRegisterType<Mpris2>(VVAVE_URI, 1, 0, "Mpris2");

    qmlRegisterType<TrackInfo>(VVAVE_URI, 1, 0, "TrackInfo");
    qmlRegisterType<MetadataEditor>(VVAVE_URI, 1, 0, "MetadataEditor");

    qmlRegisterType<PlaylistsModel>(VVAVE_URI, 1, 0, "Playlists");

    engine.addImageProvider("artwork", new ArtworkProvider());

    qRegisterMetaType<MediaPlayer2Player *>();

    qDebug() << "APP LOADING SPEED TESTS" << 4;

    engine.load(url);

    qDebug() << "APP LOADING SPEED TESTS" << 5;

    return app.exec();
}
