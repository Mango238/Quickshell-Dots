import QtQuick
import QtQuick.Shapes

/**
 * PanelBackground - Dynamic ShapePath for rendering panel backgrounds
 *
 * Self-contained and reusable. All previously external dependencies
 * (Color, Style, ShapeCornerHelper) are declared inline as properties
 * or JS helper functions.
 *
 * Corner states per corner (topLeft, topRight, bottomRight, bottomLeft):
 *   -1 : No radius (flat/square corner)
 *    0 : Normal (inner curve)
 *    1 : Horizontal inversion (outer curve on X-axis)
 *    2 : Vertical inversion (outer curve on Y-axis)
 *
 * Minimal usage example:
 *
 *   Shape {
 *       PanelBackground {
 *           panelX: 100; panelY: 100
 *           panelWidth: 300; panelHeight: 200
 *       }
 *   }
 */
ShapePath {
    id: root

    // ── Geometry ──────────────────────────────────────────────────────────────
    property real tRadiusFactor: 1
    property real bRadiusFactor: 1

    // Set these to position and size the panel background.
    property real panelX:      0
    property real panelY:      0
    property real panelWidth:  0
    property real panelHeight: 0

    // ── Appearance ────────────────────────────────────────────────────────────
    // Background fill color.
    property color backgroundColor: "#1E1E2E"   // replaces Color.mSurface
    property var backgroundGradient: null

    // Base corner radius.
    property real radius: 12                     // replaces Style.radiusL

    // ── Per-corner states ─────────────────────────────────────────────────────
    property int topLeftCornerState:     1
    property int topRightCornerState:    1
    property int bottomRightCornerState: 0
    property int bottomLeftCornerState:  0

    // ── ShapeCornerHelper (inlined) ───────────────────────────────────────────

    /**
     * Returns the X multiplier for a given corner state.
     *  0 → 1  (normal inner curve, moves right/left)
     *  1 → -1 (horizontal inversion, flips X direction)
     *  2 → 1  (vertical inversion, X direction unchanged)
     * -1 → 1  (flat corner, multiplier irrelevant but safe)
     */
    function getMultX(cornerState) {
        return (cornerState === 1) ? -1 : 1
    }

    /**
     * Returns the Y multiplier for a given corner state.
     *  0 → 1  (normal inner curve, moves down/up)
     *  1 → 1  (horizontal inversion, Y direction unchanged)
     *  2 → -1 (vertical inversion, flips Y direction)
     * -1 → 1  (flat corner, multiplier irrelevant but safe)
     */
    function getMultY(cornerState) {
        return (cornerState === 2) ? -1 : 1
    }

    /**
     * Returns the PathArc sweep direction for a given pair of multipliers.
     * Clockwise when both multipliers are positive or both negative,
     * counter-clockwise when they differ.
     */
    function getArcDirection(multX, multY) {
        return (multX * multY > 0) ? PathArc.Clockwise : PathArc.Counterclockwise
    }

    /**
     * Returns true when the panel is too small to fit the full radius,
     * i.e. either dimension is smaller than 2× the desired radius.
     */
    function shouldFlatten(w, h, r) {
        return (w < r * 2) || (h < r * 2)
    }

    /**
     * Returns a safe radius that fits inside a panel whose smallest
     * dimension is 'minDim'.  Caps at half that dimension.
     */
    function getFlattenedRadius(minDim, r) {
        return Math.min(r, minDim / 2)
    }

    // ── Derived / computed properties ────────────────────────────────────────

    readonly property bool  _flatten:        shouldFlatten(panelWidth, panelHeight, radius)
    readonly property real  effectiveRadius: _flatten
                                             ? getFlattenedRadius(Math.min(panelWidth, panelHeight), radius)
                                             : radius

    /** Returns 0 for flat corners (state -1), effectiveRadius otherwise. */
    function getCornerRadius(cornerState) {
        return (cornerState === -1) ? 0 : effectiveRadius
    }

    // Top-left
    readonly property real tlMultX:  getMultX(topLeftCornerState)
    readonly property real tlMultY:  getMultY(topLeftCornerState)
    readonly property real tlRadius: getCornerRadius(topLeftCornerState) * tRadiusFactor

    // Top-right
    readonly property real trMultX:  getMultX(topRightCornerState)
    readonly property real trMultY:  getMultY(topRightCornerState)
    readonly property real trRadius: getCornerRadius(topRightCornerState) * tRadiusFactor

    // Bottom-right
    readonly property real brMultX:  getMultX(bottomRightCornerState)
    readonly property real brMultY:  getMultY(bottomRightCornerState)
    readonly property real brRadius: getCornerRadius(bottomRightCornerState) * bRadiusFactor

    // Bottom-left
    readonly property real blMultX:  getMultX(bottomLeftCornerState)
    readonly property real blMultY:  getMultY(bottomLeftCornerState)
    readonly property real blRadius: getCornerRadius(bottomLeftCornerState) * bRadiusFactor

    // ── Huella real de la forma ──────────────────────────────────────────────
    // Las esquinas con inversión horizontal (estado 1) sobresalen del rect
    // panelX/panelWidth. Estas propiedades permiten al consumidor dimensionar
    // el contenedor sin repetir la aritmética de radios.
    readonly property real overhangLeft:  Math.max(
        topLeftCornerState    === 1 ? tlRadius : 0,
        bottomLeftCornerState === 1 ? blRadius : 0)
    readonly property real overhangRight: Math.max(
        topRightCornerState    === 1 ? trRadius : 0,
        bottomRightCornerState === 1 ? brRadius : 0)
    readonly property real totalWidth: panelWidth + overhangLeft + overhangRight

    // ── ShapePath configuration ───────────────────────────────────────────────
    strokeWidth: -1                       // Fill only, no stroke
    fillColor: backgroundGradient !== null ? "transparent" : backgroundColor
    fillGradient: backgroundGradient
    // Starting point: top edge, just after the top-left arc
    startX: panelX + tlRadius * tlMultX
    startY: panelY

    // ── Path ─────────────────────────────────────────────────────────────────

    // Top edge → right
    PathLine {
        relativeX: root.panelWidth - root.tlRadius * root.tlMultX - root.trRadius * root.trMultX
        relativeY: 0
    }

    // Top-right corner
    PathArc {
        relativeX:  root.trRadius * root.trMultX
        relativeY:  root.trRadius * root.trMultY
        radiusX:    root.trRadius
        radiusY:    root.trRadius
        direction:  root.getArcDirection(root.trMultX, root.trMultY)
    }

    // Right edge ↓
    PathLine {
        relativeX: 0
        relativeY: root.panelHeight - root.trRadius * root.trMultY - root.brRadius * root.brMultY
    }

    // Bottom-right corner
    PathArc {
        relativeX: -root.brRadius * root.brMultX
        relativeY:  root.brRadius * root.brMultY
        radiusX:    root.brRadius
        radiusY:    root.brRadius
        direction:  root.getArcDirection(root.brMultX, root.brMultY)
    }

    // Bottom edge ← left
    PathLine {
        relativeX: -(root.panelWidth - root.brRadius * root.brMultX - root.blRadius * root.blMultX)
        relativeY: 0
    }

    // Bottom-left corner
    PathArc {
        relativeX: -root.blRadius * root.blMultX
        relativeY: -root.blRadius * root.blMultY
        radiusX:    root.blRadius
        radiusY:    root.blRadius
        direction:  root.getArcDirection(root.blMultX, root.blMultY)
    }

    // Left edge ↑ back to start
    PathLine {
        relativeX: 0
        relativeY: -(root.panelHeight - root.blRadius * root.blMultY - root.tlRadius * root.tlMultY)
    }

    // Top-left corner (closes path)
    PathArc {
        relativeX:  root.tlRadius * root.tlMultX
        relativeY: -root.tlRadius * root.tlMultY
        radiusX:    root.tlRadius
        radiusY:    root.tlRadius
        direction:  root.getArcDirection(root.tlMultX, root.tlMultY)
    }
}

