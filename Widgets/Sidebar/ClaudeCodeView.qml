pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Services

Item {
    id: root

    readonly property color cardColor: Qt.alpha(Colors.palette[3], 0.5)
    readonly property color textColor: "#e6e6e6"

    // ── Cabecera ───────────────────────────────────────────────────────
    Text {
        id: title
        anchors { top: parent.top; left: parent.left }
        text: "Claude Code"
        color: root.textColor
        font.pixelSize: 20
        font.bold: true
    }
    Rectangle {
        id: newChat
        anchors { verticalCenter: title.verticalCenter; right: parent.right }
        height: 28
        width: newChatText.implicitWidth + 20
        radius: 14
        color: newHover.containsMouse ? Qt.alpha(Colors.accent, 0.25) : root.cardColor
        Text {
            id: newChatText
            anchors.centerIn: parent
            text: "󰑐 Nuevo"
            color: root.textColor
            font.pixelSize: 12
        }
        MouseArea {
            id: newHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ClaudeCodeService.reset()
        }
    }

    // ── Historial ──────────────────────────────────────────────────────
    ListView {
        id: chat
        anchors { top: title.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: inputBox.top; bottomMargin: 10 }
        clip: true
        model: ClaudeCodeService.messages
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        onCountChanged: Qt.callLater(() => chat.positionViewAtEnd())

        delegate: Item {
            id: msg
            required property string role
            required property string text
            width: chat.width
            readonly property bool isUser: role === "user"
            readonly property bool isError: role === "error"
            implicitHeight: bubble.height

            Rectangle {
                id: bubble
                width: Math.min(bubbleText.implicitWidth + 24, chat.width * 0.86)
                height: bubbleText.implicitHeight + 18
                radius: 12
                anchors.left: msg.isUser ? undefined : parent.left
                anchors.right: msg.isUser ? parent.right : undefined
                color: msg.isUser ? Colors.accent
                     : msg.isError ? Qt.alpha(Colors.danger, 0.9)
                     : root.cardColor

                Text {
                    id: bubbleText
                    anchors { left: parent.left; right: parent.right; margins: 12; verticalCenter: parent.verticalCenter }
                    text: msg.text
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    color: msg.isUser ? Colors.accentText : root.textColor
                    font.pixelSize: 13
                    onLinkActivated: (url) => Qt.openUrlExternally(url)
                }
            }
        }

        // Indicador "pensando…" mientras corre el turno
        footer: Item {
            width: chat.width
            height: ClaudeCodeService.busy ? 30 : 0
            visible: ClaudeCodeService.busy
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "󰔟 pensando…"
                color: root.textColor
                opacity: 0.6
                font.pixelSize: 13
            }
        }
    }

    // ── Input ──────────────────────────────────────────────────────────
    Rectangle {
        id: inputBox
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.max(44, input.implicitHeight + 20)
        radius: 12
        color: root.cardColor
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? Colors.accent : Qt.rgba(1, 1, 1, 0.12)
        opacity: ClaudeCodeService.busy ? 0.6 : 1.0

        TextEdit {
            id: input
            anchors { left: parent.left; right: sendBtn.left; margins: 12; verticalCenter: parent.verticalCenter }
            color: root.textColor
            font.pixelSize: 14
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            enabled: !ClaudeCodeService.busy

            Text {
                anchors.fill: parent
                text: "Escribí a Claude…  (Enter envía)"
                visible: input.text.length === 0
                color: root.textColor
                opacity: 0.4
                font.pixelSize: 14
            }

            // Enter envía; Shift+Enter inserta salto de línea.
            Keys.onPressed: (event) => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && !(event.modifiers & Qt.ShiftModifier)) {
                    event.accepted = true
                    root._send()
                }
            }
            Component.onCompleted: Qt.callLater(() => input.forceActiveFocus())
        }

        Rectangle {
            id: sendBtn
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            width: 34
            height: 34
            radius: 10
            color: (input.text.trim().length > 0 && !ClaudeCodeService.busy)
                 ? Colors.accent : Qt.alpha(Colors.palette[5], 0.4)
            Text {
                anchors.centerIn: parent
                text: " "
                font.pixelSize: 16
                color: Colors.accentText
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root._send()
            }
        }
    }

    function _send() {
        if (ClaudeCodeService.busy)
            return
        const t = input.text
        if (t.trim() === "")
            return
        ClaudeCodeService.send(t)
        input.text = ""
    }
}
