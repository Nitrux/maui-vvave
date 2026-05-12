import QtQuick
import QtQuick.Controls

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing as FB

import org.maui.vvave as Vvave

import "../VVaveTable"

import "../../db/Queries.js" as Q
import "../../utils/Player.js" as Player

StackView
{
    id: control
    background: null

    property string tagQuery

    readonly property Flickable flickable : currentItem.flickable
    readonly property alias tagList : _tagsPage.list

    Component
    {
        id: newTagDialogComponent
        FB.NewTagDialog {onClosed: destroy()}
    }

    initialItem: TagsViewModel
    {
        id: _tagsPage
    }

    Component
    {
        id: _filterListComponent

        VVaveTable
        {
            id: filterList

            property string currentTag //id

            property bool isPublic: true

            signal removeFromTag(string url)

            coverArtVisible: settings.fetchArtwork

            list.query: control.tagQuery
            showTitle: false
            title: currentTag

            holder.emoji: "tag"
            holder.title : title
            holder.body: i18n("No tracks found for this tag")

            headBar.visible: true
            headBar.farLeftContent: ToolButton
            {
                icon.name: "go-previous"
                onClicked: control.pop()
            }

            contextMenuItems: MenuItem
            {
                text: i18n("Remove from tag")
                onTriggered:
                {
                    control.tagList.removeTrack(currentTag, listModel.get(filterList.currentIndex).url)
                    listModel.list.remove(filterList.currentIndex)
                }
            }

            onQueueTrack: (index) => Player.queueTracks([listModel.get(index)], index)
            onRowClicked: (index) => Player.quickPlay(filterList.listModel.get(index))
            onAppendTrack: (index) => Player.addTrack(filterList.listModel.get(index))

            onPlayAll:
            {
                Player.playAllModel(listModel.list)
                control.pop()

                if(filterList.isPublic)
                {
                    root.sync = true
                    root.syncPlaylist = currentTag
                }
            }

            onAppendAll: Player.appendAllModel(listModel.list)
            onShuffleAll: Player.shuffleAllModel(listModel.list)

            Component.onCompleted:
            {
                filterList.isPublic = true
                tagQuery = Q.GET.playlistTracks_.arg(currentTag)
                filterList.listModel.clearFilters()
            }
        }
    }

    function populate(tag, isPublic)
    {
        control.push(_filterListComponent, {'currentTag': tag, 'isPublic': isPublic})
    }

    function getGoBackFunc()
    {
        if (control.depth > 1)
            return () => { control.pop() }
        else
            return null
    }
}
