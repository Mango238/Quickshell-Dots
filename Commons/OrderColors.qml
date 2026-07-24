pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    // ─────────────────────────────────────────────────────────────
    //  extrapolateAndSort(colors, quota)
    //
    //  colors : String[]  →  array de colores hex  (ej: ["#ff0000", "#3a7bd5"])
    //  quota  : int       →  cantidad mínima de colores a retornar
    //
    //  Retorna: String[]  →  array de hex ordenado de menor a mayor
    //                        luminosidad, con length >= quota
    // ─────────────────────────────────────────────────────────────
    function extrapolateAndSort(colors, quota) {

        // ── helpers ────────────────────────────────────────────────

        function hexToRgb(hex) {
            hex = hex.toString()
            hex = hex.replace(/^#/, "")
            if (hex.length === 3)
                hex = hex.split("").map(c => c + c).join("")
            return {
                r: parseInt(hex.slice(0, 2), 16),
                g: parseInt(hex.slice(2, 4), 16),
                b: parseInt(hex.slice(4, 6), 16)
            }
        }

        function rgbToHex(r, g, b) {
            return "#" + [r, g, b].map(v => {
                return Math.round(Math.max(0, Math.min(255, v)))
                           .toString(16)
                           .padStart(2, "0")
            }).join("")
        }

        // Luminosidad perceptual  (ITU-R BT.601)
        function luminance(hex) {
            const c = hexToRgb(hex)
            return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        }

        // Interpola linealmente entre dos colores  (t ∈ [0,1])
        function lerp(hexA, hexB, t) {
            const a = hexToRgb(hexA)
            const b = hexToRgb(hexB)
            return rgbToHex(
                a.r + (b.r - a.r) * t,
                a.g + (b.g - a.g) * t,
                a.b + (b.b - a.b) * t
            )
        }

        // ── validación básica ──────────────────────────────────────

        if (!colors || colors.length === 0) {
            console.warn("ColorPalette: el array de entrada está vacío.")
            return []
        }

        // ── extrapolación ──────────────────────────────────────────
        // Estrategia: en cada pasada insertamos el punto medio entre
        // el par con mayor distancia de luminosidad (greedy).
        // Así los colores nuevos llenan los huecos más grandes primero.

        let result = colors.slice()

        // Caso especial: un solo color → generar variaciones de brillo
        if (result.length === 1) {
            const base = hexToRgb(result[0])
            for (let i = 1; result.length < quota; i++) {
                const f = Math.max(0, 1 - i * (1 / quota))
                result.push(rgbToHex(base.r * f, base.g * f, base.b * f))
            }
        }

        // Caso general: interpolación guiada por huecos de luminosidad
        while (result.length < quota) {
            let maxGap  = -1
            let maxIdx  = 0

            for (let i = 0; i < result.length - 1; i++) {
                const gap = Math.abs(luminance(result[i + 1]) - luminance(result[i]))
                if (gap > maxGap) {
                    maxGap = gap
                    maxIdx = i
                }
            }

            const mid = lerp(result[maxIdx], result[maxIdx + 1], 0.5)
            result.splice(maxIdx + 1, 0, mid)
        }

        // ── ordenar por luminosidad (oscuro → claro) ───────────────

        result.sort((a, b) => luminance(a) - luminance(b))

        return result
    }

    // ------------ CONTRASTE -------------

    function getLuminance(hexColor) {
        // Asegurarnos de que sea un string y quitar el '#'
        var colorStr = String(hexColor).replace(/^#/, '');
        
        // Si QML pasa un color con canal Alpha (AARRGGBB), extraemos solo el RGB
        if (colorStr.length === 8) {
            colorStr = colorStr.substring(2); 
        } 
        // Si es un hex corto (#RGB)
        else if (colorStr.length === 3) {
            colorStr = colorStr[0]+colorStr[0] + colorStr[1]+colorStr[1] + colorStr[2]+colorStr[2];
        }

        // Convertir a RGB y normalizar
        var r = parseInt(colorStr.substring(0, 2), 16) / 255.0;
        var g = parseInt(colorStr.substring(2, 4), 16) / 255.0;
        var b = parseInt(colorStr.substring(4, 6), 16) / 255.0;

        // Aplicar la corrección gamma a cada canal
        var canales = [r, g, b].map(function (c) {
            return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
        });

        // Retornar la luminancia relativa
        return 0.2126 * canales[0] + 0.7152 * canales[1] + 0.0722 * canales[2];
    }

    function getContrastRatio(color1, color2) {
        var l1 = getLuminance(color1);
        var l2 = getLuminance(color2);

        var L1 = Math.max(l1, l2);
        var L2 = Math.min(l1, l2);

        var ratio = (L1 + 0.05) / (L2 + 0.05);
        return Math.round(ratio * 100) / 100; // Redondear a 2 decimales
    }

    // Interpolación RGB lineal entre dos colores (t ∈ [0,1]).
    // (Duplicada a propósito del lerp local de extrapolateAndSort, que no es
    // accesible desde fuera de esa función.)
    function mixColors(colorA, colorB, t) {
        function toRgb(hex) {
            var s = String(hex).replace(/^#/, '');
            if (s.length === 8) s = s.substring(2);
            if (s.length === 3) s = s[0]+s[0] + s[1]+s[1] + s[2]+s[2];
            return {
                r: parseInt(s.substring(0, 2), 16),
                g: parseInt(s.substring(2, 4), 16),
                b: parseInt(s.substring(4, 6), 16)
            };
        }
        var a = toRgb(colorA);
        var b = toRgb(colorB);
        function chan(x) {
            return Math.round(Math.max(0, Math.min(255, x)))
                       .toString(16).padStart(2, "0");
        }
        return "#" + chan(a.r + (b.r - a.r) * t)
                   + chan(a.g + (b.g - a.g) * t)
                   + chan(a.b + (b.b - a.b) * t);
    }

    // Devuelve el color MÁS CERCANO a fg que alcanza minRatio contra bg:
    // mezcla fg hacia blanco (fondo oscuro) o negro (fondo claro) buscando
    // por bisección la t mínima que cumple. Así el sustituto conserva el
    // tono de fg en vez de saltar a blanco/negro puros, y funciona incluso
    // desde negro puro (la mezcla mueve el canal aunque el value HSV sea 0,
    // a diferencia de Qt.lighter).
    function adjustForContrast(fg, bg, minRatio) {
        if (getContrastRatio(fg, bg) >= minRatio)
            return fg;

        var target = getLuminance(bg) < 0.5 ? "#ffffff" : "#000000";
        if (getContrastRatio(target, bg) < minRatio) {
            // Dirección preferida insuficiente: probar la contraria (para
            // minRatio <= 4.5 al menos una de las dos siempre alcanza).
            target = (target === "#ffffff") ? "#000000" : "#ffffff";
            if (getContrastRatio(target, bg) < minRatio)
                return target; // inalcanzable: mejor esfuerzo
        }

        // Bisección de la t mínima que cumple (8 iteraciones ≈ 1/256).
        var lo = 0.0;
        var hi = 1.0;
        for (var i = 0; i < 8; i++) {
            var mid = (lo + hi) / 2;
            if (getContrastRatio(mixColors(fg, target, mid), bg) >= minRatio)
                hi = mid;
            else
                lo = mid;
        }
        return mixColors(fg, target, hi);
    }

    // Función extra muy útil: Elige automáticamente texto blanco o negro según el fondo
    function getReadableTextColor(bgColor) {
        var contrastWithWhite = getContrastRatio(bgColor, "#FFFFFF");
        var contrastWithBlack = getContrastRatio(bgColor, "#000000");
        
        // Retorna el color que tenga mejor contraste
        return contrastWithWhite >= contrastWithBlack ? "#FFFFFF" : "#000000";
    }

}
