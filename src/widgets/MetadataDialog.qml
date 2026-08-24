import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing as FB
import org.maui.vvave

Maui.SettingsDialog
{
    id: control

    property string _url: ""
    property int _proxyIndex: -1
    property var _proxyModel: null
    property var _sourceModel: null
    property string _artworkAction: "keep"
    property url _artworkUrl: ""
    property url _currentArtworkUrl: ""
    property var _initialValues: null

    readonly property real _fieldWidth: Maui.Style.units.gridUnit * 13
    readonly property real _trackSpinWidth: Maui.Style.units.gridUnit * 7
    readonly property real _yearComboWidth: Maui.Style.units.gridUnit * 7
    readonly property var _yearModel: {
        const years = [""]
        for (let year = 1900; year <= 2100; ++year)
            years.push(String(year))
        return years
    }

    signal edited(var data, int index, var proxyModel, var sourceModel)

    Maui.Controls.title: i18n("Edit Metadata")
    maxWidth: (control._fieldWidth * 2) + Maui.Style.defaultSpacing
              + (Maui.Style.contentMargins * 4)
              + (Maui.Style.defaultPadding * 2)
    maxHeight: 760
    closeButtonVisible: true
    closePolicy: Popup.NoAutoClose

    function textValue(value)
    {
        if (value === undefined || value === null)
            return ""

        const result = String(value)
        return result.toUpperCase() === "UNKNOWN" ? "" : result
    }

    function hasChanges()
    {
        if (!control._initialValues)
            return false

        return _titleField.text !== control._initialValues.title
                || _artistField.text !== control._initialValues.artist
                || _albumField.text !== control._initialValues.album
                || _trackField.value !== control._initialValues.track
                || _genreField.text !== control._initialValues.genre
                || _yearField.currentIndex !== control._initialValues.yearIndex
                || control._artworkAction !== "keep"
    }

    function requestEscapeClose()
    {
        if (control.hasChanges())
            _discardChangesDialog.open()
        else
            control.close()
    }

    function albumArtworkSource(item)
    {
        if (item && item.artwork)
            return String(item.artwork)

        const artist = control.textValue(item ? item.artist : "").trim()
        const album = control.textValue(item ? item.album : "").trim()
        if (!artist.length || !album.length)
            return ""

        return "image://artwork/album:" + encodeURIComponent(artist)
                + ":" + encodeURIComponent(album)
    }

    function openFor(item, proxyModel, sourceModel, index)
    {
        if (!item || !item.url || !proxyModel || !sourceModel || index < 0)
        {
            return false
        }

        control._url = control.textValue(item.url)
        control._proxyIndex = index
        control._proxyModel = proxyModel
        control._sourceModel = sourceModel
        control._artworkAction = "keep"
        control._artworkUrl = ""
        _metadataReader.url = control._url
        control._currentArtworkUrl = _metadataReader.artwork.length > 0
                                     ? _metadataReader.artwork
                                     : control.albumArtworkSource(item)

        _titleField.text = control.textValue(item.title)
        _artistField.text = control.textValue(item.artist)
        _albumField.text = control.textValue(item.album)
        _trackField.value = Math.max(0, Number(item.track || 0))
        _genreField.text = control.textValue(item.genre)
        const year = Number(item.releasedate || 0)
        _yearField.currentIndex = year >= 1900 && year <= 2100
                                  ? year - 1899
                                  : 0

        control._initialValues = {
            "title": _titleField.text,
            "artist": _artistField.text,
            "album": _albumField.text,
            "track": _trackField.value,
            "genre": _genreField.text,
            "yearIndex": _yearField.currentIndex
        }

        control.open()
        return true
    }

    function chooseArtwork()
    {
        _artworkFileDialog.currentPath = FB.FM.homePath()
        _artworkFileDialog.open()
    }

    function commit()
    {
        if (!control._url || control._proxyIndex < 0
                || !control._proxyModel || !control._sourceModel)
        {
            return
        }

        const editedData = {
            "url": control._url,
            "title": _titleField.text.trim(),
            "artist": _artistField.text.trim(),
            "album": _albumField.text.trim(),
            "track": String(_trackField.value),
            "genre": _genreField.text.trim(),
            "releasedate": _yearField.currentIndex > 0
                           ? String(_yearField.currentIndex + 1899)
                           : "",
            "artworkAction": control._artworkAction,
            "artworkUrl": String(control._artworkUrl)
        }

        if (control._artworkAction === "replace")
            editedData.artwork = String(control._artworkUrl)

        control.edited(editedData, control._proxyIndex,
                       control._proxyModel, control._sourceModel)
        control.close()
    }

    function clearSource()
    {
        control._url = ""
        control._proxyIndex = -1
        control._proxyModel = null
        control._sourceModel = null
        control._artworkAction = "keep"
        control._artworkUrl = ""
        control._currentArtworkUrl = ""
        control._initialValues = null
        _metadataReader.url = ""
    }

    actions: [
        Action
        {
            text: i18n("Cancel")
            onTriggered: control.close()
        },
        Action
        {
            text: i18n("Save")
            enabled: control._proxyIndex >= 0 && _titleField.text.trim().length > 0
            onTriggered: control.commit()
        }
    ]

    onClosed:
    {
        control.clearSource()
    }

    Shortcut
    {
        sequences: [StandardKey.Cancel]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: control.opened
                 && !_discardChangesDialog.opened
                 && !_artworkFileDialog.opened
        onActivated: control.requestEscapeClose()
    }

    Maui.InfoDialog
    {
        id: _discardChangesDialog
        modal: true
        title: i18n("Unsaved Changes")
        message: i18n("The metadata has changed. Do you want to discard your changes?")
        template.iconSource: "dialog-warning"
        standardButtons: Dialog.Discard | Dialog.Cancel
        Component.onCompleted:
        {
            standardButton(Dialog.Discard).text = i18n("Discard Changes")
            standardButton(Dialog.Cancel).text = i18n("Continue Editing")
        }
        onDiscarded:
        {
            close()
            control.close()
        }
    }

    MetadataEditor
    {
        id: _metadataReader
    }

    FB.FileDialog
    {
        id: _artworkFileDialog
        mode: FB.FileDialog.Modes.Open
        singleSelection: true
        browser.settings.filters: ["*.jpg", "*.jpeg", "*.png"]
        callback: (paths) =>
        {
            if (!paths || paths.length === 0)
                return

            control._artworkUrl = String(paths[0])
            control._artworkAction = "replace"
        }
    }

    Maui.SectionGroup
    {
        RowLayout
        {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: _artworkPreview.showingFallback ? 0 : Maui.Style.space.large

            ArtworkItem
            {
                id: _artworkPreview
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 160
                Layout.preferredHeight: 160
                imageSizeHint: 160
                iconSizeHint: 96
                maskRadius: Maui.Style.radiusV
                imageSource: control._artworkAction === "replace"
                             ? control._artworkUrl
                             : control._currentArtworkUrl
            }
        }

        Maui.FlexSectionItem
        {
            wide: true
            label1.text: i18n("Album artwork")
            label2.text: i18n("Choose a JPEG or PNG image. It will be embedded in this track and shown for the album.")

            Button
            {
                text: i18n("Choose")
                display: AbstractButton.TextOnly
                onClicked: control.chooseArtwork()
            }
        }
    }

    Maui.SectionGroup
    {
        title: i18n("Basic Information")
        description: i18n("Identify the track and the album it belongs to.")

        ColumnLayout
        {
            Layout.fillWidth: true
            spacing: Maui.Style.space.small

            Maui.FlexSectionItem
            {
                wide: true
                label1.text: i18n("Title")
                label2.text: i18n("The name of this track.")

                TextField
                {
                    id: _titleField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: control._fieldWidth
                    Layout.maximumWidth: control._fieldWidth
                    placeholderText: i18n("Track title")
                }
            }

            Maui.FlexSectionItem
            {
                wide: true
                label1.text: i18n("Artist")
                label2.text: i18n("The primary performer of this track.")

                TextField
                {
                    id: _artistField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: control._fieldWidth
                    Layout.maximumWidth: control._fieldWidth
                    placeholderText: i18n("Artist name")
                }
            }

            Maui.FlexSectionItem
            {
                wide: true
                label1.text: i18n("Album")
                label2.text: i18n("The release that contains this track.")

                TextField
                {
                    id: _albumField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: control._fieldWidth
                    Layout.maximumWidth: control._fieldWidth
                    placeholderText: i18n("Album title")
                }
            }
        }
    }

    Maui.SectionGroup
    {
        title: i18n("Release Details")
        description: i18n("Describe where this track appears within the release.")

        ColumnLayout
        {
            Layout.fillWidth: true
            spacing: Maui.Style.space.small

            Maui.FlexSectionItem
            {
                wide: true
                label1.text: i18n("Genre")
                label2.text: i18n("The musical style used to categorize the track.")

                TextField
                {
                    id: _genreField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: control._fieldWidth
                    Layout.maximumWidth: control._fieldWidth
                    placeholderText: i18n("Genre")
                }
            }

            Maui.FlexSectionItem
            {
                wide: true
                label1.text: i18n("Track Number")
                label2.text: i18n("The track position within the album.")

                SpinBox
                {
                    id: _trackField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: control._trackSpinWidth
                    Layout.maximumWidth: control._trackSpinWidth
                    editable: true
                    from: 0
                    to: 999
                }
            }

            Maui.FlexSectionItem
            {
                wide: true
                label1.text: i18n("Year")
                label2.text: i18n("The year this track or album was released.")

                ComboBox
                {
                    id: _yearField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: control._yearComboWidth
                    Layout.maximumWidth: control._yearComboWidth
                    model: control._yearModel
                    popup.height: Math.min(popup.implicitHeight, Maui.Style.rowHeight * 8)
                }
            }
        }
    }
}
