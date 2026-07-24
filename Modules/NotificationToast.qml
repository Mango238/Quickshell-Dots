pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import qs.Services
import qs.Commons
import qs.Widgets.Bar

/**
 * NotificationToast.qml — Stack de hasta 3 toasts flotantes top-right por
 * monitor. Solo el monitor con foco de Hyprland recibe el toast entrante
 * (Hyprland.focusedMonitor.name === screen.name al momento de llegar, mismo
 * patrón de captura que PopupState.screenName); si no hay IPC de foco
 * (focusedMonitor null), fallback: se muestra en todos los monitores.
 * Autocierre por urgencia (Low 3s / Normal 5s / Critical sin autocierre),
 * salvo que el emisor pida su propio expireTimeout > 0 (tiene prioridad).
 */
Scope {
    id: scope

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: toastWindow
                required property var modelData
                screen: modelData

                Component.onCompleted: {
                    if (this.WlrLayershell != null) {
                        this.WlrLayershell.layer = WlrLayer.Overlay
                        this.WlrLayershell.namespace = "notification-toast"
                    }
                }

                color: "transparent"
                exclusiveZone: 0

                anchors {
                    top: true
                    right: true
                }
                margins {
                    top: 12
                    right: 12
                }

                implicitWidth: 340
                implicitHeight: Math.max(1, stackCol.implicitHeight)

                // Más nuevo primero; los más viejos se caen al superar 3.
                property var toastStack: []

                Connections {
                    target: NotificationService
                    function onToastReceived(notif) {
                        var focused = Hyprland.focusedMonitor
                        if (focused && focused.name !== toastWindow.screen.name) return
                        toastWindow.toastStack = [notif].concat(toastWindow.toastStack).slice(0, 3)
                    }
                }

                // Comparar por (id, timestamp) en vez de identidad de objeto (!==):
                // el Repeater entrega modelData como una copia del elemento del array
                // JS, no la misma referencia, así que "n !== notif" nunca coincide.
                // Mismo criterio de identidad que NotificationService._clearNotifRef.
                function dismissToast(notif) {
                    toastWindow.toastStack = toastWindow.toastStack.filter(function(n) {
                        return !(n.id === notif.id && n.timestamp === notif.timestamp)
                    })
                }

                function timeoutFor(n) {
                    if (n.notifRef && n.notifRef.expireTimeout > 0) return n.notifRef.expireTimeout
                    if (n.urgency === NotificationUrgency.Low) return 3000
                    if (n.urgency === NotificationUrgency.Critical) return -1
                    return 5000
                }

                function iconFor(n) {
                    if (n.notifRef && n.image && n.image.length > 0) return n.image
                    if (n.appIcon && /^(\/|file:|https?:)/.test(n.appIcon)) return n.appIcon
                    // iconPath(name, true) devuelve "" si el icono no existe:
                    // sin icono real, mejor ocultar que mostrar el placeholder
                    // roto del provider.
                    var entry = ThemeIcons.findAppEntry(n.appName)
                    if (entry && entry.icon) return Quickshell.iconPath(entry.icon, true)
                    if (n.appIcon) return Quickshell.iconPath(n.appIcon, true)
                    return ""
                }

                Column {
                    id: stackCol
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: toastWindow.toastStack

                        delegate: Rectangle {
                            id: card
                            required property var modelData

                            width: stackCol.width
                            height: contentCol.implicitHeight + 20
                            radius: 12
                            color: Colors.palette[4]
                            border.color: modelData.urgency === NotificationUrgency.Critical
                                          ? Colors.danger : Colors.palette[7]
                            border.width: modelData.urgency === NotificationUrgency.Critical ? 2 : 1

                            Timer {
                                interval: toastWindow.timeoutFor(card.modelData)
                                running: interval > 0
                                onTriggered: toastWindow.dismissToast(card.modelData)
                            }

                            Column {
                                id: contentCol
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Row {
                                    width: parent.width
                                    spacing: 10

                                    Image {
                                        id: toastIcon
                                        width: 36
                                        height: 36
                                        visible: source !== ""
                                        source: toastWindow.iconFor(card.modelData)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }

                                    Column {
                                        width: parent.width - (toastIcon.visible ? toastIcon.width + parent.spacing : 0)
                                        spacing: 2

                                        Text {
                                            width: parent.width
                                            text: card.modelData.appName
                                            color: Colors.palette[7]
                                            font.pixelSize: 11
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            text: card.modelData.summary
                                            color: Colors.palette[7]
                                            font.pixelSize: 13
                                            font.bold: true
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            visible: card.modelData.body && card.modelData.body.length > 0
                                            text: card.modelData.body
                                            textFormat: Text.StyledText
                                            color: Qt.alpha(Colors.palette[7], 0.8)
                                            font.pixelSize: 11
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 3
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 6
                                    visible: card.modelData.notifRef && card.modelData.notifRef.actions.length > 0

                                    Repeater {
                                        model: card.modelData.notifRef ? card.modelData.notifRef.actions : []

                                        delegate: BluetoothActionButton {
                                            required property var modelData
                                            label: modelData.text
                                            accentColor: Colors.accent
                                            onClicked: {
                                                modelData.invoke()
                                                toastWindow.dismissToast(card.modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (card.modelData.notifRef) {
                                        var actions = card.modelData.notifRef.actions
                                        for (var i = 0; i < actions.length; i++) {
                                            if (actions[i].identifier === "default") {
                                                actions[i].invoke()
                                                break
                                            }
                                        }
                                    }
                                    toastWindow.dismissToast(card.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
