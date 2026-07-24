import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Services

Item {
    id: root

    readonly property MprisPlayer activePlayer: {
        // Busca Spotify (cliente oficial), luego Spotifyd (daemon
        // ligero via Spotify Connect), o el primer player disponible
        for (const p of Mpris.players.values) {
            if (p.identity === "Spotify") return p;
        }
        for (const p of Mpris.players.values) {
            if (p.identity === "Spotifyd") return p;
        }
        return Mpris.players.values[0] ?? null;
    }

    readonly property bool isPlaying: activePlayer !== null && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property bool live: visible && isPlaying

    width: 20
    height: 10

    readonly property real maxBarHeight: height - 2
    readonly property real minBarHeight: 3
    readonly property color barColor: "#fff"

    onLiveChanged: {
        if (!live) {
            bars.bandsA = Qt.vector4d(0, 0, 0, 0);
            bars.bandsB = Qt.vector2d(0, 0);
        }
    }

    Loader {
        active: root.live
        sourceComponent: Component {
            Ref {
                service: CavaService
            }
        }
    }

    Timer {
        running: !CavaService.cavaAvailable && root.live
        interval: 500
        repeat: true
        onTriggered: {
            CavaService.values = [Math.random() * 20 + 5, Math.random() * 25 + 8, Math.random() * 22 + 6, Math.random() * 20 + 5, Math.random() * 22 + 6, Math.random() * 25 + 8];
        }
    }

    Connections {
        target: CavaService
        enabled: root.live
        function onValuesChanged() {
            const v = CavaService.values;
            if (v.length < 6)
                return;
            const n = i => {
                const x = v[i];
                return x <= 0 ? 0 : x >= 100 ? 1 : Math.sqrt(x * 0.01);
            };
            bars.bandsA = Qt.vector4d(n(0), n(1), n(2), n(3));
            bars.bandsB = Qt.vector2d(n(4), n(5));
        }
    }

    ShaderEffect {
        id: bars
        anchors.fill: parent

        property real widthPx: width
        property real heightPx: height
        property real minH: root.minBarHeight
        property real maxH: root.maxBarHeight
        property vector4d bandsA: Qt.vector4d(0, 0, 0, 0)
        property vector2d bandsB: Qt.vector2d(0, 0)
        property vector4d fillColor: Qt.vector4d(root.barColor.r, root.barColor.g, root.barColor.b, root.barColor.a)

        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/viz_bars.frag.qsb")
    }
}
