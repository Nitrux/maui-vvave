import QtQuick
import QtQml
import QtQuick.Controls
import QtQuick.Layouts

import QtQuick.Effects

import org.mauikit.controls as Maui

import "../utils/Player.js" as Player

import "VVaveTable"

StackView
{
    id: control

    focus: true
    padding: 0

    property alias loader: _loader

    function artworkSourceFor(artist, album)
    {
        const artistName = String(artist || "").trim()
        const albumName = String(album || "").trim()

        if (artistName.length > 0 && albumName.length > 0)
            return "image://artwork/album:" + encodeURIComponent(artistName) + ":" + encodeURIComponent(albumName)

        if (artistName.length > 0)
            return "image://artwork/artist:" + encodeURIComponent(artistName)

        return "qrc:/assets/cover.png"
    }

    background: null

    Loader
    {
        anchors.fill: parent
        active: !Maui.Handy.isMobile
        asynchronous: true
        sourceComponent: Item
        {
            DragHandler
            {
                grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverbyAnything
                onActiveChanged: { if (active) root.startSystemMove(); }
                // Harmonize(d) with ToolBar.qml, TabBar.qml from MauiKit.
            }
        }
    }

    initialItem: Loader
    {
        id: _loader
        focus: true
        asynchronous: true

        function forceActiveFocus()
        {
            if(item)
                item.forceActiveFocus()
        }

        sourceComponent: Maui.Page
        {
            Maui.Controls.showCSD: settings.focusViewDefault
            background: null
            headerContainer.margins: Maui.Style.contentMargins
            headBar.background: null
            headBar.rightContent: Loader
            {
                asynchronous: true
                sourceComponent: _mainMenuComponent
            }

            Maui.Holder
            {
                anchors.fill: parent
                visible: mainPlaylist.table.count === 0
                Maui.Theme.colorSet: Maui.Theme.Window
                Maui.Theme.inherit: false
                emoji: "qrc:/assets/view-media-track.svg"
                title : i18n("Nothing to play!")
                body: i18n("Start putting together your playlist.")
            }

            ColumnLayout
            {
                anchors.fill: parent
                spacing: Maui.Style.space.medium
                visible: mainPlaylist.table.count > 0

                Loader
                {
                    id: _artworkListLoader
                    asynchronous: true
                    active: mainPlaylist

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.maximumHeight: 400
                    Layout.minimumHeight: 100

                    onLoaded:
                    {
                        if (item && item.syncToCurrentTrack)
                            item.syncToCurrentTrack()
                    }
                    sourceComponent: ListView
                    {
                        id: _listView
                        implicitHeight: 300

                        orientation: ListView.Horizontal

                        focus: true
                        interactive: true

                        function syncToCurrentTrack()
                        {
                            const idx = root.currentTrackIndex
                            if (idx < 0 || idx >= count)
                                return

                            if (currentIndex !== idx)
                                currentIndex = idx

                            positionViewAtIndex(idx, ListView.Center)
                        }

                        Component.onCompleted: Qt.callLater(syncToCurrentTrack)
                        onCountChanged: Qt.callLater(syncToCurrentTrack)

                        Binding on currentIndex
                        {
                            value: currentTrackIndex
                            restoreMode: Binding.RestoreBindingOrValue
                        }

                        onCurrentIndexChanged:
                        {
                            if (currentIndex >= 0)
                                positionViewAtIndex(currentIndex, ListView.Center)
                        }

                        spacing: 0
                        highlightFollowsCurrentItem: true
                        highlightMoveDuration: 0
                        snapMode: ListView.SnapOneItem
                        model: mainPlaylist.listModel
                        highlightRangeMode: ListView.ApplyRange

                        Connections
                        {
                            target: root
                            function onCurrentTrackIndexChanged()
                            {
                                _listView.syncToCurrentTrack()
                            }

                            function onCurrentTrackChanged()
                            {
                                _listView.syncToCurrentTrack()
                            }
                        }

                        keyNavigationEnabled: true
                        keyNavigationWraps : true

                        Timer
                        {
                            id: _flickTimer
                            interval: 1000
                            onTriggered:
                            {
                                var index = _listView.indexAt(_listView.contentX, _listView.contentY)
                                if(index !== root.currentTrackIndex && index >= 0)
                                    Player.playAt(index)
                            }
                        }

                        onMovementEnded:
                        {
                            _flickTimer.start()
                        }

                        delegate: ColumnLayout
                        {
                            id: _artworkDelegate
                            height: ListView.view.height
                            width: ListView.view.width
                            spacing: Maui.Style.space.big
                            property bool isCurrentItem : ListView.isCurrentItem

                            Item
                            {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignCenter

                                Rectangle
                                {
                                    id: _bg
                                    width: _image.width + Maui.Style.space.medium
                                    height: width
                                    anchors.centerIn: parent
                                    radius: root.focusView ? Maui.Style.radiusV :  Math.min(width, height)

                                    Behavior on radius
                                    {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                    }

                                    color: "#fafafa"
                                    layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                                    layer.effect: MultiEffect
                                    {
                                        shadowHorizontalOffset: 0
                                        shadowVerticalOffset: 0
                                        shadowEnabled: true
                                        shadowColor: "#80000000"
                                    }
                                }

                                Image
                                {
                                    id: _image
                                    width: Math.min(parent.width, parent.height) * 0.9
                                    height: width
                                    anchors.centerIn: parent

                                    sourceSize.width: 200

                                    fillMode: Image.PreserveAspectFit
                                    antialiasing: false
                                    smooth: true
                                    asynchronous: true

                                    source: control.artworkSourceFor(model.artist, model.album)

                                    layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                                    layer.effect: MultiEffect
                                    {
                                        maskEnabled: true
                                        maskThresholdMin: 0.5
                                        maskSpreadAtMin: 1.0
                                        maskSpreadAtMax: 0.0
                                        maskThresholdMax: 1.0
                                        maskSource: ShaderEffectSource
                                        {
                                            sourceItem: Rectangle
                                            {
                                                width: _image.width
                                                height: _image.height
                                                radius: _bg.radius
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout
                            {
                                Layout.fillWidth: true
                                implicitHeight: Maui.Style.toolBarHeight
                                spacing: 0

                                Label
                                {
                                    id: _label1
                                    visible: text.length
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    verticalAlignment: Qt.AlignVCenter
                                    horizontalAlignment: Qt.AlignHCenter
                                    text: model.title
                                    elide: Text.ElideMiddle
                                    wrapMode: Text.NoWrap
                                    color: Maui.Theme.textColor
                                    font.weight: Font.Bold
                                    font.pointSize: Maui.Style.fontSizes.huge
                                }

                                Label
                                {
                                    id: _label2
                                    visible: text.length
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    verticalAlignment: Qt.AlignVCenter
                                    horizontalAlignment: Qt.AlignHCenter
                                    text: model.artist
                                    elide: Text.ElideMiddle
                                    wrapMode: Text.NoWrap
                                    color: Maui.Theme.textColor
                                    font.weight: Font.Normal
                                    font.pointSize: Maui.Style.fontSizes.big
                                    opacity: 0.7
                                }
                            }
                        }
                    }
                }

            }
        }
    }

    function forceActiveFocus()
    {
        if(control.currentItem)
            control.currentItem.forceActiveFocus()
    }

    Component.onCompleted:
    {
        forceActiveFocus()
    }

}
