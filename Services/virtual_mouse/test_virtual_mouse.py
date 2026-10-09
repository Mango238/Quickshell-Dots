#!/usr/bin/env python3
"""Checks de la lógica pura: no toca cámara ni /dev/uinput.

    venv/bin/python test_virtual_mouse.py
"""

import threading

from main import (
    SENSITIVITY,
    accumulate_scroll,
    drag_anchor,
    pick_gesture,
    sensitivity_for_span,
    should_infer,
    smooth_span,
)
from VirtualMouse import CursorEmitter, OneEuroFilter, map_to_screen

ENTER, EXIT = 22.0, 32.0  # PINCH_ENTER/EXIT * hand_span con span = 100 px
DT = 1.0 / 30.0  # paso de la cámara


def fake_emitter(ease=0.35):
    """CursorEmitter sin __init__: no arranca el hilo, se llama _tick() a mano."""
    e = object.__new__(CursorEmitter)
    e.ui, e.period, e.ease = None, 1 / 120.0, ease
    e.cond = threading.Condition()
    e.target, e.pos, e.last_sent = None, None, None
    e.ticks, e.running = 0, False
    return e


def test_scroll_conserva_fracciones_y_es_simetrico():
    accum, clicks_total = 0.0, 0
    for _ in range(3):
        clicks, accum = accumulate_scroll(accum, 0.4, 1.0)
        clicks_total += clicks
    assert clicks_total == 1, f"3 pasos de 0.4 deberían dar 1 click, dieron {clicks_total}"

    accum, clicks_total = 0.0, 0
    for _ in range(3):
        clicks, accum = accumulate_scroll(accum, -0.4, 1.0)
        clicks_total += clicks
    assert clicks_total == -1, f"el espejo negativo debería dar -1, dio {clicks_total}"

    # Sin acumulador (el bug viejo: int(amount/150)) cada paso truncaba a 0 y el
    # movimiento se perdía entero.
    assert accumulate_scroll(0.0, 0.4, 1.0)[0] == 0


def test_histeresis_no_hace_chatter():
    # hold=1 aisla la histéresis del debounce: acá se prueba solo que cruzar hacia abajo
    # y volver a la zona muerta no suelta el botón.
    active, presses, releases = None, 0, 0
    # Oscila ENTRE los dos umbrales: con un solo umbral esto daba un click por frame.
    for d in (20.0, 25.0, 20.0, 25.0, 20.0):
        active, event, _ = pick_gesture(active, {"left": d}, ENTER, EXIT, hold=1)
        if event and event[0] == "press":
            presses += 1
        if event and event[0] == "release":
            releases += 1
    assert (presses, releases) == (1, 0), f"esperaba 1 press y 0 releases, dio {presses}/{releases}"

    active, event, _ = pick_gesture(active, {"left": 40.0}, ENTER, EXIT, hold=1)
    assert event == ("release", "left") and active is None


def test_un_solo_gesto_a_la_vez():
    # Pinzar el medio acerca también el índice: antes disparaban los dos.
    dists = {"left": 20.0, "right": 18.0, "scroll": 50.0}
    active, event, _ = pick_gesture(None, dists, ENTER, EXIT, hold=1)
    assert active == "right" and event == ("press", "right"), "gana el pinch más cerrado"

    # Con 'right' activo, el izquierdo cerrándose a fondo no debe disparar nada.
    active, event, _ = pick_gesture(active, {**dists, "left": 5.0}, ENTER, EXIT, hold=1)
    assert active == "right" and event is None


def test_span_cero_no_crashea():
    s = sensitivity_for_span(0.0)  # muñeca y MCP en el mismo píxel
    assert s > 0 and s == sensitivity_for_span(1.0), "el clamp debe absorber spans mínimos"
    assert sensitivity_for_span(200.0) < sensitivity_for_span(100.0), "más lejos, más sensible"


