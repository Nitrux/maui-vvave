import QtQuick
import QtQuick.Controls

import ".."

import "../../db/Queries.js" as Q

StackView
{
    id: control
    background: null

    property string currentTag: "fav"
    property string tagQuery: Q.GET.playlistTracks_.arg(currentTag)

    readonly property Flickable flickable : currentItem.flickable
    SwipeView.onIsCurrentItemChanged:
    {
        if (SwipeView.isCurrentItem) {
            refreshFavorites()
        }
    }

    initialItem: TracksView
    {
        id: _favTracksView
        list.query: control.tagQuery
        trackNumberVisible: true

        holder.emoji: "love"
        holder.title: i18n("No Favorites!")
        holder.body: i18n("Mark tracks as favorites to see them here")

        headBar.visible: true
        headBar.farLeftContent: Item {}

        Component.onCompleted: control.refreshFavorites()
    }

    function populate(tag, isPublic)
    {
        refreshFavorites()
    }

    function refreshFavorites()
    {
        currentTag = "fav"
        tagQuery = Q.GET.playlistTracks_.arg(currentTag)

        if (currentItem && currentItem.listModel) {
            currentItem.listModel.clearFilters()
        }

        if (currentItem && currentItem.list) {
            currentItem.list.refresh()
        }
    }

    function getGoBackFunc()
    {
        return null
    }
}
