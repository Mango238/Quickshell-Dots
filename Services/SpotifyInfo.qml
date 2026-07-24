pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons

Singleton {
    id: singleton

    property MprisPlayer activePlayer: {
        // Busca Spotify (cliente oficial), luego Spotifyd (daemon
        // ligero via Spotify Connect), o el primer player disponible
        for (const p of Mpris.players.values) {
            if (p.identity === "Spotify") return p;
        }
        for (const p of Mpris.players.values) {
            if (p.identity === "Spotifyd") return p;
        }
        return Mpris.players.values[0] ?? null;
    }

    // 1. La propiedad global sigue igual
    property var trackData: ({
        "title": activePlayer?.trackTitle ?? "Nothing", 
        "artist": activePlayer?.trackArtist ?? "Nobody", 
        "image": activePlayer?.trackArtUrl ?? null,
        "progress": activePlayer?.position ?? null,
        "total": activePlayer?.length ?? null,
        "isPlaying": activePlayer?.isPlaying ?? false,
    })

    property bool spotifyAllActive: false

    // ── Paleta extraída de la carátula del álbum ───────────────────
    // ColorQuantizer solo lee archivos locales y Spotify entrega la
    // carátula como URL https, así que se descarga a caché primero.
    // Mientras no haya carátula local lista, cae a Colors.palette.
    readonly property string _artUrl: activePlayer?.trackArtUrl ?? ""
    property string artFile: ""

    on_ArtUrlChanged: {
        artFile = ""
        if (_artUrl === "")
            return
        if (_artUrl.startsWith("file://")) {
            artFile = _artUrl
            return
        }
        artFetcher.running = false
        artFetcher.url = _artUrl
        artFetcher.running = true
    }

    Process {
        id: artFetcher
        // Asignada explícitamente antes de running=true para evitar que el
        // binding de command se evalúe con una URL vieja o vacía.
        property string url: ""
        property string cacheDir:
            (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
            + "/quickshell/albumart"
        command: ["sh", "-c",
            "mkdir -p '" + cacheDir + "' && f='" + cacheDir + "/'$(basename '"
            + url + "') && { [ -s \"$f\" ] || curl -sfL '"
            + url + "' -o \"$f\"; } && echo \"$f\""]

        stdout: StdioCollector {
            id: artCollector
            onStreamFinished: {
                const path = artCollector.text.trim()
                if (path !== "")
                    singleton.artFile = "file://" + path
            }
        }
    }

    ColorQuantizer {
        id: albumQuantizer
        // Con source vacío QFSFileEngine emite un warning: el placeholder
        // lo evita mientras no hay carátula descargada.
        source: singleton.artFile !== ""
            ? singleton.artFile
            : Qt.resolvedUrl("../Assets/No_cover.jpg")
        depth: 3
        rescaleSize: 512
    }

    readonly property var albumPalette:
        (artFile !== "" && albumQuantizer.colors
         && albumQuantizer.colors.length > 0)
            ? OrderColors.extrapolateAndSort(albumQuantizer.colors, 10)
            : Colors.palette

    // Segundos → "m:ss" para las etiquetas de progreso
    function formatTime(secs) {
        if (secs === null || secs === undefined || isNaN(secs) || secs < 0)
            return "0:00"
        const s = Math.floor(secs)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
}
