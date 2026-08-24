import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.mauikit.controls as Maui

Maui.InfoDialog
{
    id: control

    property var data: null
    property int index: -1 // index of the item in the model TracksModel
    property var model: null

    signal edited(var data, int index)

    function loadData()
    {
        if (data)
        {
            data = Object.assign({}, data)
            return
        }

        if (!model || typeof model.get !== "function" || index < 0 || index >= Number(model.count || 0))
        {
            data = null
            return
        }

        const item = model.get(index)
        data = item ? Object.assign({}, item) : null
    }

    Component.onCompleted: loadData()
    onModelChanged: loadData()
    onIndexChanged: loadData()

    standardButtons: Dialog.Ok | Dialog.Cancel

    onAccepted:
    {
        if (!control.data)
        {
            control.close()
            return
        }

        control.data.title = _titleField.text;
        control.data.artist = _artistField.text;
        control.data.album = _albumField.text;
        control.data.track = _trackField.text;
        control.data.genre = _genreField.text;
        control.data.releasedate = _yearField.text;
        control.data.comment = _commentField.text;

        control.edited(control.data, control.index)
        control.close()
    }

    onRejected: close()

    Maui.SectionGroup
    {
        id: _template
        title: i18n("Metadata")
        description: i18n("Embedded metadata info.")

        Maui.SectionItem
        {
            label1.text: i18n("Track Title")

            TextField
            {
                id: _titleField
                text: control.data ? control.data.title : ""
                Layout.fillWidth: true
            }
        }

        Maui.SectionItem
        {
            label1.text: i18n("Artist")

            TextField
            {
                id: _artistField
                text: control.data ? control.data.artist : ""
                Layout.fillWidth: true

            }
        }

        Maui.SectionItem
        {
            label1.text: i18n("Album")

            TextField
            {
                id: _albumField
                text: control.data ? control.data.album : ""
                Layout.fillWidth: true

            }
        }

        Maui.SectionItem
        {
            label1.text: i18n("Track")

            TextField
            {
                id: _trackField
                text: control.data ? control.data.track : ""
                Layout.fillWidth: true

            }
        }

        Maui.SectionItem
        {
            label1.text: i18n("Genre")

            TextField
            {
                id: _genreField
                text: control.data ? control.data.genre : ""
                Layout.fillWidth: true

            }
        }

        Maui.SectionItem
        {
            label1.text: i18n("Year")

            TextField
            {
                id: _yearField
                text: control.data ? control.data.releasedate : ""
                Layout.fillWidth: true

            }
        }

        Maui.SectionItem
        {
            label1.text: i18n("Comment")

            TextField
            {
                id: _commentField
                text: control.data ? control.data.comment : ""
                Layout.fillWidth: true

            }
        }
    }
}
