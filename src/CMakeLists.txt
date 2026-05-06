# Copyright 2018-2020 Camilo Higuita <milo.h@aol.com>
# Copyright 2018-2020 Nitrux Latinoamericana S.C.
#
# SPDX-License-Identifier: GPL-3.0-or-later

remove_definitions(-DQT_NO_CAST_FROM_ASCII -DQT_STRICT_ITERATORS -DQT_NO_CAST_FROM_BYTEARRAY)

set(vvave_SRCS
    main.cpp
    vvave.cpp
    pulpo/services/lastfmService.cpp
    pulpo/services/spotifyService.cpp
    pulpo/pulpo.cpp
    pulpo/service.cpp
    services/local/taginfo.cpp
    services/local/artworkprovider.cpp
    services/local/player.cpp
    services/local/playlist.cpp
    services/local/trackinfo.cpp
    services/local/metadataeditor.cpp
    services/local/powermanagementinterface.cpp
    models/tracks/tracksmodel.cpp
    models/playlists/playlistsmodel.cpp
    models/albums/albumsmodel.cpp
    kde/mpris2/mpris2.cpp
    kde/server.cpp)

qt_add_resources(vvave_QML_QRC
    assets.qrc)

qt_generate_dbus_interface(${CMAKE_CURRENT_SOURCE_DIR}/kde/server.h org.kde.Vvave.xml)
qt_add_dbus_adaptor(vvave_dbus_SRCS ${CMAKE_CURRENT_BINARY_DIR}/org.kde.Vvave.xml kde/server.h Server)
qt_add_dbus_interface(vvave_dbus_SRCS ${CMAKE_CURRENT_BINARY_DIR}/org.kde.Vvave.xml vvaveinterface)

qt_add_executable(${PROJECT_NAME}
    ${vvave_SRCS}
    ${vvave_dbus_SRCS}
    ${vvave_QML_QRC})

set_source_files_properties(utils/Player.js PROPERTIES QT_QML_SKIP_QMLDIR_ENTRY TRUE)
set_source_files_properties(db/Queries.js PROPERTIES QT_QML_SKIP_QMLDIR_ENTRY TRUE)

qt_add_qml_module(${PROJECT_NAME} URI app.maui.vvave
    NO_PLUGIN
    NO_IMPORT_SCAN
    QML_FILES
    main.qml
    widgets/TracksView.qml
    widgets/AlbumsView.qml
    widgets/MainPlaylist/MainPlaylist.qml
    widgets/PlaylistsView/PlaylistsView.qml
    widgets/InfoView/InfoView.qml
    widgets/PlaylistsView/PlaylistsViewModel.qml
    widgets/FloatingDisk.qml
    widgets/SelectionBar.qml
    widgets/FocusView.qml
    widgets/SettingsView/SettingsDialog.qml
    widgets/SettingsView/ShortcutsDialog.qml
    widgets/MetadataDialog.qml
    widgets/VVaveTable/TableDelegate.qml
    widgets/VVaveTable/TableMenu.qml
    widgets/VVaveTable/VVaveTable.qml
    widgets/VVaveGrid/VVaveGrid.qml
    widgets/MiniMode.qml

    utils/Player.js
    db/Queries.js)

target_sources(${PROJECT_NAME}
    PRIVATE
    kde/mpris2/mediaplayer2.cpp
    kde/mpris2/mediaplayer2player.cpp)

target_link_libraries(${PROJECT_NAME}
    PRIVATE
    Qt6::DBus
    Qt6::Widgets)

set(Taglib_LIBRARIES
    Taglib::Taglib)

target_compile_definitions(${PROJECT_NAME}
    PRIVATE $<$<OR:$<CONFIG:Debug>,$<CONFIG:RelWithDebInfo>>:QT_QML_DEBUG>)

target_include_directories(${PROJECT_NAME} PRIVATE ${Taglib_INCLUDE_DIRS})

target_link_libraries(${PROJECT_NAME}
    PRIVATE
    MauiKit4
    MauiKit4::FileBrowsing
    MauiKit4::Audio
    Qt6::Core
    Qt6::Network
    Qt6::Qml
    Qt6::Xml
    Qt6::Multimedia
    Qt6::QuickControls2
    KF6::CoreAddons
    KF6::I18n
${Taglib_LIBRARIES})

install(TARGETS ${PROJECT_NAME} ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES assets/vvave.svg DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)
