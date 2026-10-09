import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Services

// Animación en los huecos de la barra (port de StreamShader, barra qsbar de
// Ryoku). Un ShaderEffect por hueco; gapX ubica cada píxel en una grilla
// global, así el modo 1 es un marquee continuo entre huecos. Con música
// sonando lee la energía de CavaService y el stream acelera/brilla.
Item {
    id: root

    /// Huecos a rellenar: [{ x1, x2 }] en coordenadas de este Item.
    property var gaps: []
    /// 1 stream · 2 surge · 3 bolt · 4 spark gap · 5 transfer · 6 collider
    property int mode: 3
    property color accent: Colors.accent

    readonly property bool playing: Mpris.players.values.some(p => p.playbackState === MprisPlaybackState.Playing)
    /// Cuánto acelera el reloj con el volumen (0 = velocidad fija).
    property real speedGain: 1.5

    // Análisis de audio portado del blob (AlbumArt.qml updateBands/stepBlob):
    // bandas con ataque/caída + "punch" (rápida − lenta), onsets por spectral
    // flux que patean un resorte con overshoot. cava llega a 25 Hz; el resorte
    // y las bandas se integran en el Timer para que el shader no escalone.
    readonly property real cavaFullScale: 45
    property real energyTarget: 0
    property real energy: 0      // 0..1.15 (overshoot del resorte)
    property real energyVel: 0
    property var smoothed: [0, 0, 0, 0, 0, 0]
    property var slow: [0, 0, 0, 0, 0, 0]
    property var targets: [0, 0, 0, 0, 0, 0]
    property var bands: [0, 0, 0, 0, 0, 0]   // lo que ve el shader
    property var prev: [0, 0, 0, 0, 0, 0]
    readonly property var fluxWeights: [1.0, 1.0, 0.6, 0.6, 0.35, 0.35]
    property real fluxAvg: 0.02
    property real loudCtx: 0.1
    property int beatCooldown: 0

    // Modo 3: los rayos solo caen en golpes fuertes (no en cada kick).
    // Umbral de flux relativo, energía mínima y separación mínima en segundos.
    property real strikeThreshold: 2.2
    property real strikeMinEnergy: 0.45
    property real strikeMinGap: 0.9
    property real strikeAge: 99   // s desde el último rayo (reloj real)
    property int strikeCount: 0   // semilla: cada rayo con otra forma

    // Al pausar solo se apagan los objetivos: el resorte y las bandas bajan solos.
    onPlayingChanged: if (!playing) { energyTarget = 0; targets = [0, 0, 0, 0, 0, 0] }

    Loader {
        active: root.playing
        sourceComponent: Component {
            Ref { service: CavaService }
        }
    }

    Connections {
        target: CavaService
        enabled: root.playing
        function onValuesChanged() {
            const v = CavaService.values
            if (!v || v.length < 6) return
            const s = root.smoothed, sl = root.slow, out = root.targets, p = root.prev, w = root.fluxWeights
            let flux = 0
            for (let i = 0; i < 6; i++) {
                const lv = Math.min(Math.max(v[i], 0), root.cavaFullScale) / root.cavaFullScale
                flux += Math.max(0, lv - p[i]) * w[i]
                p[i] = lv
                s[i] += (lv > s[i] ? 0.75 : 0.2) * (lv - s[i])
                sl[i] += 0.05 * (lv - sl[i])
                const punch = Math.max(0, s[i] - sl[i]) * 2.5
                out[i] = Math.min(1, (0.55 * s[i] + punch) * 1.15)
            }
            // Onset: flux muy por encima de su media → patada al resorte.
            const ratio = flux / Math.max(root.fluxAvg, 0.004)
            root.fluxAvg += 0.06 * (flux - root.fluxAvg)
            if (root.beatCooldown > 0) root.beatCooldown--
            else if (ratio > 1.4 && flux > 0.008) {
                root.energyVel += 4 * Math.min(2.5, ratio - 1)
                root.beatCooldown = 3
                if (ratio > root.strikeThreshold && root.energyTarget > root.strikeMinEnergy
                        && root.strikeAge > root.strikeMinGap) {
                    root.strikeAge = 0
                    root.strikeCount++
                }
            }
            // Energía relativa al contexto: un tema fuerte no queda saturado.
            const loud = 0.7 * Math.max(p[0], p[1]) + 0.3 * Math.max(p[2], p[3])
            root.loudCtx += 0.03 * (loud - root.loudCtx)
            const surge = Math.max(0, loud / Math.max(root.loudCtx, 0.05) - 1)
            root.energyTarget = Math.min(1, 0.5 * loud + 0.6 * Math.min(1, surge))
        }
    }

    function step(dt) {
        energyVel += (220 * (energyTarget - energy) - 19 * energyVel) * dt
        energy = Math.max(0, Math.min(1.15, energy + energyVel * dt))
        const f = Math.min(1, dt * 14)
        const b = bands
        for (let i = 0; i < 6; i++) b[i] += f * (targets[i] - b[i])
        bands = b.slice()   // array nuevo: mismo objeto no notifica a los uniforms
        time += dt * (1 + Math.min(1, energy) * speedGain)
        if (strikeAge < 99) strikeAge += dt
    }

    // Reloj por Timer y no FrameAnimation: esta solo pide un frame cuando la
    // imagen cambia (20 fps en reposo, 30/60 con música) en vez de uno por vsync.
    property real time: 0
    Timer {
        interval: root.playing ? ((root.mode === 5 || root.mode === 6) ? 16 : 33) : 50
        running: root.visible
        repeat: true
        // Con volumen el tiempo corre más rápido: los ciclos (descargas,
        // pulsos, choques) se disparan más seguido en todos los modos.
        onTriggered: root.step(interval / 1000)
    }

    Repeater {
        model: root.gaps
        delegate: ShaderEffect {
            required property var modelData
            required property int index

            x: modelData.x1
            width: Math.max(0, modelData.x2 - modelData.x1)
            height: root.height
            visible: width > 10

            property real time: root.time
            property real aud: root.energy
            property real bass: (root.bands[0] + root.bands[1]) / 2
            property vector4d bandsA: Qt.vector4d(root.bands[0], root.bands[1], root.bands[2], root.bands[3])
            property vector2d bandsB: Qt.vector2d(root.bands[4], root.bands[5])
            property real strikeAge: root.strikeAge
            property real strikeSeed: root.strikeCount
            property real gapX: x
            property real gapW: width
            property real gapH: height
            property real gapIndex: index
            property real mode: root.mode
            property vector4d seal: Qt.vector4d(root.accent.r, root.accent.g, root.accent.b, 1.0)

            fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/stream.frag.qsb")
        }
    }
}