def test_filtro_suprime_jitter_en_reposo():
    f = OneEuroFilter()
    señal = [320.0 + (1.0 if i % 2 else -1.0) for i in range(60)]  # constante +- 1 px
    salida = [f(x, DT) for x in señal]

    cola_in, cola_out = señal[30:], salida[30:]
    amp_in = max(cola_in) - min(cola_in)
    amp_out = max(cola_out) - min(cola_out)
    assert amp_out < amp_in / 4, f"jitter mal suprimido: {amp_in:.2f} -> {amp_out:.2f}"
    assert abs(sum(cola_out) / len(cola_out) - 320.0) < 0.2, "debe converger al valor real"


def test_filtro_sigue_una_rampa_mejor_que_un_lowpass_fijo():
    # beta abre el cutoff con la velocidad: eso es lo que evita el lag al barrer.
    # Un low-pass con el mismo min_cutoff pero sin adaptación queda más atrás.
    adaptativo = OneEuroFilter()  # los defaults que se envían
    fijo = OneEuroFilter(beta=0.0)

    x = 200.0
    for _ in range(40):
        x += 15.0  # 450 px/s, un barrido de mano normal
        y_ad, y_fijo = adaptativo(x, DT), fijo(x, DT)

    err_ad, err_fijo = x - y_ad, x - y_fijo
    assert err_ad < err_fijo / 2, f"beta no está ayudando: {err_ad:.1f} vs {err_fijo:.1f} px"


def test_emisor_interpola_entre_frames_de_camara():
    # El problema medido: a 30 Hz el cursor salta ~75 px de golpe. El emisor a 120 Hz
    # debe partir ese salto en varios pasos mucho más chicos.
    e = fake_emitter(ease=0.35)
    e.set_target(1000.0, 500.0)
    e.pos = (925.0, 500.0)  # 75 px por recorrer, el salto medido de un frame
    e.last_sent = (925, 500)

    pasos, prev = [], 925
    for _ in range(4):  # 4 ticks de 120 Hz = un intervalo de cámara de 33 ms
        out = e._tick()
        assert out is not None, "cada tick del intervalo debe producir una posición nueva"
        pasos.append(out[0] - prev)
        prev = out[0]

    assert len(pasos) == 4, f"esperaba 4 posiciones intermedias, hubo {len(pasos)}"
    assert max(pasos) < 30, f"el paso máximo sigue siendo grande: {max(pasos)} px"
    assert sum(pasos) > 50, f"debe avanzar la mayor parte de los 75 px: avanzó {sum(pasos)}"

    # Duplicados: sin movimiento del objetivo, converge y deja de escribir.
    for _ in range(200):
        e._tick()
    assert e._tick() is None, "convergido no debe seguir emitiendo la misma posición"
    assert e._idle(), "convergido: el hilo debe poder dormir"
    e.set_target(1100.0, 500.0)
    assert not e._idle(), "un objetivo nuevo debe despertarlo"


def test_gate_de_movimiento_infiere_por_cualquiera_de_las_cuatro_condiciones():
    G = 15  # TRACK_GRACE
    assert not should_infer(G, 0, 0), "reposo sin mano: no inferir"
    assert should_infer(0, 0, 0), "con mano recién vista siempre infiere"
    assert should_infer(G - 1, 0, 0), "dentro de la gracia sigue infiriendo aunque nada se mueva"
    assert should_infer(G, 3, 0), "movimiento >= MOTION_CELLS despierta"
    assert not should_infer(G, 2, 5), "ruido bajo el umbral no despierta"
    assert should_infer(G, 0, 6), "cada IDLE_FORCE_EVERY frames se fuerza"


def test_press_necesita_dos_frames():
    # Un frame aislado de landmarks ruidosos (motion blur) no debe soltar un click.
    active, event, pending = pick_gesture(None, {"left": 20.0}, ENTER, EXIT, hold=2)
    assert (active, event) == (None, None) and pending == ("left", 1), "un frame no alcanza"

    active, event, pending = pick_gesture(None, {"left": 20.0}, ENTER, EXIT, pending, hold=2)
    assert event == ("press", "left") and active == "left" and pending is None

    # Dudar entre dos gestos reinicia la cuenta: no se acumulan frames de gestos distintos.
    _, _, pending = pick_gesture(None, {"left": 20.0, "right": 50.0}, ENTER, EXIT, None, 2)
    _, event, pending = pick_gesture(None, {"left": 50.0, "right": 20.0}, ENTER, EXIT, pending, 2)
    assert event is None and pending == ("right", 1), "el cambio de gesto debe reiniciar"


