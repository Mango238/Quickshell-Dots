/**
 * HoverPopup.qml — Popup modular reutilizable para Quickshell
 *
 * USO:
 *   HoverPopup {
 *       triggerItem: miWidget          // Item que activa el hover
 *       anchorWindow: root             // Ventana de anclaje (obligatorio)
 *
 *       offsetX: 0                     // Desplazamiento horizontal extra (opcional)
 *       offsetY: 0                     // Desplazamiento vertical extra (opcional)
 *       popupWidth: 160                // Ancho del popup
 *       popupHeight: 80                // Alto del popup
 *
 *       popupContent: Component {      // Contenido personalizado
 *           Text { text: "Hola!" }
 *       }
 *   }
 */

import QtQuick
import Quickshell

Item {
    id: hoverPopup

    // ─── API pública ──────────────────────────────────────────────────────────

    /// Item que dispara el hover. OBLIGATORIO.
    required property Item triggerItem

    /// Ventana de anclaje del popup. OBLIGATORIO.
    required property var anchorWindow

    /// Componente QML con el contenido interno del popup
    property Component popupContent: null

    /// Dimensiones del popup
    property real popupWidth: 160
    property real popupHeight: 80

    /// Desplazamientos extra sobre la posición calculada
    property real offsetX: 0
    property real offsetY: 0

    /// Animación de fade al abrir/cerrar (true por defecto)
    property bool animated: true

    property bool show: false
    // ─── Estado interno ───────────────────────────────────────────────────────

    property rect _anchorRect: Qt.rect(0, 0, 1, 1)
    property bool _hovered: false

    // ─── Cálculo de posición ──────────────────────────────────────────────────

    function _updatePosition() {
        if (!triggerItem) return;
        if (triggerItem.width <= 0 || triggerItem.height <= 0) return;

        var pos = triggerItem.mapToItem(null, offsetX, triggerItem.height + offsetY);
        _anchorRect = Qt.rect(pos.x, pos.y, popupWidth, popupHeight);
    }

    // ─── Conexiones al triggerItem ────────────────────────────────────────────

    Connections {
        target: triggerItem
        function onWidthChanged()  { hoverPopup._updatePosition(); }
        function onHeightChanged() { hoverPopup._updatePosition(); }
        function onXChanged()      { hoverPopup._updatePosition(); }
        function onYChanged()      { hoverPopup._updatePosition(); }
    }

    onShowChanged: {
        hoverPopup._updatePosition();
    }

    Component.onCompleted: Qt.callLater(_updatePosition)


    // ─── Ventana popup ───────────────────────────────────────────────────────

    PopupWindow {
        id: popup

        anchor.window: hoverPopup.anchorWindow
        anchor.rect: hoverPopup._anchorRect

        implicitWidth:  hoverPopup.popupWidth
        implicitHeight: hoverPopup.popupHeight

        // La ventana debe estar visible para que la opacidad funcione
        visible: hoverPopup.show || (animated && fadeAnim.running)

        color: "transparent"

        // ── Contenedor visual con fade ─────────────────────────────────────
        
        Item {
            id: contentRoot
            anchors.fill: parent

            opacity: hoverPopup.show ? 1.0 : 0.0

            Behavior on opacity {
                enabled: hoverPopup.animated
                NumberAnimation {
                    id: fadeAnim
                    duration: 130
                    easing.type: Easing.OutCubic
                }
            }

            Loader {
                anchors.fill: parent
                sourceComponent: hoverPopup.popupContent
            }
        }
    }
}
