# Copyright 2018-2020 Camilo Higuita <milo.h@aol.com>
# Copyright 2018-2020 Nitrux Latinoamericana S.C.
#
# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 3.20)

set(VVAVE_VERSION 4.0.3)
add_compile_definitions(APP_COPYRIGHT_NOTICE="© 2019-2025 Maui Development Team")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(CheckCXXCompilerFlag)
if(NOT CMAKE_CROSSCOMPILING)
    string(TOLOWER "${CMAKE_HOST_SYSTEM_PROCESSOR}" _host_processor)
    if(_host_processor MATCHES "^(x86_64|amd64)$")
        check_cxx_compiler_flag("-march=x86-64-v3" HAS_X86_64_V3)
        if(HAS_X86_64_V3)
            add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-march=x86-64-v3>")
        endif()
    endif()
endif()
set(CMAKE_INCLUDE_CURRENT_DIR ON)

set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

project(vvave VERSION ${VVAVE_VERSION} LANGUAGES CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(FATAL_ERROR "This project supports Linux only.")
endif()


set(QT_MAJOR_VERSION 6)

set(REQUIRED_QT_VERSION 6.5.2)
set(REQUIRED_KF_VERSION 5.240.0)

find_package(ECM ${REQUIRED_KF_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
# set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)

include(KDECompilerSettings NO_POLICY_SCOPE)
include(KDEClangFormat)
include(ECMSetupVersion)
include(ECMSourceVersionControl)
include(FeatureSummary)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Qml Quick QuickControls2 Network Sql Xml Multimedia)
find_package(KF6 ${REQUIRED_KF_VERSION} REQUIRED COMPONENTS I18n CoreAddons)

find_package(MauiKit4 REQUIRED COMPONENTS FileBrowsing Audio)

find_package(Taglib 1.4 REQUIRED)
find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS DBus Widgets)

if(${ECM_SOURCE_UNDER_VERSION_CONTROL})
    execute_process(
        COMMAND git rev-parse --abbrev-ref HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_BRANCH
        OUTPUT_STRIP_TRAILING_WHITESPACE)

    # Get the latest abbreviated commit hash of the working branch
    execute_process(
        COMMAND git log -1 --format=%h
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_COMMIT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE)

    add_definitions(-DGIT_COMMIT_HASH="${GIT_COMMIT_HASH}")
    add_definitions(-DGIT_BRANCH="${GIT_BRANCH}")

else()
    add_definitions(-DGIT_COMMIT_HASH="${VVAVE_VERSION}")
    add_definitions(-DGIT_BRANCH="Stable")
endif()

ecm_setup_version(${VVAVE_VERSION}
    VARIABLE_PREFIX VVAVE
    VERSION_HEADER "${CMAKE_CURRENT_BINARY_DIR}/vvave_version.h")

qt_policy(SET QTP0001 OLD)
qt_policy(SET QTP0004 NEW)

add_subdirectory(src)

ki18n_install(po)

install(FILES org.kde.vvave.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES org.kde.vvave.appdata.xml DESTINATION ${KDE_INSTALL_METAINFODIR})

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)

file(GLOB_RECURSE ALL_CLANG_FORMAT_SOURCE_FILES *.cpp *.h)
kde_clang_format(${ALL_CLANG_FORMAT_SOURCE_FILES})

qt_finalize_project()


if(NOT TARGET uninstall)
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake_uninstall.cmake.in"
        "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
        IMMEDIATE
        @ONLY)

    add_custom_target(uninstall
        COMMAND ${CMAKE_COMMAND} -P "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake")
endif()
