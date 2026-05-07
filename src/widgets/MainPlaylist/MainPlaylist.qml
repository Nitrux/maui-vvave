import QtQuick
import QtQml

import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing as FB

import org.maui.vvave as Vvave

import "../../utils/Player.js" as Player
import "../../db/Queries.js" as Q

import "../VVaveTable"

Maui.Page
{
    id: control

    Maui.Theme.colorSet: Maui.Theme.Window

    property alias listModel: table.listModel
    readonly property alias listView : table.listView
    readonly property alias table: table
    property bool collapseRepeatedAlbumArt: false

    readonly property alias contextMenu: table.contextMenu

    headBar.visible: false

    background: null

    Component
    {
        id: _fileDialogComponent
        FB.FileDialog {onClosed: destroy()}
    }

    VVaveTable
    {
        id: table
        clip: true
        anchors.fill: parent
        list.autoPopulate: false
        footBar.visible: !mainlistEmpty
        footerMargins: Maui.Style.defaultPadding
        background: null
        footBar.rightContent:[

            ToolButton
            {
                icon.name: "edit-clear"
                ToolTip.visible: hovered
                ToolTip.text: i18n("Clear playlist")
                onClicked:
                {
                    player.stop()
                    listModel.list.clear()
                    root.sync = false
                    root.syncPlaylist = ""
                }
            },
            Loader
            {
                active: settings.sleepOption !== "none"
                visible: active
                sourceComponent: Label
                {
                    font.family: "Monospace"
                    text: "Zzz"
                    color: "white"
                    padding: Maui.Style.space.tiny

                    // icon.name: "clock"
                    background: Rectangle
                    {
                        color: "purple"
                        radius: 4
                    }
                }
            }]

        footBar.leftContent: [
            ToolButton
            {
                icon.name: "document-save"
                ToolTip.visible: hovered
                ToolTip.text: i18n("Save playlist to file")
                onClicked: saveList()
            },

            ToolButton
            {
                icon.name: switch(playlist.repeatMode)
                           {
                           case Vvave.Playlist.NoRepeat: return "media-repeat-none"
                           case Vvave.Playlist.RepeatOnce: return "media-playlist-repeat-song"
                           case Vvave.Playlist.Repeat: return "media-playlist-repeat"
                           }
                ToolTip.visible: hovered
                ToolTip.text: switch(playlist.repeatMode)
                              {
                              case Vvave.Playlist.NoRepeat: return i18n("Repeat: Off")
                              case Vvave.Playlist.RepeatOnce: return i18n("Repeat: One")
                              case Vvave.Playlist.Repeat: return i18n("Repeat: All")
                              }
                onClicked:
                {
                    switch(playlist.repeatMode)
                    {
                    case Vvave.Playlist.NoRepeat:
                        playlist.repeatMode = Vvave.Playlist.Repeat
                        break

                    case Vvave.Playlist.Repeat:
                        playlist.repeatMode = Vvave.Playlist.RepeatOnce
                        break

                    case Vvave.Playlist.RepeatOnce:
                        playlist.repeatMode = Vvave.Playlist.NoRepeat
                        break
                    }
                }
            },

            ToolButton
            {
                checked:  playlist.playMode === Vvave.Playlist.Shuffle
                icon.name: switch(playlist.playMode)
                           {
                           case Vvave.Playlist.Normal: return "media-playlist-normal"
                           case Vvave.Playlist.Shuffle: return "media-playlist-shuffle"
                           }
                ToolTip.visible: hovered
                ToolTip.text: checked ? i18n("Playback mode: Shuffle") : i18n("Playback mode: Normal")

                onClicked:
                {
                    switch(playlist.playMode)
                    {
                    case Vvave.Playlist.Normal:
                        playlist.playMode = Vvave.Playlist.Shuffle
                        break

                    case Vvave.Playlist.Shuffle:
                        playlist.playMode = Vvave.Playlist.Normal
                        break
                    }
                }
            }]

        Binding on currentIndex
        {
            value: currentTrackIndex
            restoreMode: Binding.RestoreBindingOrValue
        }

        listModel.sort: ""
        listBrowser.enableLassoSelection: false
        headBar.visible: false
        Maui.Theme.colorSet: Maui.Theme.Window

        holder.visible: listModel.list.count === 0
        holder.label1.width: Math.min(width - (Maui.Style.space.big * 2), Maui.Style.units.gridUnit * 12)
        holder.label2.width: holder.label1.width
        holder.emoji: "media-playlist-append"
        holder.title : i18n("Playlist is Empty")
        holder.body: i18n("Play videos from your library to build a playlist.")
        listView.header: Column
        {
            width: parent.width

            Loader
            {
                width: visible ? parent.width : 0
                height: width

                asynchronous: true
                active: !focusView && control.height > control.width*3 && currentTrackIndex >= 0
                visible: active && !mainlistEmpty
                sourceComponent: Item
                {
                    scale: _mouseArea.pressed ? 0.9 :  1

                    Behavior on scale
                    {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    Maui.GalleryRollTemplate
                    {
                        anchors.fill: parent
                        anchors.bottomMargin: Maui.Style.space.medium
                        radius: Maui.Style.radiusV
                        interactive: true
                        fillMode: Image.PreserveAspectCrop

                        images: [
                            "image://artwork/album:"
                            + (currentTrack && currentTrack.artist ? currentTrack.artist : "")
                            + ":"
                            + (currentTrack && currentTrack.album ? currentTrack.album : ""),
                            "image://artwork/artist:"
                            + (currentTrack && currentTrack.artist ? currentTrack.artist : "")
                        ]
                    }

                    MouseArea
                    {
                        id:_mouseArea
                        anchors.fill: parent
                        onDoubleClicked: toggleMiniMode()
                        hoverEnabled: true

                        Rectangle
                        {
                            anchors.fill: parent
                            color: Maui.Theme.backgroundColor
                            visible: parent.containsMouse
                            opacity: parent.pressed ? 0.8 : 0.6
                        }

                        Maui.Icon
                        {
                            visible: parent.containsMouse

                            source: "window"
                            color: Maui.Theme.textColor
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: Maui.Style.space.medium
                        }
                    }
                }

                OpacityAnimator on opacity
                {
                    from: 0
                    to: 1
                    duration: Maui.Style.units.longDuration
                    running: parent.status === Loader.Ready
                }
            }

            Rectangle
            {
                visible: root.sync
                Maui.Theme.inherit: false
                Maui.Theme.colorSet:Maui.Theme.Complementary
                z: table.z + 999
                width: parent.width
                height: visible ?  Maui.Style.rowHeightAlt : 0
                color: Maui.Theme.backgroundColor

                RowLayout
                {
                    anchors.fill: parent
                    anchors.leftMargin: Maui.Style.space.small

                    Label
                    {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        anchors.margins: Maui.Style.space.small
                        text: i18n("Syncing to ") + root.syncPlaylist
                    }

                    ToolButton
                    {
                        Layout.fillHeight: true
                        icon.name: "dialog-close"
                        onClicked:
                        {
                            root.sync = false
                            root.syncPlaylist = ""
                        }
                    }
                }
            }
        }

        delegate: TableDelegate
        {
            id: delegate

            width: ListView.view.width
            height: Math.max(implicitHeight, Maui.Style.rowHeight)

            property int mindex : index

            isCurrentItem: ListView.isCurrentItem
            mouseArea.drag.axis: Drag.YAxis
            Drag.source: delegate

            number : false
            coverArt : settings.fetchArtwork
            draggable: true
            checkable: false
            checked: false

            onPressAndHold: if(Maui.Handy.isTouch && table.allowMenu) table.openItemMenu(index)

            onRightClicked: tryOpenContextMenu()

            function tryOpenContextMenu()
            {
                if (table.allowMenu)
                    table.openItemMenu(index)
            }

            sameAlbum: control.totalMoves, evaluate(listModel.get(mindex-1))

            function evaluate(item)
            {
                return control.collapseRepeatedAlbumArt && coverArt && item && item.album === model.album && item.artist === model.artist
            }

                Item
                {
                    visible: mindex === currentTrackIndex
                    Layout.fillHeight: true
                    Layout.preferredWidth: Maui.Style.rowHeight

                    AnimatedImage
                    {
                        id: _playingIcon
                        height: 16
                        width: height
                        playing: root.isPlaying && Maui.Style.enableEffects
                        anchors.centerIn: parent
                        source: "qrc:/assets/playing.gif"
                        visible: GraphicsInfo.api === GraphicsInfo.Software
                    }

                    MultiEffect
                    {
                        anchors.fill: _playingIcon
                        source: _playingIcon
                        colorization: 1.0
                        contrast: 1.0
                        colorizationColor: "#fafafa"
                        visible: GraphicsInfo.api !== GraphicsInfo.Software
                    }
                }

                AbstractButton
                {
                    Layout.fillHeight: true
                    Layout.preferredWidth: Maui.Style.rowHeight
                    visible: (Maui.Handy.isTouch ? true : delegate.hovered) && index !== currentTrackIndex
                    icon.name: "edit-clear"
                    onClicked:
                    {
                        if(index === currentTrackIndex)
                            player.stop()

                        root.playlistManager.remove(index)
                    }

                    Maui.Icon
                    {
                        color: delegate.label1.color
                        anchors.centerIn: parent
                        height: Maui.Style.iconSizes.small
                        width: height
                        source: parent.icon.name
                    }
                    opacity: delegate.hovered ? 0.8 : 0.6
                }

                onClicked:
                {
                    table.forceActiveFocus()
                    if(Maui.Handy.isTouch)
                        Player.playAt(index)
                }

                onDoubleClicked:
                {
                    if(!Maui.Handy.isTouch)
                        Player.playAt(index)
                }

                onContentDropped: (drop) =>
                                  {
                                      if(typeof drop.source.mindex !== 'undefined')
                                      {
                                          root.playlistManager.move(drop.source.mindex, delegate.mindex)

                                      }else
                                      {
                                          root.playlistManager.insert(String(drop.urls).split(","), delegate.mindex)
                                      }

                                      control.totalMoves++
                                  }
            }
        }

        property int totalMoves: 0

        function saveList()
        {
            if (listModel.list.count <= 0)
                return

            const suggested = "VVave Playlist " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh-mm-ss") + ".m3u"
            const props = ({
                               'mode': FB.FileDialog.Modes.Save,
                               'singleSelection': true,
                               'currentPath': FB.FM.homePath(),
                               'suggestedFileName': suggested,
                               'callback': function(paths)
                               {
                                   if (!paths || paths.length === 0)
                                       return

                                   const ok = playlist.exportM3U(paths[0])
                                   if (ok)
                                       Maui.App.rootComponent.notify("dialog-information", i18n("Playlist saved"), paths[0])
                                   else
                                       Maui.App.rootComponent.notify("dialog-error", i18n("Could not save playlist"), paths[0])
                               }
                           })

            const dialog = _fileDialogComponent.createObject(root, props)
            dialog.open()
        }
    }
