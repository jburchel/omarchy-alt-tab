import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons // qmllint disable import

// One window in the switcher: title row over a live preview, or a large app
// icon in icon mode. The selected card gets the theme accent.
Rectangle {
    id: card

    property var toplevel: null
    property string iconSource: ""
    property string workspace: ""
    property bool selected: false
    property bool previews: true
    property bool live: false

    signal hovered()
    signal clicked()

    readonly property int inset: Math.max(Style.space(6), Math.round(width * 0.035))
    readonly property string title: {
        var t = card.toplevel ? String(card.toplevel.title || "") : "";
        if (t)
            return t;
        var ipc = card.toplevel && card.toplevel.lastIpcObject ? card.toplevel.lastIpcObject : {};
        return String(ipc.class || "Window");
    }

    radius: Style.cornerRadius
    color: card.selected ? Style.selectedAccentFill : (hover.containsMouse ? Style.hoverFill : "transparent")
    border.width: Math.max(2, Style.space(3))
    border.color: card.selected ? Color.accent : "transparent"

    // Title row (previews mode).
    Row {
        id: titleRow
        visible: card.previews
        x: card.inset
        y: card.inset
        width: card.width - card.inset * 2
        spacing: Style.spacing.md

        Image {
            id: smallIcon
            width: Math.round(Style.font.heading * 1.25)
            height: width
            source: card.iconSource
            sourceSize: Qt.size(width * 2, height * 2)
            asynchronous: true
            smooth: true
        }
        Text {
            width: titleRow.width - smallIcon.width - titleRow.spacing
            anchors.verticalCenter: smallIcon.verticalCenter
            text: card.title
            elide: Text.ElideRight
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            font.bold: card.selected
        }
    }

    // Preview area.
    Rectangle {
        id: previewFrame
        visible: card.previews
        x: card.inset
        y: titleRow.y + titleRow.height + Style.spacing.md
        width: card.width - card.inset * 2
        height: card.height - y - card.inset
        radius: Math.max(0, Style.cornerRadius - Style.spacing.xs)
        color: Util.alpha(Color.foreground, 0.05)
        clip: true

        ScreencopyView {
            id: preview
            readonly property real sourceAspect: sourceSize.width > 0 && sourceSize.height > 0
                ? sourceSize.width / sourceSize.height : previewFrame.width / Math.max(1, previewFrame.height)
            readonly property real frameAspect: previewFrame.width / Math.max(1, previewFrame.height)
            anchors.centerIn: parent
            width: sourceAspect >= frameAspect ? previewFrame.width : Math.round(previewFrame.height * sourceAspect)
            height: sourceAspect >= frameAspect ? Math.round(previewFrame.width / sourceAspect) : previewFrame.height
            captureSource: card.previews && card.toplevel && card.toplevel.wayland ? card.toplevel.wayland : null
            live: card.live
            paintCursor: false
        }

        // Fallback while no frame has arrived (or capture is unavailable).
        Image {
            visible: !preview.hasContent
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.4
            height: width
            source: card.iconSource
            sourceSize: Qt.size(width * 2, height * 2)
            asynchronous: true
            opacity: 0.8
        }
    }

    // Icon mode.
    Column {
        visible: !card.previews
        anchors.centerIn: parent
        width: card.width - card.inset * 2
        spacing: Style.spacing.md

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(Math.min(card.width, card.height) * 0.46)
            height: width
            source: card.iconSource
            sourceSize: Qt.size(width * 2, height * 2)
            asynchronous: true
            smooth: true
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: card.title
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: card.selected
        }
    }

    // Workspace badge.
    Rectangle {
        visible: card.workspace !== ""
        readonly property int margin: Math.round(card.inset * 0.6)
        // On the preview's corner in previews mode, the card's otherwise.
        x: card.previews ? previewFrame.x + previewFrame.width - width - margin : card.width - width - margin
        y: card.previews ? previewFrame.y + margin : margin
        width: Math.max(height, badgeText.implicitWidth + Style.spacing.lg)
        height: badgeText.implicitHeight + Style.spacing.xs
        radius: Math.min(height / 2, Style.cornerRadius)
        color: card.selected ? Color.accent : Color.menu.background
        border.width: 1
        border.color: card.selected ? Color.accent : Util.alpha(Color.foreground, 0.35)
        z: 3

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: card.workspace
            color: card.selected ? Color.background : Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        // Only real pointer motion selects, so a card that appears under a
        // resting cursor does not steal the keyboard selection.
        onPositionChanged: card.hovered()
        onClicked: card.clicked()
    }
}
