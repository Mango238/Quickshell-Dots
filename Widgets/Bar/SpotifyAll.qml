import QtQuick
import QtQuick.Controls
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.Services
import qs.Commons
import qs.Widgets.General

Item {
    id: spotAll

    property var player: SpotifyInfo.activePlayer
    property var trackData: SpotifyInfo.trackData

    readonly property var pal: SpotifyInfo.albumPalette
    readonly property color textColor: OrderColors.getReadableTextColor(pal[4])
    property color accent: pal[8]

    // Mpris no reevalúa los bindings de position por sí solo: hay que
    // emitir positionChanged() periódicamente mientras reproduce.
    Timer {
        interval: 500
        running: spotAll.visible && (spotAll.player?.isPlaying ?? false)
        repeat: true
        onTriggered: spotAll.player.positionChanged()
    }

    // Rueda del ratón sobre cualquier punto del panel = volumen
    WheelHandler {
        enabled: spotAll.player?.volumeSupported ?? false
        onWheel: (event) => {
            const delta = event.angleDelta.y > 0 ? 0.05 : -0.05
            spotAll.player.volume =
                Math.max(0, Math.min(1, spotAll.player.volume + delta))
        }
    }

    function cycleLoop() {
        if (!player?.loopSupported)
            return
        player.loopState = player.loopState === MprisLoopState.None
            ? MprisLoopState.Playlist
            : player.loopState === MprisLoopState.Playlist
                ? MprisLoopState.Track
                : MprisLoopState.None
    }

    // ── Sin player activo ──────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: !spotAll.player
        text: "Nada sonando"
        color: spotAll.textColor
        font.pixelSize: 16
    }

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 14
        visible: !!spotAll.player

        // ── Carátula ───────────────────────────────────────────────
        Item {
            id: coverStack
            height: parent.height
            width: height
            clip: false   // explícito: este contenedor NO debe recortar

            AlbumArt {
                anchors.centerIn: parent
                // más grande que el cover para que el blob asome por los bordes
                width: parent.width
                height: width
                z: 0
                accentColor: Colors.ensureReadable(pal[5], accent, 2.5)
            }

            ClippingRectangle {
                id: cover
                anchors.fill: parent
                radius: 70
                color: Qt.alpha(spotAll.textColor, 0.1)
                z: 1

                Image {
                    anchors.fill: parent
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop

                    readonly property url fallback: Qt.resolvedUrl("../../Assets/No_cover.jpg")
                    // Si la carga de la carátula remota falla (sin red), cae al
                    // fallback local en vez de quedar en blanco. loadFailed se
                    // resetea al cambiar de track.
                    readonly property string remoteImage: spotAll.trackData.image
                    property bool loadFailed: false
                    onRemoteImageChanged: loadFailed = false
                    source: (remoteImage && !loadFailed) ? remoteImage : fallback
                    onStatusChanged: if (status === Image.Error) loadFailed = true
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: spotAll.player?.canRaise ?? false
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: spotAll.player.raise()
                }
            }
        }

        // ── Título, controles, progreso y volumen ─────────────────
        Column {
            width: parent.width - cover.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                width: parent.width
                text: spotAll.trackData.title + " - " + spotAll.trackData.artist
                color: spotAll.textColor
                font.bold: true
                font.pixelSize: 14
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 22

                MediaButton {
                    visible: spotAll.player?.shuffleSupported ?? false
                    text: "󰒝"
                    font.pixelSize: 15
                    baseColor: Qt.alpha(spotAll.textColor, 0.6)
                    activeColor: spotAll.accent
                    active: spotAll.player?.shuffle ?? false
                    onActivated: spotAll.player.shuffle = !spotAll.player.shuffle
                }

                MediaButton {
                    text: "󰒮"
                    baseColor: spotAll.textColor
                    enabled: spotAll.player?.canGoPrevious ?? false
                    onActivated: spotAll.player.previous()
                }

                MediaButton {
                    text: (spotAll.player?.isPlaying ?? false) ? "󰏤" : "󰐊"
                    font.pixelSize: 24
                    baseColor: spotAll.textColor
                    enabled: spotAll.player?.canTogglePlaying ?? false
                    onActivated: spotAll.player.togglePlaying()
                }

                MediaButton {
                    text: "󰒭"
                    baseColor: spotAll.textColor
                    enabled: spotAll.player?.canGoNext ?? false
                    onActivated: spotAll.player.next()
                }

                MediaButton {
                    visible: spotAll.player?.loopSupported ?? false
                    text: (spotAll.player?.loopState ?? MprisLoopState.None)
                              === MprisLoopState.Track ? "󰑘" : "󰑖"
                    font.pixelSize: 15
                    baseColor: Qt.alpha(spotAll.textColor, 0.6)
                    activeColor: spotAll.accent
                    active: (spotAll.player?.loopState ?? MprisLoopState.None)
                                !== MprisLoopState.None
                    onActivated: spotAll.cycleLoop()
                }
            }

            // Progreso: 0:42 ────────●──── 3:15
            Row {
                width: parent.width
                spacing: 8

                Text {
                    id: posLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: SpotifyInfo.formatTime(spotAll.player?.position)
                    color: Qt.alpha(spotAll.textColor, 0.7)
                    font.pixelSize: 10
                    font.family: "Monospace"
                }

                Slider {
                    id: progress
                    width: parent.width - posLabel.width - lenLabel.width
                           - parent.spacing * 2
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: spotAll.player?.length ?? 1
                    enabled: spotAll.player?.canSeek ?? false

                    // No enlazar value directamente: la interacción del
                    // usuario rompería el binding. Binding condicional.
                    Binding {
                        target: progress
                        property: "value"
                        value: spotAll.player?.position ?? 0
                        when: !progress.pressed
                        // Qt6 cambió el default a RestoreBindingOrValue, que al
                        // presionar restauraba el valor previo → salto del handle.
                        restoreMode: Binding.RestoreNone
                    }

                    onPressedChanged: {
                        if (!pressed && spotAll.player?.canSeek)
                            spotAll.player.position = value
                    }

                    background: Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: progress.width
                        height: 4
                        radius: 2
                        color: Qt.alpha(spotAll.textColor, 0.25)

                        Rectangle {
                            width: progress.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: spotAll.accent
                        }
                    }

                    handle: Rectangle {
                        x: progress.visualPosition * (progress.width - width)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 5
                        color: spotAll.textColor
                        visible: progress.enabled
                    }
                }

                Text {
                    id: lenLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: SpotifyInfo.formatTime(spotAll.player?.length)
                    color: Qt.alpha(spotAll.textColor, 0.7)
                    font.pixelSize: 10
                    font.family: "Monospace"
                }
            }

            // Volumen: 󰕾 ──────●──
            Row {
                width: parent.width * 0.6
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                visible: spotAll.player?.volumeSupported ?? false

                Text {
                    id: volIcon
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰕾"
                    color: Qt.alpha(spotAll.textColor, 0.7)
                    font.pixelSize: 12
                }

                Slider {
                    id: volume
                    width: parent.width - volIcon.width - parent.spacing
                    height: 12
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: 1

                    Binding {
                        target: volume
                        property: "value"
                        value: spotAll.player?.volume ?? 0
                        when: !volume.pressed
                        restoreMode: Binding.RestoreNone
                    }

                    onMoved: spotAll.player.volume = value

                    background: Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: volume.width
                        height: 3
                        radius: 1.5
                        color: Qt.alpha(spotAll.textColor, 0.25)

                        Rectangle {
                            width: volume.visualPosition * parent.width
                            height: parent.height
                            radius: 1.5
                            color: Qt.alpha(spotAll.accent, 0.8)
                        }
                    }

                    handle: Rectangle {
                        x: volume.visualPosition * (volume.width - width)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: spotAll.textColor
                    }
                }
            }
        }
    }
}
