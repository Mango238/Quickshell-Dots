import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: panelPopup

    // ─── API pública ──────────────────────────────────────────────────────
    required property Item alignItem
    property bool show: false

    /// Opt-in: toma foco de teclado del compositor (HyprlandFocusGrab)
    /// mientras show sea true. NO llamarla "grabFocus": PopupWindow ya tiene
    /// una propiedad C++ con ese nombre (Qt::Popup + auto-dismiss) cuyo
    /// cierre escribe `visible` imperativamente y destruiría el binding
    /// `visible: show || fadeAnim.running` de abajo.
    property bool grabKeyboardFocus: false

    /// Emitida cuando el compositor limpia el grab (click fuera del popup).
    /// El dueño del popup decide qué hacer (p. ej. PopupState.active = "").
    signal dismissed()

    /// true mientras el contenido debe existir: abierto o en fade de cierre.
    /// Lo usan los Loader de Bar.qml para instanciar el contenido de forma
    /// perezosa (los popups no-lazy triplicados por monitor eran el mayor
    /// costo de RAM de la config).
    readonly property bool contentActive: show || fadeAnim.running

    /// Desplazamiento horizontal del anclaje, en px. Positivo = hacia la
    /// derecha, negativo = hacia la izquierda. El popup sigue centrado sobre
    /// el rect de anclaje (ya desplazado); SlideX sigue protegiendo que no
    /// se corte en los bordes de pantalla.
    property real offsetX: 0

    /// Color sólido (color) O array de colores (var) → activa modo gradiente.
    property var panelColor: "#1E1E2E"
    /// Ángulo del gradiente en grados, convención CSS (0° = arriba, horario).
    property real gradientAngle: 45
    /// Posiciones custom de los stops (0..1). Vacío = distribución uniforme.
    property var gradientStopPositions: []

    property real panelHeight: 170
    property real panelWidth: 0
    property real panelRadius: 12
    property real tRadiusFactor: 2.0
    property int topLeftCornerState:     1
    property int topRightCornerState:    1
    property int bottomRightCornerState: 0
    property int bottomLeftCornerState:  0

    default property alias content: contentSlot.data

    // ─── Modo gradiente vs sólido ───────────────────────────────────────────
    readonly property bool isGradientMode: Array.isArray(panelColor) && panelColor.length > 1
    readonly property color solidColor: Array.isArray(panelColor) ? panelColor[0] : panelColor
    readonly property int maxGradientStops: 8

    /// Posición del stop N: usa gradientStopPositions si está definido, si no distribuye uniforme.
    function stopPosition(index, total) {
        if (gradientStopPositions.length === total)
            return gradientStopPositions[index]
        return total > 1 ? index / (total - 1) : 0
    }

    /// Convierte ángulo CSS (0°=arriba, horario) + tamaño de caja → línea x1,y1,x2,y2
    /// que cubre la caja completa (mismo algoritmo que linear-gradient() de CSS).
    function gradientLine(w, h, angleDeg) {
        var rad = angleDeg * Math.PI / 180
        var len = Math.abs(w * Math.sin(rad)) + Math.abs(h * Math.cos(rad))
        var dx = (len * Math.sin(rad)) / 2
        var dy = (len * Math.cos(rad)) / 2
        var cx = w / 2, cy = h / 2
        return { x1: cx - dx, y1: cy + dy, x2: cx + dx, y2: cy - dy }
    }

    /// Color del stop N: usa panelColor[i] si existe, si no repite el último color.
    function stopColor(i) {
        if (!isGradientMode) return "transparent"
        var colors = panelColor
        return i < colors.length ? colors[i] : colors[colors.length - 1]
    }

    /// Posición del stop N (wrapper sobre stopPosition con el total de panelColor).
    function stopColorPosition(i) {
        if (!isGradientMode) return 0
        var count = panelColor.length
        return i < count ? stopPosition(i, count) : 1.0
    }

    // ─── Anclaje ─────────────────────────────────────────────────────────
    anchor.item: alignItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    // Antes: PopupAdjustment.None desactivaba toda corrección de posición
    // horizontal — el popup de spotify (500px) centrado sobre rightside se
    // salía por el borde derecho de la pantalla y no se veía. SlideX: sigue
    // centrado sobre su sección (edges/gravity sin tocar) pero desliza lo
    // mínimo necesario para no cortarse en los bordes de pantalla —
    // decisión explícita del usuario: centrado con tope, no alineado al
    // borde de la sección.
    anchor.adjustment: PopupAdjustment.SlideX
    anchor.rect: panelPopup._anchorRect

    // El rect de anclaje por defecto (solo con anchor.item, sin anchor.rect)
    // usa las dimensiones del propio item — una sección (leftside/midside/
    // rightside) de ~27.5px centrada verticalmente dentro de una barra de
    // 45px. Con edges/gravity Bottom eso hacía nacer el popup en el borde
    // inferior de la SECCIÓN (~y=36), solapando la mitad inferior de la
    // barra. Extendemos el rect (relativo al item) hasta que su borde
    // inferior coincida con el borde inferior real de la PanelWindow, para
    // que el popup nazca justo ahí.
    //
    // Recalculado explícitamente en vez de solo un binding declarativo
    // directo sobre anchor.rect: el doc de PopupAnchor advierte que la
    // posición final del popup respecto a su ventana "se calcula solo
    // cuando se muestra inicialmente" (semántica de positioner de Wayland),
    // así que nos aseguramos de que el rect esté fresco justo antes de eso
    // — mismo patrón reactivo (Connections a x/y/width/height del item +
    // onShowChanged) que ya usa HoverPopup.qml en este mismo directorio.
    property rect _anchorRect: Qt.rect(0, 0, 1, 1)

    function _updateAnchorRect() {
        if (!alignItem) return
        // mapToItem(null, ...) da la posición del item en coordenadas de
        // ventana (mismo mecanismo que ya usa HoverPopup.qml).
        var pos = alignItem.mapToItem(null, 0, 0)
        // NO usar QsWindow.window.height: en Modules/Bar.qml la PanelWindow
        // (id: root) redefine "height" como `property int height:
        // (root.implicitHeight / 2) + 5` (~27.5, usado a propósito por
        // LeftSide/MidSide/RightSide para su propio layout). Esa propiedad
        // custom TAPA cualquier lectura de `.height` sobre ese mismo objeto
        // window — confirmado con un console.log temporal: QsWindow.window
        // SÍ resolvía a un ProxyWindowAttached real (no undefined), pero
        // `.height` devolvía ~27 en vez de los 45px reales de la ventana.
        // En cambio, subir por la cadena de parents de Item hasta la raíz de
        // la escena llega al contentItem de la ventana — un Item plano, sin
        // ninguna propiedad custom shadowing — cuyo .height sí es el alto
        // real en píxeles.
        var p = alignItem
        while (p.parent) p = p.parent
        var winHeight = p.height
        // Math.max: nunca <= 0, ni siquiera en el primer frame con medidas todavía en 0.
        var h = Math.max(1, winHeight - pos.y)
        _anchorRect = Qt.rect(offsetX, 0, alignItem.width, h)
    }

    Connections {
        target: alignItem
        function onWidthChanged()  { panelPopup._updateAnchorRect() }
        function onHeightChanged() { panelPopup._updateAnchorRect() }
        function onXChanged()      { panelPopup._updateAnchorRect() }
        function onYChanged()      { panelPopup._updateAnchorRect() }
    }

    onShowChanged: {
        if (show) _updateAnchorRect()
        // Asignación imperativa a propósito: el setter C++ del grab escribe
        // active=false cuando el compositor lo limpia, lo que destruiría un
        // binding declarativo. Qt.callLater da un tick para que la ventana
        // llegue a mostrarse antes de pedir el grab (el C++ además engancha
        // ventanas aún no conectadas vía windowConnected).
        if (grabKeyboardFocus) Qt.callLater(() => grab.active = panelPopup.show)
    }

    HyprlandFocusGrab {
        id: grab
        windows: [ panelPopup ]
        onCleared: if (panelPopup.show) panelPopup.dismissed()
    }

    Component.onCompleted: Qt.callLater(_updateAnchorRect)

    implicitWidth: (panelWidth ? panelWidth : alignItem.width) + bg.overhangLeft + bg.overhangRight
    implicitHeight: panelHeight

    visible: show || fadeAnim.running
    color: "transparent"

    Item {
        id: contentRoot
        anchors.fill: parent
        opacity: panelPopup.show ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation {
                id: fadeAnim
                duration: 130
                easing.type: Easing.OutCubic
            }
        }

        Shape {
            anchors.fill: parent
            LinearGradient {
                id: panelGradient
                x1: panelPopup.gradientLine(bg.panelWidth, bg.panelHeight, panelPopup.gradientAngle).x1
                y1: panelPopup.gradientLine(bg.panelWidth, bg.panelHeight, panelPopup.gradientAngle).y1
                x2: panelPopup.gradientLine(bg.panelWidth, bg.panelHeight, panelPopup.gradientAngle).x2
                y2: panelPopup.gradientLine(bg.panelWidth, bg.panelHeight, panelPopup.gradientAngle).y2

                GradientStop { position: panelPopup.stopColorPosition(0); color: panelPopup.stopColor(0) }
                GradientStop { position: panelPopup.stopColorPosition(1); color: panelPopup.stopColor(1) }
                GradientStop { position: panelPopup.stopColorPosition(2); color: panelPopup.stopColor(2) }
                GradientStop { position: panelPopup.stopColorPosition(3); color: panelPopup.stopColor(3) }
                GradientStop { position: panelPopup.stopColorPosition(4); color: panelPopup.stopColor(4) }
                GradientStop { position: panelPopup.stopColorPosition(5); color: panelPopup.stopColor(5) }
                GradientStop { position: panelPopup.stopColorPosition(6); color: panelPopup.stopColor(6) }
                GradientStop { position: panelPopup.stopColorPosition(7); color: panelPopup.stopColor(7) }
            }

            Panel {
                id: bg

                fillGradient: panelPopup.isGradientMode ? panelGradient : null
                backgroundColor: panelPopup.solidColor

                panelX: bg.overhangLeft
                panelY: 0
                panelWidth: panelPopup.panelWidth ? panelPopup.panelWidth : panelPopup.alignItem.width
                panelHeight: panelPopup.panelHeight
                radius: panelPopup.panelRadius
                tRadiusFactor: panelPopup.tRadiusFactor
                topLeftCornerState: panelPopup.topLeftCornerState
                topRightCornerState: panelPopup.topRightCornerState
                bottomRightCornerState: panelPopup.bottomRightCornerState
                bottomLeftCornerState: panelPopup.bottomLeftCornerState
            }
        }

        Item {
            id: contentSlot
            anchors.fill: parent
            anchors.leftMargin: bg.overhangLeft
            anchors.rightMargin: bg.overhangRight
        }
    }
}


