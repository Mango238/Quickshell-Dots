import QtQuick
import qs.Services
import qs.Commons

Item {
    id: textContainer
    clip: true

    property var trackData: SpotifyInfo.trackData

    // Ancho máximo del pill. Antes era contentWidth/1.7, que por construcción
    // deja el contenedor SIEMPRE más angosto que el texto: needsScrolling era
    // true siempre y el marquee corría 24/7 (~60 fps de repintado de toda la
    // barra, en cada monitor). Con un tope fijo, los títulos cortos no scrollean.
    readonly property int maxWidth: 200
    width: Math.min(mediaText.implicitWidth, maxWidth)
    height: 20   
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onClicked: PopupState.toggle("spotify")

    }

    Text {
        id: mediaText
        // Guard contra trackData nulo; icono según estado de reproducción
        text: trackData
            ? ((SpotifyInfo.activePlayer?.isPlaying ? "󰐊 " : "󰏤 ")
               + trackData.title + " - " + trackData.artist)
            : ""
        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])
        property bool needsScrolling: implicitWidth > textContainer.width
        property real scrollOffset: 0
        property real textShift: 0

        verticalAlignment: Text.AlignVCenter
        width: parent.width
        height: parent.height
        //font.pixelSize: 11
        wrapMode: Text.NoWrap
        x: (needsScrolling ? -scrollOffset : 0) + textShift
        opacity: 1

        onTextChanged: {
            // Sin restart() del scroll: restart() escribe running=true a mano y
            // rompe el binding de abajo para siempre, así que el marquee ya no
            // podía apagarse nunca. El binding solo ya lo arranca si hace falta.
            scrollOffset = 0;
            textShift = 0;
            textChangeAnimation.restart();
        }

        SequentialAnimation {
            id: scrollAnimation
            running: mediaText.needsScrolling && textContainer.visible
                     && (SpotifyInfo.activePlayer?.isPlaying ?? false)
            loops: Animation.Infinite

            PauseAnimation {
                duration: 2000
            }

            NumberAnimation {
                target: mediaText
                property: "scrollOffset"
                from: 0
                to: mediaText.implicitWidth - textContainer.width + 5
                duration: Math.max(1000, (mediaText.implicitWidth - textContainer.width + 5) * 60)
                easing.type: Easing.Linear
            }

            PauseAnimation {
                duration: 2000
            }

            NumberAnimation {
                target: mediaText
                property: "scrollOffset"
                to: 0
                duration: Math.max(1000, (mediaText.implicitWidth - textContainer.width + 5) * 60)
                easing.type: Easing.Linear
            }
        }

        SequentialAnimation {
            id: textChangeAnimation

            ParallelAnimation {
                NumberAnimation {
                    target: mediaText
                    property: "opacity"
                    from: 0.7
                    to: 1
                    duration: 1000
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
                }

                NumberAnimation {
                    target: mediaText
                    property: "textShift"
                    from: 4
                    to: 0
                    duration: 1000
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
                }
            }
        }

    }
}
