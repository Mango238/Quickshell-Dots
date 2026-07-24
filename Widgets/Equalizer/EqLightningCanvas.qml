import QtQuick
import QtQuick.Effects

// Rayo que barre las 10 bandas al aplicar el EQ. Portado de la config de ilyamiro
// (music/MusicPopup.qml). Solo dibuja mientras dura el barrido: `progress` avanza de 0 a 10
// y `fade` lo apaga; con fade >= 1 el Timer se detiene y no consume nada.
Canvas {
    id: canvas

    required property var eqBands   // 10 ganancias en dB (-12..12)
    required property real progress // 0..10, punta del rayo
    required property real fade     // 0 = visible, 1 = apagado

    // Cuatro hebras, de halo externo a nucleo caliente.
    property color strandOuter: "#cba6f7"
    property color strandMid: "#f5c2e7"
    property color strandCore: "#b4befe"
    property color glowColor: strandOuter

    opacity: 1.0 - fade

    // FBO en vez de render por software; el bloom lo hace la GPU via layer.effect en lugar de
    // ctx.shadowBlur, que bloquea la CPU.
    renderTarget: Canvas.FramebufferObject
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: canvas.glowColor
        shadowBlur: 1.0
        shadowOpacity: 0.6
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
    }

    Timer {
        interval: 16
        running: canvas.fade < 1.0 && canvas.progress > 0.0
        repeat: true
        onTriggered: canvas.requestPaint()
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        if (progress <= 0.0 || fade >= 1.0) return;
        if (!eqBands || eqBands.length < 10) return;

        var time = Date.now() / 1000;
        var maxIdx = progress;

        ctx.lineJoin = "round";
        ctx.lineCap = "round";

        // 1. Posicion espacial de los 10 handles
        var pts = [];
        for (var b = 0; b < 10; b++) {
            var val = Number(eqBands[b]);
            if (isNaN(val)) val = 0;
            var norm = 1.0 - ((val + 12) / 24);
            pts.push({
                x: (b + 0.5) * (width / 10),
                y: 10 + norm * (height - 35)
            });
        }

        // 2. Cuatro hebras superpuestas: halo mauve, onda media, nucleo crepitante, core blanco
        for (var s = 0; s < 4; s++) {
            ctx.beginPath();
            ctx.moveTo(pts[0].x, pts[0].y);

            for (var i = 0; i < pts.length - 1; i++) {
                if (i > maxIdx) break;

                var p1 = pts[i];
                var p2 = pts[i + 1];

                var fraction = 1.0;
                if (maxIdx < i + 1) fraction = maxIdx - i;

                var steps = s === 3 ? 6 : 8;
                for (var j = 1; j <= steps; j++) {
                    var t = j / steps;
                    if (t > fraction) t = fraction;

                    var cx = p1.x + (p2.x - p1.x) * t;
                    var cy = p1.y + (p2.y - p1.y) * t;

                    var envelope = Math.sin(t * Math.PI);

                    var noiseAmpX = s === 3 ? 1.0 : (4 - s) * 4;
                    var noiseAmpY = s === 3 ? 1.0 : (4 - s) * 5;

                    // Las hebras externas (0,1) llevan ademas una onda de separacion lenta
                    var sepWaveX = (s < 2) ? Math.sin(time * 3 + i + j + s) * 10 * envelope : 0;
                    var sepWaveY = (s < 2) ? Math.cos(time * 2.5 + i - j - s) * 15 * envelope : 0;

                    var noiseX = Math.sin(time * (10 + s) + i + j) * Math.cos(time * 8 - i + j) * noiseAmpX * envelope * (1 - fade);
                    var noiseY = Math.cos(time * (9 - s) + i - j) * Math.sin(time * 7 + i - j) * noiseAmpY * envelope * (1 - fade);

                    ctx.lineTo(cx + sepWaveX + noiseX, cy + sepWaveY + noiseY);

                    if (t === fraction) break;
                }
            }

            if (s === 0) {
                ctx.lineWidth = 20; ctx.strokeStyle = strandOuter; ctx.globalAlpha = 0.2;
            } else if (s === 1) {
                ctx.lineWidth = 8; ctx.strokeStyle = strandMid; ctx.globalAlpha = 0.45;
            } else if (s === 2) {
                ctx.lineWidth = 3.5; ctx.strokeStyle = strandCore; ctx.globalAlpha = 0.85;
            } else {
                ctx.lineWidth = 1.0; ctx.strokeStyle = "#ffffff"; ctx.globalAlpha = 0.1;
            }

            ctx.stroke();
        }
    }
}
