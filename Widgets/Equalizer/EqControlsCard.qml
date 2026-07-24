pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects
import qs.Commons

// UI del ecualizador portada de la config de ilyamiro (music/MusicPopup.qml, lineas 966-1471),
// montada sobre el backend propio (filter-chain de PipeWire). El backend no se toca.
Item {
    id: root

    required property var backend

    // --- Mapeo del tema de la referencia (Catppuccin) a Colors.palette ---
    readonly property color cAccent: Colors.accent
    readonly property color cAccentAlt: Qt.lighter(Colors.accent, 1.3)
    readonly property color cText: Colors.ready ? Colors.palette[7] : "#CDD6F4"
    readonly property color cSubText: Qt.alpha(cText, 0.6)
    readonly property color cFreqLabel: Qt.alpha(cText, 0.5)
    readonly property color cOnAccent: Colors.accentText
    readonly property color cTrack: Colors.ready ? Colors.palette[3] : "#313244"
    readonly property color cSurface1: Colors.ready ? Colors.palette[4] : "#45475A"
    readonly property color cSurface2: Colors.ready ? Colors.palette[5] : "#585B70"
    readonly property color cPresetIdle: Qt.alpha(Colors.ready ? Colors.palette[0] : "#1E1E2E", 0.75)

    readonly property bool eqIsBypassed: backend.applyStatus === "Disabled" || backend.applyStatus === "Disabling..."

    // --- Rayo: dos escalares gobiernan todos los efectos ---
    property real eqLightningProgress: 0.0
    property real eqLightningFade: 1.0 // 1.0 = totalmente apagado

    SequentialAnimation {
        id: eqLightningAnim
        ScriptAction { script: { root.eqLightningFade = 0.0; root.eqLightningProgress = 0.0; } }
        NumberAnimation { target: root; property: "eqLightningProgress"; from: 0.0; to: 10.0; duration: 650; easing.type: Easing.OutSine }
        PauseAnimation { duration: 150 }
        NumberAnimation { target: root; property: "eqLightningFade"; from: 0.0; to: 1.0; duration: 800; easing.type: Easing.OutQuad }
        ScriptAction { script: root.eqLightningProgress = 0.0 }
    }
    function triggerEqLightning() { eqLightningAnim.restart(); }

    // --- Animaciones de entrada, escalonadas ---
    property real introEqHeader: 0
    property real introEqSliders: 0
    property real introPresets: 0

    ParallelAnimation {
        running: true
        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: root; property: "introEqHeader"; from: 0; to: 1.0; duration: 710; easing.type: Easing.OutQuart }
        }
        SequentialAnimation {
            PauseAnimation { duration: 120 }
            NumberAnimation { target: root; property: "introEqSliders"; from: 0; to: 1.0; duration: 860; easing.type: Easing.OutExpo }
        }
        SequentialAnimation {
            PauseAnimation { duration: 240 }
            NumberAnimation { target: root; property: "introPresets"; from: 0; to: 1.0; duration: 810; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 15

        // ============ HEADER: titulo + Apply + preset actual ============
        RowLayout {
            Layout.fillWidth: true
            opacity: root.introEqHeader
            transform: Translate { y: 15 * (1 - root.introEqHeader) }

            Text {
                text: "Equalizer"
                color: root.cAccent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 16
                font.bold: true
                Layout.fillWidth: true
            }

            // Boton Apply: el backend reinicia PipeWire (~4-6 s y corta el audio), asi que los
            // cambios de banda se acumulan como pendientes y se aplican de una sola vez.
            Rectangle {
                id: applyBtn
                readonly property bool pending: root.backend.hasPendingEqChanges && !root.backend.isBusy
                Layout.preferredHeight: 28
                Layout.preferredWidth: applyTxt.implicitWidth + 30
                radius: 10
                color: applyBtn.pending ? root.cAccent : root.cSurface1
                border.color: applyBtn.pending ? root.cAccent : root.cSurface2
                border.width: 1

                Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }

                layer.enabled: applyBtn.pending
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.cAccent
                    shadowOpacity: 0.4
                    shadowBlur: 0.6
                }

                Text {
                    id: applyTxt
                    anchors.centerIn: parent
                    text: root.backend.isBusy ? "Applying" : (applyBtn.pending ? "Apply" : "Saved")
                    color: applyBtn.pending ? root.cOnAccent : root.cSubText
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                    Behavior on color { ColorAnimation { duration: 300 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: applyBtn.pending ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (!applyBtn.pending) return;
                        root.triggerEqLightning();
                        root.backend.applyPendingBands();
                    }
                }
            }

            Text {
                text: root.backend.selectedPreset || "Flat"
                color: root.cSubText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
                font.bold: true
                Layout.leftMargin: 15
            }
        }

        // ============ SLIDERS + CANVAS DEL RAYO ============
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 180

            Row {
                id: eqSliderRow
                anchors.fill: parent
                z: 1

                Repeater {
                    model: root.backend.eqFrequencies

                    delegate: Item {
                        id: sliderDelegate
                        required property int index
                        required property string modelData

                        width: eqSliderRow.width / 10
                        height: eqSliderRow.height

                        opacity: root.introEqSliders
                        transform: Translate {
                            y: 30 * (1 - root.introEqSliders) + (sliderDelegate.index * 8 * (1 - root.introEqSliders))
                        }

                        // Posicion del rayo relativa a esta banda
                        property real dist: root.eqLightningProgress - sliderDelegate.index
                        property real hitPulse: dist >= 0 && dist < 1.0 ? Math.sin(dist * Math.PI) : 0.0

                        property real trackPulse: 0.0
                        property real ringPulse: 0.0
                        property real flashFade: 0.0
                        property bool hasFired: false

                        onDistChanged: {
                            if (dist <= 0.05) {
                                hasFired = false;
                            } else if (dist > 0.4 && !hasFired) {
                                hasFired = true;
                                trackPulseAnim.restart();
                                ringPulseAnim.restart();
                                flashFadeAnim.restart();
                            }
                        }

                        NumberAnimation { id: trackPulseAnim; target: sliderDelegate; property: "trackPulse"; from: 0.0; to: 1.0; duration: 1000; easing.type: Easing.OutQuart }
                        NumberAnimation { id: ringPulseAnim; target: sliderDelegate; property: "ringPulse"; from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutExpo }
                        NumberAnimation { id: flashFadeAnim; target: sliderDelegate; property: "flashFade"; from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutSine }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 5

                            Slider {
                                id: eqSlider
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignHCenter
                                orientation: Qt.Vertical
                                from: -12
                                to: 12
                                stepSize: 1
                                enabled: !root.backend.isBusy

                                Component.onCompleted: {
                                    var v = Number(root.backend.eqBands[sliderDelegate.index]);
                                    if (!isNaN(v)) value = v;
                                }

                                // Solo aceptamos valores externos cuando no se esta arrastrando,
                                // para no pelear con el dedo del usuario.
                                Connections {
                                    target: root.backend
                                    function onEqBandsChanged() {
                                        if (eqSlider.pressed) return;
                                        var v = Number(root.backend.eqBands[sliderDelegate.index]);
                                        if (!isNaN(v)) eqSlider.value = v;
                                    }
                                }

                                Behavior on value {
                                    enabled: !eqSlider.pressed
                                    NumberAnimation { duration: 350; easing.type: Easing.OutQuart }
                                }

                                onPressedChanged: {
                                    if (pressed) {
                                        root.backend.beginBandDrag();
                                        return;
                                    }
                                    // setBandFromY espera pixeles: invertimos dB -> y sobre un alto
                                    // nominal de 100. Marca "Unapplied changes" SIN aplicar.
                                    var db = Math.round(value);
                                    root.backend.setBandFromY(sliderDelegate.index, (1 - (db + 12) / 24) * 100, 100);
                                    // Cerramos el drag sin commitBandDrag(): ese aplicaria al instante.
                                    root.backend.bandDragActive = false;
                                }

                                background: Rectangle {
                                    x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                    y: eqSlider.topPadding
                                    implicitWidth: 10
                                    implicitHeight: 150
                                    width: 10
                                    height: eqSlider.availableHeight
                                    radius: 4
                                    color: Qt.alpha(root.cTrack, 0.7)

                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowColor: "#000000"
                                        shadowOpacity: 0.9
                                        shadowBlur: 0.5
                                        shadowVerticalOffset: 1
                                    }

                                    // Onda de choque al pasar el rayo
                                    Rectangle {
                                        z: -1
                                        anchors.centerIn: parent
                                        width: parent.width + 20 + sliderDelegate.ringPulse * 40
                                        height: parent.height + 20 + sliderDelegate.ringPulse * 60
                                        radius: parent.radius + 10 + sliderDelegate.ringPulse * 20
                                        color: "transparent"
                                        border.color: root.cAccent
                                        border.width: 2 + sliderDelegate.ringPulse * 4
                                        opacity: sliderDelegate.ringPulse * 0.8 * (1.0 - root.eqLightningFade)
                                        layer.enabled: true
                                        layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                    }

                                    // Relleno, enmascarado para que respete el radio del track
                                    Item {
                                        width: parent.width
                                        height: (1 - eqSlider.visualPosition) * parent.height
                                        y: eqSlider.visualPosition * parent.height

                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: eqFillMask
                                        }

                                        Rectangle {
                                            id: eqFillMask
                                            anchors.fill: parent
                                            radius: 4
                                            visible: false
                                            layer.enabled: true
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            color: root.cAccent

                                            // Destello que enfria el track tras el impacto
                                            Rectangle {
                                                anchors.fill: parent
                                                opacity: sliderDelegate.flashFade
                                                gradient: Gradient {
                                                    orientation: Gradient.Vertical
                                                    GradientStop { position: 0.0; color: root.cAccentAlt }
                                                    GradientStop { position: 0.5; color: root.cAccent }
                                                    GradientStop { position: 1.0; color: "transparent" }
                                                }
                                            }

                                            // Descarga interna que sube por el track
                                            Rectangle {
                                                width: parent.width
                                                height: 80
                                                y: (sliderDelegate.trackPulse * (parent.height + height)) - height
                                                opacity: Math.sin(sliderDelegate.trackPulse * Math.PI) * 2.0 * (1.0 - root.eqLightningFade)
                                                gradient: Gradient {
                                                    orientation: Gradient.Vertical
                                                    GradientStop { position: 0.0; color: "transparent" }
                                                    GradientStop { position: 0.2; color: root.cAccent }
                                                    GradientStop { position: 0.5; color: root.cText }
                                                    GradientStop { position: 0.8; color: root.cAccentAlt }
                                                    GradientStop { position: 1.0; color: "transparent" }
                                                }
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    shadowEnabled: true
                                                    shadowColor: root.cAccent
                                                    shadowBlur: 1.0
                                                    shadowOpacity: 1.0
                                                }
                                            }
                                        }
                                    }
                                }

                                handle: Rectangle {
                                    x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                    y: eqSlider.topPadding + eqSlider.visualPosition * (eqSlider.availableHeight - height)
                                    implicitWidth: 18
                                    implicitHeight: 18
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: root.cText

                                    scale: 1.0 + (sliderDelegate.hitPulse * 0.4 * (1.0 - root.eqLightningFade))

                                    // Fogonazo al pasar el rayo
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width + 36 * sliderDelegate.hitPulse
                                        height: width
                                        radius: width / 2
                                        color: sliderDelegate.index % 2 === 0 ? root.cAccent : root.cAccentAlt
                                        opacity: sliderDelegate.hitPulse * (1.0 - root.eqLightningFade)
                                        layer.enabled: true
                                        layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                    }
                                }
                            }

                            Text {
                                text: sliderDelegate.modelData
                                color: root.cFreqLabel
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }

            EqLightningCanvas {
                anchors.fill: parent
                z: 0
                eqBands: root.backend.eqBands
                progress: root.eqLightningProgress
                fade: root.eqLightningFade
                strandOuter: root.cAccent
                strandMid: root.cAccentAlt
                strandCore: root.cText
                glowColor: root.cAccent
            }
        }

        // ============ PRESETS: los 10 del backend, en 2 filas de 5 ============
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            opacity: root.introPresets
            transform: Translate { y: 20 * (1 - root.introPresets) }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Repeater {
                    model: root.backend.presetNames.slice(0, 5)
                    delegate: PresetButton {
                        required property string modelData
                        name: modelData
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Repeater {
                    model: root.backend.presetNames.slice(5)
                    delegate: PresetButton {
                        required property string modelData
                        name: modelData
                    }
                }
            }
        }

        // ============ ESTADO + BYPASS ============
        RowLayout {
            Layout.fillWidth: true
            opacity: root.introPresets

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.backend.applyStatus
                color: root.cSubText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.bold: true
            }

            // Toggle: la UI anterior solo desactivaba y no habia forma de reactivar desde aqui.
            Rectangle {
                id: bypassBtn
                readonly property bool bypassed: root.eqIsBypassed
                Layout.preferredHeight: 26
                Layout.preferredWidth: bypassTxt.implicitWidth + 26
                radius: 8
                color: bypassMa.containsMouse ? root.cSurface1 : root.cPresetIdle
                border.width: 1
                border.color: bypassBtn.bypassed ? Colors.danger : root.cSurface2
                opacity: root.backend.isBusy ? 0.5 : 1.0

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    id: bypassTxt
                    anchors.centerIn: parent
                    text: bypassBtn.bypassed ? "Activar EQ" : "Bypass"
                    color: bypassBtn.bypassed ? Colors.danger : root.cSubText
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                MouseArea {
                    id: bypassMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.backend.isBusy) return;
                        if (bypassBtn.bypassed) {
                            root.triggerEqLightning();
                            root.backend.applyToPipeWire(root.backend.eqBands);
                        } else {
                            root.backend.disablePipeWireEq();
                        }
                    }
                }
            }
        }
    }

    // --- Boton de preset ---
    component PresetButton: Rectangle {
        id: presetBtn
        property string name: ""

        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: 8

        readonly property bool isActivePreset: root.backend.selectedPreset === presetBtn.name
        readonly property bool isHovered: hoverMa.containsMouse

        color: presetBtn.isActivePreset ? root.cAccent : (presetBtn.isHovered ? root.cSurface1 : root.cPresetIdle)
        scale: presetBtn.isHovered && !presetBtn.isActivePreset ? 1.05 : 1.0

        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: presetBtn.name
            color: presetBtn.isActivePreset ? root.cOnAccent : (presetBtn.isHovered ? root.cText : root.cSubText)
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.bold: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        MouseArea {
            id: hoverMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.backend.isBusy) return;
                root.triggerEqLightning();
                root.backend.applyPreset(presetBtn.name);
            }
        }
    }
}