def test_release_no_se_debouncea():
    # Un botón trabado es peor que uno que se suelta de más: el release sale al toque.
    active, event, pending = pick_gesture("left", {"left": 40.0}, ENTER, EXIT, hold=5)
    assert event == ("release", "left") and active is None and pending is None


def test_congela_el_cursor_durante_el_click():
    press, break_px = (100.0, 100.0), 12.0
    # Micro-movimiento del propio pinch: el cursor NO se mueve.
    for x, y in ((100.0, 100.0), (105.0, 100.0), (100.0, 108.0), (95.0, 95.0)):
        point, offset = drag_anchor(x, y, press, None, break_px)
        assert point is None and offset is None, f"({x},{y}) debería quedar congelado"


def test_arrastre_no_salta_al_romper_el_umbral():
    press, break_px = (100.0, 100.0), 12.0

    # Al cruzar, el primer punto es exactamente el congelado: el arrastre empieza donde
    # el cursor ya estaba, sin teletransporte.
    point, offset = drag_anchor(120.0, 100.0, press, None, break_px)
    assert point == press, f"el arrastre debe arrancar en el punto congelado, dio {point}"
    assert offset is not None, "cruzar el umbral debe fijar el offset"

    # Y desde ahí sigue 1:1 con la mano.
    p2, offset2 = drag_anchor(125.0, 100.0, press, offset, break_px)
    assert offset2 == offset, "el offset queda fijo una vez que arranca el arrastre"
    assert abs((p2[0] - point[0]) - 5.0) < 1e-9, f"la mano avanzó 5 px, el cursor {p2[0]-point[0]}"


def test_span_suavizado_mata_el_jitter_de_sensibilidad():
    # El hallazgo: la sensibilidad sale del span y se aplica DESPUÉS del One Euro, así que
    # el ruido del span pasa al cursor sin filtrar. Peor cuanto más lejos del centro.
    SW, SH = 1920, 1200
    # 3/4 del área activa: con el 0.75 hardcodeado, subir SENSITIVITY lo dejaba
    # fuera de la zona y el clamp daba 0 px de temblor (test midiendo nada).
    NX = 0.5 + 0.375 / SENSITIVITY
    ruido = [1.015 if i % 2 else 0.985 for i in range(40)]  # +-1.5 %

    def cursor_x(span):
        return map_to_screen(NX, 0.5, sensitivity_for_span(span), SW, SH)[0]

    crudo = [cursor_x(100.0 * r) for r in ruido]

    prev = None
    for r in ruido[:20]:  # dejar que el EMA converja antes de medir
        prev = smooth_span(prev, 100.0 * r)
    suave = []
    for r in ruido[20:]:
        prev = smooth_span(prev, 100.0 * r)
        suave.append(cursor_x(prev))

    amp_crudo = max(crudo) - min(crudo)
    amp_suave = max(suave) - min(suave)
    assert amp_crudo > 15.0, f"el caso base debería temblar fuerte, dio {amp_crudo:.1f} px"
    assert amp_suave < amp_crudo / 5, f"jitter de span mal suprimido: {amp_crudo:.1f} -> {amp_suave:.1f} px"


def test_span_arranca_sin_barrido():
    # Mano que reaparece a otra distancia: hay que empezar EN el valor nuevo, no barrer
    # hacia él (barrer daría unos frames con la sensibilidad de la posición vieja).
    assert smooth_span(None, 60.0) == 60.0
    assert 100.0 < smooth_span(100.0, 200.0) < 200.0, "ya arrancado, sí debe suavizar"


def test_dry_run_no_necesita_uinput():
    from VirtualMouse import VirtualMouse

    m = VirtualMouse(1920, 1200, 640, 480, 2.2, dry_run=True)
    m.move(320.0, 240.0, 1 / 30)
    m.click("left", 1)
    m.scroll(1)
    m.close()


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"ok  {t.__name__}")
    print(f"\n{len(tests)} checks pasaron")
