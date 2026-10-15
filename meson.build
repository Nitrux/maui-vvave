project('vvave', 'cpp', version: '4.0.5', meson_version: '>=1.12.0', default_options: ['cpp_std=c++17', 'buildtype=release'])
qt6 = import('qt6')
cpp_compiler = meson.get_compiler('cpp')
if cpp_compiler.get_id() == 'gcc' and cpp_compiler.has_argument('-Wno-sfinae-incomplete')
    add_project_arguments('-Wno-sfinae-incomplete', language: 'cpp')
endif
qt = dependency('qt6', version: '>=6.9', modules: ['Core', 'Concurrent', 'Qml', 'Quick', 'QuickControls2', 'Network', 'Xml', 'Multimedia', 'DBus', 'Widgets'])
kf6_core = declare_dependency(
    include_directories: include_directories(get_option('prefix') / 'include' / 'KF6' / 'KCoreAddons'),
    dependencies: [cpp_compiler.find_library('KF6CoreAddons')],
)
kf6_i18n = declare_dependency(
    include_directories: include_directories(get_option('prefix') / 'include' / 'KF6' / 'KI18n'),
    dependencies: [cpp_compiler.find_library('KF6I18n'), cpp_compiler.find_library('KF6I18nQml')],
)
mauikit = dependency('MauiKit4', version: '>=4.0.5')
filebrowsing = dependency('MauiKitFileBrowsing4', version: '>=4.0.5')
audio = dependency('MauiKitAudio4', version: '>=4.0.5')
taglib = dependency('taglib', version: '>=2.0')
cpp_args = ['-DAPP_COPYRIGHT_NOTICE="© 2019-2025 Maui Development Team"']
if host_machine.cpu_family() == 'x86_64'
    cpp_args += ['-march=x86-64-v3']
endif
vvave_version = configure_file(
    input: 'meson-content.in',
    output: 'vvave_version.h',
    configuration: {'CONTENT': ('''#pragma once
#define VVAVE_VERSION_STRING "4.0.5"
#define GIT_BRANCH "Stable"
#define GIT_COMMIT_HASH "4.0.5"
''')}
)
vvave_includes = include_directories('src')
dbus_cpp2xml = find_program('qdbuscpp2xml')
dbus_xml2cpp = find_program('qdbusxml2cpp')
dbus_xml = custom_target('vvave-dbus-xml', input: 'src/kde/server.h', output: 'org.kde.Vvave.xml', command: [dbus_cpp2xml, '-o', '@OUTPUT@', '@INPUT@'])
dbus_adaptor = custom_target('vvave-dbus-adaptor', input: dbus_xml, output: ['vvaveadaptor.cpp', 'vvaveadaptor.h'], command: [dbus_xml2cpp, '-a', 'vvaveadaptor', '@INPUT@'])
dbus_interface = custom_target('vvave-dbus-interface', input: dbus_xml, output: ['vvaveinterface.cpp', 'vvaveinterface.h'], command: [dbus_xml2cpp, '-p', 'vvaveinterface', '@INPUT@'])
vvave_sources = ['src/main.cpp', 'src/vvave.cpp', 'src/pulpo/services/lastfmService.cpp', 'src/pulpo/services/spotifyService.cpp', 'src/pulpo/pulpo.cpp', 'src/pulpo/service.cpp', 'src/services/local/taginfo.cpp', 'src/services/local/artworkprovider.cpp', 'src/services/local/player.cpp', 'src/services/local/playlist.cpp', 'src/services/local/metadataeditor.cpp', 'src/services/local/powermanagementinterface.cpp', 'src/models/tracks/tracksmodel.cpp', 'src/models/albums/albumsmodel.cpp', 'src/kde/mpris2/mpris2.cpp', 'src/kde/mpris2/mediaplayer2.cpp', 'src/kde/mpris2/mediaplayer2player.cpp', 'src/kde/server.cpp']
qt_sources = qt6.preprocess(qresources: ['src/assets.qrc', 'src/qml.qrc'], moc_headers: ['src/vvave.h', 'src/services/local/powermanagementinterface.h', 'src/kde/mpris2/mpris2.h', 'src/kde/mpris2/mediaplayer2.h', 'src/kde/mpris2/mediaplayer2player.h', 'src/services/local/artworkprovider.h', 'src/services/local/metadataeditor.h', 'src/services/local/player.h', 'src/services/local/playlist.h', 'src/services/local/taginfo.h', 'src/models/tracks/tracksmodel.h', 'src/models/albums/albumsmodel.h', 'src/pulpo/pulpo.h', 'src/pulpo/service.h', 'src/pulpo/services/lastfmService.h', 'src/pulpo/services/spotifyService.h', 'src/kde/server.h', dbus_adaptor[1], dbus_interface[1]], moc_extra_arguments: ['-I' + qt.get_variable('includedir'), '-I' + qt.get_variable('includedir') + '/QtQml'])
executable('vvave', vvave_sources + [dbus_adaptor, dbus_interface] + qt_sources + [vvave_version], dependencies: [qt, kf6_core, kf6_i18n, mauikit, filebrowsing, audio, taglib], include_directories: vvave_includes, cpp_args: cpp_args, install: true)
install_data('org.maui.vvave.desktop', install_dir: get_option('datadir') / 'applications')
install_data('org.maui.vvave.appdata.xml', install_dir: get_option('datadir') / 'metainfo')
install_data('src/assets/vvave.svg', install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps')
