pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Services

// Text de solo lectura que muestra markdown con fórmulas LaTeX ($…$, $$…$$,
// \(…\), \[…\]). Qt no tiene motor matemático: las fórmulas se apartan antes
// del parseo, las renderiza MathRender a PNG y vuelven como <img>. Sin texlive
// no hay PNG y la fórmula queda como texto plano — se degrada, no se rompe.
Text {
    id: root

    property string source: ""
    property bool _ready: false

    textFormat: Text.RichText
    wrapMode: Text.Wrap
    onLinkActivated: (url) => Qt.openUrlExternally(url)

    // `text` se asigna imperativamente, no por binding: _render() escribe en
    // mdConv y lee su length, y hacer eso dentro de un binding es un loop.
    // El primer render espera a onCompleted para que font.pixelSize (que manda
    // el tamaño de los <h1..h6>) ya tenga el valor del consumidor.
    onSourceChanged: root._update()
    Component.onCompleted: { root._ready = true; root._update() }

    // Cuando llegan PNGs de fórmulas nuevos, se rehace el HTML para meterlos.
    Connections {
        target: MathRender
        function onRendered() { root._update() }
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

    function _update() {
        if (root._ready)
            root.text = root._render(root.source)
    }

    function _render(src) {
        // Las fórmulas salen ANTES del parseo: markdown se come los escapes de
        // LaTeX (`\,` queda en `,`, `\\` en `\`). El token es alfanumérico, así
        // que atraviesa el parser intacto y se sustituye después en el HTML.
        // Inline con "$" exige que el contenido no empiece ni termine en
        // espacio, que es la convención de TeX y evita que un `$PATH y $HOME`
        // de una línea de shell se tome por fórmula.
        // ponytail: no distingue los delimitadores que están dentro de código;
        // si molesta, apartar los fences antes de esta extracción.
        const math = []
        src = src.replace(
            /\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\$([^\s$][^\n$]*?[^\s$]|[^\s$])\$|\\\(([\s\S]+?)\\\)/g,
            (m, blk, blk2, inl, inl2) => {
                const tex = blk !== undefined ? blk
                          : blk2 !== undefined ? blk2
                          : inl !== undefined ? inl : inl2
                math.push({ tex: tex.trim(), raw: m })
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
        // sacándolo manda la fuente de este Text.
        html = html.replace(/font-size:\s*\d+pt;/g, "")

        // Los <h1..h6> quedan entonces del tamaño del cuerpo — Qt no reescala
        // solo. Se les pone tamaño explícito, relativo al del consumidor.
        const base = root.font.pixelSize
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
        // (render en curso, o sin texlive) vuelven a su texto original.
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
