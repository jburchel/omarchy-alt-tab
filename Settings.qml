import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons // qmllint disable import
import qs.Ui // qmllint disable import
import "SettingsModel.js" as SettingsModel

// Omarchy Alt-Tab settings overlay: `omarchy-shell omarchy-alt-tab settings`.
// Up/Down pick a row, Left/Right change it, Space/Enter flip switches,
// Escape closes. Every change is saved immediately.
Item {
    id: root

    property var shell: null
    property var manifest: null
    readonly property string pluginId: String((root.manifest && root.manifest.id) || "io.github.jburchel.omarchy-alt-tab")

    property bool opened: false
    property int cursor: 0

    SettingsStore {
        id: store
        shell: root.shell
        pluginId: root.pluginId
    }

    readonly property var rows: [
        { key: "scope", label: "Windows shown", hint: "Hold Alt and press ` to change this for one switch", options: SettingsModel.SCOPE_OPTIONS },
        { key: "showDelay", label: "Show switcher", hint: "A quick Alt+Tab tap switches without flashing the switcher", options: SettingsModel.DELAY_OPTIONS },
        { key: "style", label: "Cards", hint: "", options: SettingsModel.STYLE_OPTIONS },
        { key: "workspaceBadges", label: "Workspace badges", hint: "Show which workspace each window is on", toggle: true },
        { key: "includeSpecial", label: "Scratchpad windows", hint: "Include windows on special workspaces", toggle: true }
    ]

    function open(payloadJson) {
        root.opened = true;
        root.cursor = 0;
        Qt.callLater(function() { keyCatcher.forceActiveFocus(); });
    }

    function close() {
        root.opened = false;
    }

    function dismiss() {
        root.opened = false;
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide(root.pluginId);
    }

    function valueFor(row) {
        var v = store.values;
        if (row.key === "style")
            return v.previews ? "previews" : "icons";
        if (row.key === "showDelay")
            return String(v.showDelay);
        return v[row.key];
    }

    function apply(row, value) {
        if (row.key === "style")
            store.set("previews", value === "previews");
        else if (row.key === "showDelay")
            store.set("showDelay", Number(value));
        else
            store.set(row.key, value);
    }

    function shift(row, delta) {
        if (row.toggle) {
            store.set(row.key, !store.values[row.key]);
            return;
        }
        var current = String(root.valueFor(row));
        var index = 0;
        for (var i = 0; i < row.options.length; i++)
            if (row.options[i].value === current)
                index = i;
        var next = Math.max(0, Math.min(row.options.length - 1, index + delta));
        root.apply(row, row.options[next].value);
    }

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-alt-tab-settings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: Color.menu.scrim
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }

        BorderSurface {
            id: card
            anchors.centerIn: parent
            width: Style.space(620)
            height: body.implicitHeight + card.contentTopInset + card.contentBottomInset
            radius: Style.cornerRadius
            color: Color.menu.background
            borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
            padding: Style.spacing.panelPadding

            MouseArea { anchors.fill: parent }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true
                Keys.onPressed: function(event) {
                    var row = root.rows[root.cursor];
                    if (event.key === Qt.Key_Escape)
                        root.dismiss();
                    else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_Tab)
                        root.cursor = (root.cursor + 1) % root.rows.length;
                    else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Backtab)
                        root.cursor = (root.cursor + root.rows.length - 1) % root.rows.length;
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_L)
                        root.shift(row, 1);
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_H)
                        root.shift(row, -1);
                    else if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && row.toggle)
                        root.shift(row, 1);
                    else
                        return;
                    event.accepted = true;
                }
            }

            Column {
                id: body
                x: card.contentLeftInset
                y: card.contentTopInset
                width: card.width - card.contentLeftInset - card.contentRightInset
                spacing: Style.spacing.md

                Text {
                    textFormat: Text.PlainText
                    text: "Omarchy Alt-Tab"
                    color: Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Hold Alt, tap Tab to walk through windows, let go to switch. Shift+Tab or arrows go the other way."
                    color: Color.menu.text
                    opacity: 0.65
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.bodySmall
                    bottomPadding: Style.spacing.md
                }

                Repeater {
                    model: root.rows

                    Rectangle {
                        id: rowItem
                        required property var modelData
                        required property int index
                        readonly property bool current: index === root.cursor
                        width: body.width
                        height: rowContent.implicitHeight + Style.spacing.lg * 2
                        radius: Style.cornerRadius
                        color: current ? Color.menu.selectedBackground : "transparent"

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onPositionChanged: root.cursor = rowItem.index
                            onClicked: if (rowItem.modelData.toggle) root.shift(rowItem.modelData, 1)
                        }

                        Item {
                            id: rowContent
                            x: Style.spacing.rowPaddingX
                            width: parent.width - Style.spacing.rowPaddingX * 2
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: Math.max(labels.implicitHeight, control.height)

                            Column {
                                id: labels
                                anchors.left: parent.left
                                anchors.right: control.left
                                anchors.rightMargin: Style.spacing.huge
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.spacing.xxs

                                Text {
                                    textFormat: Text.PlainText
                                    text: rowItem.modelData.label
                                    color: rowItem.current ? Color.menu.selectedText : Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    visible: text !== ""
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: rowItem.modelData.hint
                                    color: Color.menu.text
                                    opacity: 0.55
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }

                            Item {
                                id: control
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: rowItem.modelData.toggle ? toggle.width : group.width
                                height: rowItem.modelData.toggle ? toggle.height : group.height

                                ButtonGroup {
                                    id: group
                                    visible: !rowItem.modelData.toggle
                                    focusable: false
                                    options: rowItem.modelData.options || []
                                    value: String(root.valueFor(rowItem.modelData))
                                    fontFamily: Style.font.menuFamily
                                    fontSize: Style.font.caption
                                    onChanged: function(value) { root.apply(rowItem.modelData, value); }
                                }
                                ToggleSwitch {
                                    id: toggle
                                    visible: !!rowItem.modelData.toggle
                                    checked: root.valueFor(rowItem.modelData) === true
                                    hasCursor: rowItem.current
                                    onToggled: root.shift(rowItem.modelData, 1)
                                }
                            }
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    topPadding: Style.spacing.md
                    text: "↑↓ choose   ←→ change   space toggle   esc close"
                    color: Color.menu.text
                    opacity: 0.45
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                }
            }
        }
    }
}
