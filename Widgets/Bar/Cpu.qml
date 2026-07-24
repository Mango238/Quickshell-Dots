import QtQuick
import Quickshell.Widgets
import qs.Commons
import qs.Services

// Vista del uso de CPU. El proceso Rust vive en CpuService (singleton):
// un solo proceso compartido entre las barras de todos los monitores.
WrapperItem {
    id: main

    child: text

    Text {
        id: text
        text: "   " + CpuService.usage + "%"
        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])
    }
}
