import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing as FB
import org.maui.vvave as Vvave

import "VVaveTable"
import "../db/Queries.js" as Q
import "../utils/Player.js" as Player

VVaveTable
{
    id: control

    Maui.Theme.colorSet: Maui.Theme.Window
    Maui.Theme.inherit: false

    trackNumberVisible: false
    coverArtVisible: false
    group: false
    enforceDefaultTitleSort: true

    readonly property int rowPadding: Maui.Style.space.small
    readonly property int cellPadding: Maui.Style.space.medium
    readonly property int tableMaxWidth: 1040
    readonly property int headerHeight: 32
    readonly property int tableAvailableWidth: Math.max(Math.min(width - (rowPadding * 2) - 24, tableMaxWidth), 320)
    readonly property int totalColumnWeight: 116

    readonly property int songColWidth: Math.round(tableAvailableWidth * 33 / totalColumnWeight)
    readonly property int artistColWidth: Math.round(tableAvailableWidth * 22 / totalColumnWeight)
    readonly property int albumColWidth: Math.round(tableAvailableWidth * 22 / totalColumnWeight)
    readonly property int yearColWidth: Math.round(tableAvailableWidth * 8 / totalColumnWeight)
    readonly property int lengthColWidth: Math.round(tableAvailableWidth * 8 / totalColumnWeight)
    readonly property int favColWidth: Math.round(tableAvailableWidth * 8 / totalColumnWeight)
    readonly property int genreColWidth: Math.max(120, tableAvailableWidth - (songColWidth + artistColWidth + albumColWidth + yearColWidth + lengthColWidth + favColWidth))

    function formatDuration(seconds)
    {
        const secs = Math.max(0, parseInt(seconds || "0"))
        const m = Math.floor(secs / 60)
        const s = secs % 60
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }

    function yearLabel(value)
    {
        const year = parseInt(value || "0")
        return year > 0 ? String(year) : ""
    }

    headBar.visible: Vvave.Vvave.sources.length > 0 && count > 0
    holder.visible: Vvave.Vvave.sources.length === 0 || count === 0
    holder.emoji: "folder-music"
    holder.title : i18n("No Tracks!")
    holder.body: i18n("Add new music sources")
    holder.actions: []

    list.query : Q.GET.allTracks
    listModel.sort : "title"
    listModel.sortOrder : Qt.AscendingOrder

    listView.headerPositioning: ListView.OverlayHeader
    listView.topMargin: control.count > 0 ? 12 : 0

    listView.header: Rectangle
    {
        width: parent ? parent.width : 0
        height: control.count > 0 ? control.headerHeight : 0
        color: Qt.rgba(0.12, 0.11, 0.16, 1.0)
        radius: Maui.Style.radiusV
        visible: height > 0
        z: 999

        RowLayout
        {
            anchors.left: parent.left
            anchors.leftMargin: control.rowPadding
            anchors.verticalCenter: parent.verticalCenter
            width: control.tableAvailableWidth
            height: parent.height
            spacing: 0

            Item
            {
                Layout.preferredWidth: control.songColWidth
                Layout.fillHeight: true

                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding + 38 + Maui.Style.space.small
                    anchors.rightMargin: control.cellPadding
                    text: i18n("Song")
                    font.bold: true
                    opacity: 0.92
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }
            Item
            {
                Layout.preferredWidth: control.artistColWidth
                Layout.fillHeight: true
                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    text: i18n("Artist")
                    font.bold: true
                    opacity: 0.92
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }
            Item
            {
                Layout.preferredWidth: control.albumColWidth
                Layout.fillHeight: true
                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    text: i18n("Album")
                    font.bold: true
                    opacity: 0.92
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }
            Item
            {
                Layout.preferredWidth: control.yearColWidth
                Layout.fillHeight: true
                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    text: i18n("Year")
                    font.bold: true
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    opacity: 0.92
                    elide: Text.ElideRight
                }
            }
            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }
            Item
            {
                Layout.preferredWidth: control.lengthColWidth
                Layout.fillHeight: true
                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    text: i18n("Length")
                    font.bold: true
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    opacity: 0.92
                    elide: Text.ElideRight
                }
            }
            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }
            Item
            {
                Layout.preferredWidth: control.favColWidth
                Layout.fillHeight: true
                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    text: i18n("Favorite")
                    font.bold: true
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    opacity: 0.92
                    elide: Text.ElideRight
                }
            }
            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }
            Item
            {
                Layout.preferredWidth: control.genreColWidth
                Layout.fillHeight: true
                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    text: i18n("Genre")
                    font.bold: true
                    opacity: 0.92
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
            Item { Layout.fillWidth: true }
        }
    }

    delegate: Maui.ListBrowserDelegate
    {
        id: rowDelegate

        width: ListView.view.width
        height: 56
        isCurrentItem: ListView.isCurrentItem
        draggable: true
        padding: 0
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0

        readonly property bool isFav: FB.Tagging.isFav(model.url)

        background: Rectangle
        {
            color: rowDelegate.isCurrentItem ? Qt.rgba(0.20, 0.19, 0.26, 0.96) : Qt.rgba(0.17, 0.16, 0.22, rowDelegate.hovered ? 0.90 : 0.72)
            radius: Maui.Style.radiusV
            border.color: rowDelegate.isCurrentItem ? Maui.Theme.highlightColor : (rowDelegate.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.04))
            border.width: rowDelegate.hovered || rowDelegate.isCurrentItem ? 1 : 0
        }

        template.content: RowLayout
        {
            x: control.rowPadding
            y: 0
            width: control.tableAvailableWidth
            height: parent ? parent.height : 0
            spacing: 0

            Item
            {
                Layout.preferredWidth: control.songColWidth
                Layout.fillHeight: true

                RowLayout
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    spacing: Maui.Style.space.small

                    Rectangle
                    {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: 6
                        color: Qt.rgba(1, 1, 1, 0.05)
                        clip: true

                        Image
                        {
                            anchors.fill: parent
                            source: "image://artwork/album:" + model.artist + ":" + model.album
                            fillMode: Image.PreserveAspectCrop
                        }
                    }

                    Label
                    {
                        Layout.fillWidth: true
                        text: model.title
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }

            Item
            {
                Layout.preferredWidth: control.artistColWidth
                Layout.fillHeight: true

                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    text: model.artist
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }

            Item
            {
                Layout.preferredWidth: control.albumColWidth
                Layout.fillHeight: true

                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    text: model.album
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }

            Item
            {
                Layout.preferredWidth: control.yearColWidth
                Layout.fillHeight: true

                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    text: control.yearLabel(model.releasedate)
                    elide: Text.ElideRight
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }

            Item
            {
                Layout.preferredWidth: control.lengthColWidth
                Layout.fillHeight: true

                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    text: control.formatDuration(model.duration)
                    elide: Text.ElideRight
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }

            Item
            {
                Layout.preferredWidth: control.favColWidth
                Layout.fillHeight: true

                ToolButton
                {
                    anchors.centerIn: parent
                    icon.name: rowDelegate.isFav ? "love" : "love-outline"
                    onClicked: listModel.list.fav(listModel.mappedToSource(index), !rowDelegate.isFav)
                    flat: true
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.05) }

            Item
            {
                Layout.preferredWidth: control.genreColWidth
                Layout.fillHeight: true

                Label
                {
                    anchors.fill: parent
                    anchors.leftMargin: control.cellPadding
                    anchors.rightMargin: control.cellPadding
                    text: model.genre
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Item { Layout.fillWidth: true }
        }

        onClicked:
        {
            currentIndex = index
            rowClicked(index)
        }

        onDoubleClicked:
        {
            currentIndex = index
            rowClicked(index)
        }

        onRightClicked:
        {
            currentIndex = index
            openItemMenu(index)
        }

        onPressAndHold:
        {
            if (Maui.Handy.isTouch)
            {
                currentIndex = index
                openItemMenu(index)
            }
        }
    }

    onRowClicked: (index) => Player.quickPlay(listModel.get(index))
    onAppendTrack: (index) => Player.addTrack(listModel.get(index))
    onQueueTrack:(index) => Player.queueTracks([listModel.get(index)], index)

    onPlayAll: Player.playAllModel(listModel.list)
    onAppendAll: Player.appendAllModel(listModel.list)
    onShuffleAll: Player.shuffleAllModel(listModel.list)
}
