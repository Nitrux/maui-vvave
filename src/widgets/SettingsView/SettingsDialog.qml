/*
 *   Copyright 2020 Camilo Higuita <milo.h@aol.com>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU Library General Public License as
 *   published by the Free Software Foundation; either version 2, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details
 *
 *   You should have received a copy of the GNU Library General Public
 *   License along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing as FB

import org.maui.vvave

Maui.SettingsDialog
{
    id: control
    property var backendLabels: [i18n("Automatic")]
    property var backendValues: [""]
    readonly property var sleepLabels: [
        i18n("Disabled"),
        i18n("15 minutes"),
        i18n("30 minutes"),
        i18n("60 minutes"),
        i18n("End of current track"),
        i18n("End of playlist")
    ]
    readonly property var sleepValues: [
        "none",
        "15m",
        "30m",
        "60m",
        "eot",
        "eop"
    ]

    function updateBackendChoices()
    {
        const labels = [i18n("Automatic")]
        const values = [""]
        const seen = new Set()
        for (let i = 0; i < player.outputs.length; ++i) {
            const backend = player.outputs[i]
            const text = String(backend).trim()
            if (!text.length || seen.has(text))
                continue

            seen.add(text)
            labels.push(text.charAt(0).toUpperCase() + text.slice(1))
            values.push(text)
        }

        backendLabels = labels
        backendValues = values
    }

    Component.onCompleted: updateBackendChoices()

    Maui.InfoDialog
    {
        id: confirmationDialog
        property string url : ""

        title : i18n("Remove source")
        message : i18n("Are you sure you want to remove the source: \n%1", url)
        template.iconSource: "emblem-warning"

        standardButtons: Dialog.Ok | Dialog.Cancel

        onAccepted:
        {
            if(url.length>0)
                Vvave.removeSource(url)
            confirmationDialog.close()
        }
        onRejected: confirmationDialog.close()
    }

    Maui.SectionGroup
    {
        title: i18n("Playback")

        Maui.FlexSectionItem
        {
            label1.text: i18n("Playback Backend")
            label2.text: (_outputCombo.currentIndex > 0 && _outputCombo.currentText.length)
                         ? i18n("Current backend: %1. Use Automatic to let Vvave pick the best available backend.", _outputCombo.currentText)
                         : i18n("Vvave automatically selects the best available playback backend.")

            ComboBox 
            {
                id: _outputCombo
                model: control.backendLabels
                onActivated:
                {
                    player.preferredOutput = control.backendValues[currentIndex]
                }
                Component.onCompleted:
                {
                    control.updateBackendChoices()
                    currentIndex = 0
                    if (player.preferredOutput !== "")
                        player.preferredOutput = ""
                }
            }
        }

        Maui.FlexSectionItem
        {
            label1.text: i18n("Sleep Timer")
            label2.text: i18n("Stop playback after a selected amount of time or when the playlist finishes.")

            ComboBox
            {
                id: _sleepOptionCombo
                model: control.sleepLabels
                Component.onCompleted:
                {
                    const index = Math.max(0, control.sleepValues.indexOf(settings.sleepOption))
                    currentIndex = index
                }

                onActivated: setSleepTimer(control.sleepValues[currentIndex])
            }
        }
    }

    Maui.SectionGroup
    {
        title: i18n("Collection")
//        description: i18n("Configure the app plugins and collection behavior.")

        Maui.FlexSectionItem
        {
            label1.text: i18n("Fetch Artwork")
            label2.text: i18n("Gathers album and artists artworks from online services: LastFM, Spotify, MusicBrainz, iTunes, Genius, and others.")

            Switch
            {
                checkable: true
                checked: settings.fetchArtwork
                onToggled:  settings.fetchArtwork = !settings.fetchArtwork
            }
        }

    }

    Maui.SectionGroup
    {
        title: i18n("General")
//        description: i18n("Configure the app plugins and collection behavior.")

        Maui.FlexSectionItem
        {
            label1.text: i18n("Focus View")
            label2.text: i18n("Make the focus view the default.")

            Switch
            {
                Layout.fillHeight: true
                checked: settings.focusViewDefault
                onToggled:
                {
                     settings.focusViewDefault = !settings.focusViewDefault
                }
            }
        }

        Maui.FlexSectionItem
        {
            label1.text: i18n("Artwork")
            label2.text: i18n("Show the cover artwork for the tracks.")

            Switch
            {
                Layout.fillHeight: true
                checked: settings.showArtwork
                onToggled:
                {
                    settings.showArtwork = !settings.showArtwork
                }
            }
        }

        Maui.FlexSectionItem
        {
            label1.text: i18n("Titles")
            label2.text: i18n("Show the title of albums and artists in the grid view.")

            Switch
            {
                Layout.fillHeight: true
                checked: settings.showTitles
                onToggled:
                {
                    settings.showTitles = !settings.showTitles
                }
            }
        }
    }

    Maui.SectionGroup
    {
        title: i18n("Sources")
//        description: i18n("Add or remove sources")

        ColumnLayout
        {
            Layout.fillWidth: true
            spacing: Maui.Style.space.medium

            Repeater
            {
                model: Vvave.sources

                delegate: Maui.ListDelegate
                {
                    Layout.fillWidth: true

                    template.iconSource: modelData.icon
                    template.iconSizeHint: Maui.Style.iconSizes.small
                    template.label1.text: modelData.label
                    template.label2.text: modelData.path

                    template.content: ToolButton
                    {
                        icon.name: "edit-clear"
                        flat: true
                        onClicked:
                        {
                            confirmationDialog.url = modelData.path
                            confirmationDialog.open()
                        }
                    }
                }
            }

            Button
            {
                Layout.fillWidth: true
                text: i18n("Add")
                //                flat: true
                onClicked:
                {
                    let props =({'mode' : FB.FileDialog.Modes.Open,
                                    'browser.settings.onlyDirs' : true,
                                    'callback' : function(urls)
                                    {
                                        Vvave.addSources(urls)
                                    }})
                    var dialog = _fileDialogComponent.createObject(root, props)
                    dialog.open()
                }
            }

        }
    }

}
