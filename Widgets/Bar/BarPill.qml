import QtQuick
import qs.Commons

/**
 * BarPill.qml — Delegate de píldora compartido por los Repeaters de
 * LeftSide.qml y RightSide.qml (antes duplicado idéntico en ambos).
 *
 * Uso: delegate: BarPill {}  (sin bindings explícitos)
 *
 * `modelData` se declara como required property para que el Repeater la
 * rellene automáticamente (mismo mecanismo que WallpaperThumbnail.qml usa
 * con `required property int index`). A propósito NO se escribe
 * `content: modelData` a mano en el sitio de instanciación: ambos
 * LeftSide.qml/RightSide.qml viven dentro de un `Variants { model:
 * Quickshell.screens }` cuyo PanelWindow YA declara su propio
 * `required property var modelData` (el screen) — una asignación JS
 * explícita ahí resolvía ambigua y terminaba tomando el modelData del
 * screen en vez del del Repeater interno ("Unable to assign
 * QuickshellScreenInfo to QQmlComponent"). El auto-fill de required
 * property del Repeater no tiene ese problema de scoping.
 *
 * Hover con HoverHandler (no MouseArea): un HoverHandler es un "point
 * handler" que solo observa, no acepta/consume botones ni gestos — a
 * diferencia de un MouseArea, no le roba clicks a los MouseArea internos de
 * cada widget cargado por el Loader (Spoti, PowerOff, BleActivate, etc.),
 * que siguen recibiendo press/click con normalidad.
 */
Rectangle {
    id: pill

    required property Component modelData

    readonly property bool hovered: hoverHandler.hovered

    color: pill.hovered ? Qt.lighter(Colors.palette[4], 1.15) : Colors.palette[4]
    width: loader.item ? loader.item.width + 10 : 50
    height: 20
    clip: true
    radius: 5
    border.color: pill.hovered ? Qt.lighter(Colors.palette[8], 1.15) : Colors.palette[8]
    border.width: 1

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
    Behavior on width {
        NumberAnimation { duration: 100 }
    }

    Loader {
        id: loader
        anchors.centerIn: parent
        sourceComponent: pill.modelData
    }

    HoverHandler {
        id: hoverHandler
    }
}
