pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services

// Editor markdown de la nota abierta (ObsidianEditor.path). Se edita el texto
// crudo: un TextEdit con textFormat MarkdownText reescribe el archivo al
// guardar (reformatea listas, links y front-matter), así que el render vive en
// un Text de solo lectura detrás del toggle 󰈈.
Item {
    id: root

    property bool preview: false

    readonly property color cardColor: Qt.alpha(Colors.palette[3], 0.5)
    readonly property color textColor: "#e6e6e6"

    // Las fórmulas se renderizan del color del texto del preview.
    Component.onCompleted: MathRender.color = root.textColor

    function _title() {
        const p = ObsidianEditor.path
        const i = p.lastIndexOf("/")
        return (i === -1 ? p : p.slice(i + 1)).replace(/\.md$/, "")
    }

    // ── Cabecera ───────────────────────────────────────────────────────
    Rectangle {
        id: backBtn
        anchors { top: parent.top; left: parent.left }
        width: 30
        height: 30
        radius: 10
        color: backHover.containsMouse ? Qt.alpha(Colors.accent, 0.25) : root.cardColor
        Text {
            anchors.centerIn: parent
            text: ""
            font.pixelSize: 15
            color: root.textColor
        }
        MouseArea {
            id: backHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ObsidianEditor.close()
        }
    }

    Text {
        id: title
        anchors { left: backBtn.right; leftMargin: 10; right: actions.left; rightMargin: 10
                  verticalCenter: backBtn.verticalCenter }
        text: root._title()
        color: root.textColor
        font.pixelSize: 17
        font.bold: true
        elide: Text.ElideMiddle
    }

    Row {
        id: actions
        anchors { right: parent.right; verticalCenter: backBtn.verticalCenter }
        spacing: 6

        Rectangle {
            id: previewBtn
            width: 30
            height: 30
            radius: 10
            color: root.preview ? Colors.accent
                 : previewHover.containsMouse ? Qt.alpha(Colors.accent, 0.25)
                 : root.cardColor
            Text {
                anchors.centerIn: parent
                text: "󰈈"
                font.pixelSize: 15
                color: root.preview ? Colors.accentText : root.textColor
            }
            MouseArea {
                id: previewHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.preview = !root.preview
            }
        }

        Rectangle {
            id: obsidianBtn
            width: 30
            height: 30
            radius: 10
            color: obsidianHover.containsMouse ? Qt.alpha(Colors.accent, 0.25) : root.cardColor
            Text {
                anchors.centerIn: parent
                text: "󰏋"
                font.pixelSize: 15
                color: root.textColor
            }
            MouseArea {
                id: obsidianHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(
                    ["xdg-open", "obsidian://open?path=" + encodeURIComponent(ObsidianEditor.path)])
            }
        }
    }

    // ── Estado de guardado ─────────────────────────────────────────────
    Text {
        id: status
        anchors { top: backBtn.bottom; topMargin: 8; left: parent.left; right: parent.right }
        text: ObsidianEditor.error !== "" ? ObsidianEditor.error
            : ObsidianEditor.dirty ? "sin guardar · Ctrl+S"
            : "guardado"
        color: ObsidianEditor.error !== "" ? Colors.danger : root.textColor
        opacity: ObsidianEditor.error !== "" ? 1.0 : 0.5
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    // ── Cuerpo ─────────────────────────────────────────────────────────
    Flickable {
        id: editFlick
        anchors { top: status.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: !root.preview
        clip: true
        contentWidth: width
        contentHeight: editor.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        TextEdit {
            id: editor
            width: editFlick.width
            color: root.textColor
            font.family: Config.font
            font.pixelSize: 14
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            selectionColor: Qt.alpha(Colors.accent, 0.5)

            onTextChanged: ObsidianEditor.text = text

            // Mantiene el cursor a la vista al escribir más allá del pliegue.
            onCursorRectangleChanged: {
                const r = cursorRectangle
                if (r.y < editFlick.contentY)
                    editFlick.contentY = r.y
                else if (r.y + r.height > editFlick.contentY + editFlick.height)
                    editFlick.contentY = r.y + r.height - editFlick.height
            }

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                    event.accepted = true
                    ObsidianEditor.save()
                }
            }
            // Primer Escape sale del editor; el segundo cierra el sidebar.
            Keys.onEscapePressed: (event) => {
                event.accepted = true
                ObsidianEditor.close()
            }

            Component.onCompleted: {
                editor.text = ObsidianEditor.text   // ya había cargado
                root._updatePreview()
                Qt.callLater(() => editor.forceActiveFocus())
            }
        }

        // La carga del archivo es asíncrona: puede terminar después de que
        // esta vista se creó.
        Connections {
            target: ObsidianEditor
            function onTextLoaded(t) { editor.text = t }
        }
    }

    Flickable {
        id: previewFlick
        anchors.fill: editFlick
        visible: root.preview
        clip: true
        contentWidth: width
        contentHeight: rendered.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Text {
            id: rendered
            width: previewFlick.width
            // `text` se asigna desde _updatePreview(), no por binding: _render()
            // escribe en mdConv y lee su length, y hacer eso dentro de un
            // binding es un loop.
            textFormat: Text.RichText
            wrapMode: Text.Wrap
            color: root.textColor
            font.family: Config.font
            font.pixelSize: 14
            onLinkActivated: (url) => Qt.openUrlExternally(url)
        }
    }

    // Conversor markdown → HTML. El importador de markdown de Qt (md4c,
    // CommonMark + GitHub) descarta el HTML inline, así que no se puede
    // inyectar nada en el markdown de origen: hay que parsear primero y
    // retocar el HTML resultante. Este TextEdit es solo el conversor, no se
    // dibuja.
    TextEdit {
        id: mdConv
        visible: false
        width: 1
        font.family: Config.font   // el HTML sale con esta familia embebida
    }

    // Solo se parsea con el preview a la vista: reparsear la nota entera en
    // cada tecla mientras se edita no le sirve a nadie.
    function _updatePreview() {
        if (root.preview)
            rendered.text = root._render(ObsidianEditor.text)
    }

    onPreviewChanged: root._updatePreview()
    Connections {
        target: ObsidianEditor
        function onTextChanged() { root._updatePreview() }
    }
    // Cuando llegan PNGs de fórmulas nuevos, se rehace el HTML para meterlos.
    Connections {
        target: MathRender
        function onRendered() { root._updatePreview() }
    }

    function _render(src) {
        // Las fórmulas salen ANTES del parseo: markdown se come los escapes de
        // LaTeX (`\,` queda en `,`, `\\` en `\`). El token es alfanumérico, así
        // que atraviesa el parser intacto y se sustituye después en el HTML.
        // Inline exige que el contenido no empiece ni termine en espacio, que es
        // la convención de TeX y evita que un `$PATH y $HOME` de una línea de
        // shell se tome por fórmula.
        // ponytail: no distingue los "$" que están dentro de código; si molesta,
        // apartar los fences antes de esta extracción.
        const math = []
        src = src.replace(/\$\$([\s\S]+?)\$\$|\$([^\s$][^\n$]*?[^\s$]|[^\s$])\$/g,
            (m, blk, inl) => {
                math.push({ tex: (blk !== undefined ? blk : inl).trim(), raw: m })
                return "qsmath" + (math.length - 1) + "qs"
            })
        if (math.length > 0)
            MathRender.request(math.map(f => f.tex))

        mdConv.textFormat = Text.MarkdownText
        mdConv.text = src
        mdConv.textFormat = Text.RichText
        var html = mdConv.getFormattedText(0, mdConv.length)

        // getFormattedText exporta un "fragmento" y marca sus bordes con estos
        // comentarios; el que cae dentro del primer bloque le rompe el formato
        // (un <h1> inicial terminaba más chico que el cuerpo).
        html = html.replace(/<!--(?:Start|End)Fragment-->/g, "")

        // Qt escribe en cada span el font-size absoluto del conversor (9pt);
        // sacándolo manda la fuente de `rendered`.
        html = html.replace(/font-size:\s*\d+pt;/g, "")

        // Los <h1..h6> quedan entonces del tamaño del cuerpo — Qt no reescala
        // solo. Se les pone tamaño explícito, relativo al del editor.
        const base = rendered.font.pixelSize
        const scale = { "1": 1.7, "2": 1.42, "3": 1.2, "4": 1.1, "5": 1.0, "6": 1.0 }
        html = html.replace(/<h([1-6]) style="/g,
            (m, n) => '<h' + n + ' style=" font-size:' + Math.round(base * scale[n]) + 'px;')

        // El código sale como spans/bloques en monospace. Se aparta antes de
        // tocar los "==" para que un `a == b` de código no se destaque.
        // El centinela \u0000 no aparece ni en el HTML de Qt ni en una nota.
        const code = []
        html = html.replace(/<pre[\s\S]*?<\/pre>|<span style="[^"]*monospace[^"]*">[\s\S]*?<\/span>/g,
            (m) => {
                code.push(m)
                return "\u0000" + (code.length - 1) + "\u0000"
            })

        // ==destacado== de Obsidian: no existe en CommonMark, así que la marca
        // llega literal hasta acá. Si adentro había **negrita**, el par de "=="
        // cae en spans distintos — por eso el grupo captura etiquetas también y
        // el reemplazo termina anidando los spans.
        // ponytail: regex simple; un "==" impar destaca hasta el próximo "==".
        html = html.replace(/==([\s\S]*?)==/g,
            '<span style="background-color:' + root._hex(Colors.accent)
            + '; color:' + root._hex(Colors.accentText) + ';">$1</span>')

        html = html.replace(/\u0000(\d+)\u0000/g, (m, i) => code[parseInt(i)])

        // Los tokens de fórmula pasan a <img>; las que todavía no tienen PNG
        // (render en curso, o sin matplotlib) vuelven a su texto original.
        html = html.replace(/qsmath(\d+)qs/g, (m, i) => {
            const f = math[parseInt(i)]
            if (!f)
                return m
            const d = MathRender.dimFor(f.tex)
            if (!d)
                return f.raw.replace(/&/g, "&amp;").replace(/</g, "&lt;")
            // width/height explícitos: el PNG viene al doble para que no se vea
            // blando, y acá se baja al tamaño real.
            return '<img src="file://' + MathRender.pathFor(f.tex)
                 + '" width="' + d[0] + '" height="' + d[1]
                 + '" style="vertical-align: middle" />'
        })

        return html
    }

    // color → "#rrggbb" para meterlo en un style CSS.
    function _hex(c) {
        const h = (v) => Math.round(v * 255).toString(16).padStart(2, "0")
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
}
