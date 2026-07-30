import QtQuick
import QtQuick.Shapes
import qs.Commons

/**
 * Indicador de huella del lock screen. Solo pinta estado: no habla con PAM.
 *
 * Todos los colores cuelgan de `vs`, un estado derivado unico. `flash` es lo unico que se
 * escribe imperativamente (desde flashFail/flashSuccess) precisamente para no romper el
 * binding de `vs` con un PropertyAction sobre una property que tenia binding.
 *
 * Las dos animaciones en bucle (ping + barrido) van atadas a `armed`, para no mantener la
 * GPU despierta mientras el sensor no espera dedo.
 */
Item {
    id: fp

    /// Factor de escala responsive del lock (screenRoot.sc).
    property real sc: 1.0
    /// Sensor armado esperando dedo (pamFp.active).
    property bool armed: false
    /// Intentos agotados: el badge queda apagado y clickeable para rearmar.
    property bool exhausted: false
    /// Mensaje de pam_fprintd.
    property string statusText: ""

    signal retryRequested()

    /// Lo escriben SOLO las animaciones de flash: "" | "fail" | "ok".
    property string flash: ""
    readonly property string vs: flash !== "" ? flash : (exhausted ? "off" : "armed")

    readonly property color cOk: "#A6E3A1"   // igual que el verde hardcodeado del lock
    readonly property color cDim: Colors.ready ? Colors.palette[7] : "#CDD6F4"
    readonly property color cSurface: Colors.ready ? Colors.palette[3] : "#313244"
    readonly property color tone: {
        if (vs === "fail") return Colors.danger;
        if (vs === "ok") return cOk;
        if (vs === "off") return Qt.alpha(cDim, 0.5);
        return Colors.accent;
    }

    implicitWidth: 380 * sc
    implicitHeight: label.y + label.height

    function flashFail() {
        okAnim.stop();
        failAnim.restart();
    }

    function flashSuccess() {
        failAnim.stop();
        okAnim.restart();
    }

    // Ping de radar: dice "el sensor esta vivo" sin pedir nada.
    Rectangle {
        id: ping
        anchors.centerIn: badge
        width: badge.width
        height: width
        radius: width / 2
        color: "transparent"
        border.color: fp.tone
        border.width: Math.max(1, 1 * fp.sc)
        visible: fp.armed && !fp.exhausted && fp.flash === ""

        ParallelAnimation {
            running: ping.visible
            loops: Animation.Infinite
            ScaleAnimator { target: ping; from: 1.0; to: 1.7; duration: Config.anim.ambient; easing.type: Config.easingOf(Config.anim.decelerate) }
            OpacityAnimator { target: ping; from: 0.35; to: 0.0; duration: Config.anim.ambient; easing.type: Config.easingOf(Config.anim.decelerate) }
        }
    }

    // Burst de exito. Solo hay ~300 ms antes de que exitTimer mate el proceso.
    Rectangle {
        id: burst
        anchors.centerIn: badge
        width: badge.width
        height: width
        radius: width / 2
        color: "transparent"
        border.color: fp.cOk
        border.width: Math.max(1, 2 * fp.sc)
        opacity: 0
        visible: opacity > 0
    }

    // Arco de barrido girando: el "escaneando" del indicador.
    Shape {
        id: sweep
        anchors.centerIn: badge
        width: badge.width + (22 * fp.sc)
        height: width
        preferredRendererType: Shape.CurveRenderer
        visible: fp.armed && !fp.exhausted

        ShapePath {
            strokeColor: fp.tone
            strokeWidth: Math.max(1, 2 * fp.sc)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: sweep.width / 2
                centerY: sweep.height / 2
                radiusX: (sweep.width / 2) - Math.max(1, 2 * fp.sc)
                radiusY: radiusX
                startAngle: -90
                sweepAngle: 100
            }
        }

        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 1400
            loops: Animation.Infinite
            running: sweep.visible
        }
    }

    Rectangle {
        id: badge
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: 64 * fp.sc
        height: width
        radius: width / 2

        // Backdrop de surface + tinte del estado: con un acento oscuro (paleta de wallpaper
        // nocturno) un relleno de solo tone se pierde sobre el fondo.
        color: Qt.tint(Qt.alpha(fp.cSurface, 0.55), Qt.alpha(fp.tone, fp.vs === "off" ? 0.05 : 0.2))
        border.color: Qt.alpha(fp.tone, fp.vs === "off" ? 0.4 : 0.9)
        border.width: Math.max(1, 2 * fp.sc)

        // El pop de rearmado va en un Scale aparte: animar `scale` chocaria con su Behavior.
        scale: retryMouse.containsMouse ? 1.06 : 1.0
        transform: [
            Translate { id: shake },
            Scale { id: pop; origin.x: badge.width / 2; origin.y: badge.height / 2 }
        ]

        Behavior on color { ColorAnimation { duration: Config.anim.panel } }
        Behavior on border.color { ColorAnimation { duration: Config.anim.panel } }
        Behavior on scale { NumberAnimation { duration: Config.anim.base; easing.type: Config.easingOf(Config.anim.emphasized) } }

        Text {
            anchors.centerIn: parent
            text: "󰈷"
            font.family: Config.font
            font.pixelSize: 30 * fp.sc
            font.strikeout: fp.vs === "off"
            // Mismo criterio que el label: en reposo el glifo va en color de texto para que se
            // lea, y el acento se queda en el anillo y el arco.
            color: fp.vs === "armed" ? fp.cDim : fp.tone
            Behavior on color { ColorAnimation { duration: Config.anim.panel } }
        }

        MouseArea {
            id: retryMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: fp.exhausted
            onClicked: {
                fp.retryRequested();
                popAnim.restart();
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: fp.exhausted ? "Retry fingerprint" : "Fingerprint reader"
        Accessible.description: label.text
    }

    Text {
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: badge.bottom
        anchors.topMargin: 14 * fp.sc
        width: fp.width
        horizontalAlignment: Text.AlignHCenter
        // El prompt de pam_fprintd es largo ("Coloque su dedo indice derecho en el lector de
        // huellas dactilares"): en una sola linea se cortaba.
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.family: Config.font
        font.pixelSize: 12 * fp.sc
        font.weight: Font.Medium
        font.letterSpacing: 2.0
        // En reposo el texto va en color de texto (como el status row del lock): el acento
        // sale de una paleta de wallpaper y puede ser demasiado oscuro para leerlo.
        color: fp.vs === "armed" ? fp.cDim : fp.tone
        text: (fp.exhausted
                ? "Tap to retry"
                : (fp.statusText !== "" ? fp.statusText : "Fingerprint ready")).toUpperCase()

        // Un Behavior on opacity no dispara con un cambio de texto: hay que reanimar a mano.
        onTextChanged: labelFade.restart()
        NumberAnimation { id: labelFade; target: label; property: "opacity"; from: 0; to: 1; duration: Config.anim.base }
        Behavior on color { ColorAnimation { duration: Config.anim.panel } }
    }

    SequentialAnimation {
        id: failAnim
        PropertyAction { target: fp; property: "flash"; value: "fail" }
        NumberAnimation { target: shake; property: "x"; from: 0; to: -6 * fp.sc; duration: Config.anim.instant; easing.type: Easing.InOutSine }
        NumberAnimation { target: shake; property: "x"; from: -6 * fp.sc; to: 6 * fp.sc; duration: Config.anim.instant; easing.type: Easing.InOutSine }
        NumberAnimation { target: shake; property: "x"; to: 0; duration: Config.anim.instant; easing.type: Easing.InOutSine }
        PauseAnimation { duration: Config.anim.slow }
        PropertyAction { target: fp; property: "flash"; value: "" }
    }

    SequentialAnimation {
        id: okAnim
        PropertyAction { target: fp; property: "flash"; value: "ok" }
        ParallelAnimation {
            NumberAnimation { target: burst; property: "scale"; from: 1.0; to: 2.4; duration: Config.anim.panel; easing.type: Config.easingOf(Config.anim.decelerate) }
            NumberAnimation { target: burst; property: "opacity"; from: 0.9; to: 0.0; duration: Config.anim.panel; easing.type: Config.easingOf(Config.anim.decelerate) }
            NumberAnimation { target: pop; property: "xScale"; from: 1.0; to: 1.15; duration: Config.anim.panel; easing.type: Config.easingOf(Config.anim.emphasized) }
            NumberAnimation { target: pop; property: "yScale"; from: 1.0; to: 1.15; duration: Config.anim.panel; easing.type: Config.easingOf(Config.anim.emphasized) }
        }
    }

    ParallelAnimation {
        id: popAnim
        NumberAnimation { target: pop; property: "xScale"; from: 0.85; to: 1.0; duration: Config.anim.panel; easing.type: Config.easingOf(Config.anim.emphasized) }
        NumberAnimation { target: pop; property: "yScale"; from: 0.85; to: 1.0; duration: Config.anim.panel; easing.type: Config.easingOf(Config.anim.emphasized) }
    }
}
