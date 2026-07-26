// Regresión de Widgets/General/HoverPopup.qml: abre el popup de verdad y
// comprueba el anclaje (anchor.item + rect siempre fresco) y el Loader
// perezoso. Sale con el número de fallos como código de salida.
//
//   quickshell -p HoverPopupTest.qml   # rc=0 → todo ok
//
// No lo carga shell.qml: solo corre cuando se le apunta explícitamente.
import Quickshell
import QtQuick
import qs.Widgets.General

ShellRoot {
    PanelWindow {
        id: bar
        anchors { top: true; left: true; right: true }
        implicitHeight: 45
        color: "transparent"

        Rectangle {
            id: trigger
            x: 100; y: 10
            width: 60; height: 25
            color: "red"
        }

        HoverPopup {
            id: pop
            triggerItem: trigger
            popupWidth: 200
            popupHeight: 120
            offsetY: 45 - 2
            offsetX: 30 - popupWidth / 2
            animated: false          // sin fade: estado inmediato, test determinista
            popupContent: Rectangle { anchors.fill: parent; color: "lime" }
        }

        property int failures: 0
        function check(name, cond) {
            if (!cond) { failures++; console.warn("FAIL:", name) }
            else console.info("ok:", name)
        }

        Component.onCompleted: Qt.callLater(function() {
            const popWin = pop.data[0]
            const loader = popWin.contentItem.children[0].children[0]
            check("cerrado: ventana invisible", popWin.visible === false)
            check("cerrado: contenido NO instanciado", loader.item === null)

            pop.show = true
            check("abierto: contenido instanciado", loader.item !== null)
            check("abierto: ventana visible", popWin.visible === true)
            check("abierto: rect x = offsetX", popWin.anchor.rect.x === pop.offsetX)
            check("abierto: rect y = trigger.height + offsetY",
                  popWin.anchor.rect.y === trigger.height + pop.offsetY)
            check("abierto: anchor.item es el trigger", popWin.anchor.item === trigger)

            // el rect sigue a los offsets/tamaño en vivo (el bug del rect rancio)
            pop.offsetY = 100
            check("rect fresco tras cambiar offsetY",
                  popWin.anchor.rect.y === trigger.height + 100)
            pop.popupHeight = 300
            check("rect fresco tras cambiar popupHeight",
                  popWin.anchor.rect.height === 300)

            pop.show = false
            check("cerrado de nuevo: invisible", popWin.visible === false)
            check("cerrado de nuevo: contenido liberado", loader.item === null)

            console.info(bar.failures === 0 ? "ALL OK" : "FAILURES: " + bar.failures)
            Qt.exit(bar.failures)
        })
    }
}
