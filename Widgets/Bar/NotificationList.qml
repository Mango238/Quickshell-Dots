pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Services
import qs.Commons

/**
 * NotificationList.qml — Historial de notificaciones para el PanelPopup.
 * Mismo lenguaje visual que WallpaperGrid.qml/BluetoothDeviceList.qml:
 * cardColor = palette[3], texto/borde = palette[7], borde fino = palette[8].
 */
Item {
    id: root

    property color textColor: Colors.palette[7]
    property color subTextColor: Qt.alpha(Colors.palette[7], 0.6)
    property color cardColor: Colors.palette[3]
    property color borderColor: Colors.palette[8]

    // Timestamp relativo: _now se toca cada 60s para forzar reevaluación de
    // relativeTime() en los delegates (función JS pura sobre Date.now(), sin
    // binding reactivo propio).
    property real _now: Date.now()
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root._now = Date.now()
    }

    function relativeTime(ts) {
        var diffMin = Math.floor((root._now - ts) / 60000)
        if (diffMin < 1) return "ahora"
        if (diffMin < 60) return "hace " + diffMin + " min"
        var diffH = Math.floor(diffMin / 60)
        if (diffH < 24) return "hace " + diffH + " h"
        var diffD = Math.floor(diffH / 24)
        return diffD === 1 ? "ayer" : ("hace " + diffD + " d")
    }

    // Misma prioridad que NotificationToast: imagen viva > appIcon si parece
    // ruta/URL > resuelto por ThemeIcons contra el icon theme instalado.
    function iconFor(n) {
        if (n.notifRef && n.image && n.image.length > 0) return n.image
        if (n.appIcon && /^(\/|file:|https?:)/.test(n.appIcon)) return n.appIcon
        // iconPath(name, true) devuelve "" si el icono no existe: sin icono
        // real, mejor ocultar que mostrar el placeholder roto del provider.
        var entry = ThemeIcons.findAppEntry(n.appName)
        if (entry && entry.icon) return Quickshell.iconPath(entry.icon, true)
        if (n.appIcon) return Quickshell.iconPath(n.appIcon, true)
        return ""
    }

    Column {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            id: header
            width: parent.width
            spacing: 8

            Text {
                text: "Notificaciones"
                color: root.textColor
                font.pixelSize: 15
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Text {
                text: NotificationService.dndEnabled ? "󰂛" : "󰂚"
                color: NotificationService.dndEnabled ? Colors.accent : root.subTextColor
                font.pixelSize: 15

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.toggleDnd()
                }
            }

            Text {
                text: "Limpiar todo"
                color: root.subTextColor
                font.pixelSize: 11

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.clearHistory()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.darker(root.cardColor, 1.3)
        }

        Text {
            visible: NotificationService.history.length === 0
            width: parent.width
            text: "Sin notificaciones."
            color: root.subTextColor
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
        }

        ListView {
            width: parent.width
            height: parent.height - header.height - 24
            clip: true
            spacing: 6
            model: NotificationService.history

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Rectangle {
                required property var modelData
                required property int index

                width: ListView.view.width
                height: rowContent.implicitHeight + 16
                radius: 8
                color: root.cardColor
                border.color: root.borderColor
                border.width: 1

                RowLayout {
                    id: rowContent
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Image {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        visible: source !== ""
                        source: root.iconFor(modelData)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: modelData.appName + " — " + modelData.summary
                                color: root.textColor
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: root.relativeTime(modelData.timestamp)
                                color: root.subTextColor
                                font.pixelSize: 10
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: modelData.body && modelData.body.length > 0
                            text: modelData.body
                            textFormat: Text.StyledText
                            color: root.subTextColor
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: !!(modelData.notifRef && modelData.notifRef.actions.length > 0)

                            Repeater {
                                model: modelData.notifRef ? modelData.notifRef.actions : []

                                delegate: BluetoothActionButton {
                                    required property var modelData
                                    label: modelData.text
                                    accentColor: Colors.accent
                                    onClicked: modelData.invoke()
                                }
                            }
                        }
                    }

                    Text {
                        text: "✕"
                        color: root.subTextColor
                        font.pixelSize: 12

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationService.dismissAt(index)
                        }
                    }
                }
            }
        }
    }
}
