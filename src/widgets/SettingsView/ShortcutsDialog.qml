import QtQuick
import QtQuick.Controls

import org.mauikit.controls as Maui

Maui.SettingsDialog
{
    id: control

    Maui.Controls.title: i18n("Shortcuts")

    property var shortcutGroups: []

    function parseShortcutKeys(shortcut)
    {
        return shortcut.nativeText
        .split("+")
        .map((key) => key === "" ? "+" : key)
    }

    function buildShortcutGroups()
    {
        const orderedCategories = []
        const grouped = {}

        for (let i = 0; i < shortcuts.length; ++i)
        {
            const sc = shortcuts[i]
            if (!(sc.dialogCategory in grouped)) {
                grouped[sc.dialogCategory] = []
                orderedCategories.push(sc.dialogCategory)
            }

            grouped[sc.dialogCategory].push({
                label: sc.dialogLabel,
                keys: parseShortcutKeys(sc)
            })
        }

        const result = []
        for (const category of orderedCategories) {
            result.push({
                title: category,
                rows: grouped[category]
            })
        }

        shortcutGroups = result
    }

    Repeater
    {
        model: control.shortcutGroups

        delegate: Maui.SectionGroup
        {
            title: i18n(modelData.title)

            Repeater
            {
                model: modelData.rows

                delegate: Maui.FlexSectionItem
                {
                    label1.text: i18n(modelData.label)

                    Maui.ToolActions
                    {
                        id: _actions
                        checkable: false
                        autoExclusive: false
                    }

                    Component
                    {
                        id: _shortcutActionComponent
                        Action {}
                    }

                    Component.onCompleted:
                    {
                        for (let i = 0; i < modelData.keys.length; ++i)
                        {
                            _actions.actions.push(
                                _shortcutActionComponent.createObject(
                                    _actions,
                                    { text: modelData.keys[i] }
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: buildShortcutGroups()
}
