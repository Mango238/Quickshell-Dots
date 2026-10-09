#!/usr/bin/env python3

import argparse
import csv
import json
import math
import os
import signal
import subprocess
import sys
import time

import cv2
from mediapipe import Image, ImageFormat
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import HandLandmarker, HandLandmarkerOptions, RunningMode

from VirtualMouse import VirtualMouse

# --- CONFIGURACIÓN ---
CAMERA_WIDTH = 640
CAMERA_HEIGHT = 480
CAMERA_DEVICE = "/dev/video0"

# API Tasks (mediapipe 1.1.0): un solo modelo, full float16; no hay knob de complexity
# (la API legacy usaba complexity 0 = Lite). No viene en el wheel: se descarga aparte.
# Medido en Core Ultra 5 226V con delegate CPU: sin mano p50 16 ms (legacy lite: 9), mano
# trackeada 14.5 ms (5.3); con delegate GPU (el default, ver BaseOptions) p50 10 / p95 14.4 ms.
MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hand_landmarker.task")

# Área activa = 45% central del frame (291 de 640 px): el borde de la zona queda a
# nx≈0.27 del borde del frame, así la mano ENTERA sigue visible para MediaPipe aun
# apuntando a un borde de pantalla (con 1.5 el ancla llegaba a 0.167 y los dedos/muñeca salían).
SENSITIVITY = 2.2

# Suavizado: ver MIN_CUTOFF / BETA / EMIT_EASE en VirtualMouse.py. No hay dead zone —
# el filtro One Euro se encarga del jitter, y una dead zone produce el "pega y salta"
# que es justo lo contrario de un desplazamiento suave.

# Span de referencia (muñeca -> MCP del medio, en px de cámara) al que SENSITIVITY
# vale tal cual. Más lejos la mano => span menor => más sensibilidad, para que el
# recorrido en pantalla no dependa de la distancia a la cámara.
HAND_SPAN_REF = 107.0
MIN_HAND_SPAN = 20.0  # clamp: evita ZeroDivisionError y sensibilidades absurdas

# El span sale de dos landmarks ruidosos y de él sale la sensibilidad, que map_to_screen
# aplica DESPUÉS del filtro One Euro: ese temblor el filtro no puede verlo. Medido, 1.5 %
# de ruido en el span da 21.6 px de temblor del cursor a 3/4 del área activa (y 0 en el
# centro, que es por qué se notaba más en los bordes). Un EMA agresivo lo mata sin costar
# responsividad, porque el span NO es la señal de posición: la distancia a la cámara
# cambia en segundos, no entre frames.
# Medido en nx=0.75 con ruido de span σ=1.5%: crudo 67.5 px de temblor, con ease 0.08
# quedan 11.5 px, y una acercada real de la mano se acomoda en 0.93 s. Se puede bajar
# más (0.05 -> 8.6 px) a costa de 1.5 s, que ya se nota al inclinarse hacia la cámara.
SPAN_EASE = 0.08

# Umbrales de pinch como fracción de hand_span. Histéresis tipo Schmitt: se entra al
# gesto en ENTER y se suelta en EXIT. Con un solo umbral hay chatter en la frontera
# (click/release/click a 30 fps).
PINCH_ENTER = 0.22
PINCH_EXIT = 0.32

# Congelar el cursor mientras un botón está apretado. Pinzar mueve la mano unos px, así
# que el click aterrizaba corrido y el release en otro lado (micro-arrastre en vez de
# click). Se descongela solo si la mano se aleja más de DRAG_BREAK * hand_span del punto
# de press: eso es lo que separa un click de un arrastre deliberado.
DRAG_BREAK = 0.12

# Frames consecutivos con el mismo gesto antes de disparar el press. La histéresis mata el
# chatter EN la frontera, pero no un frame aislado de landmarks ruidosos que cae muy por
# debajo del umbral (motion blur al mover rápido) y suelta un click fantasma. Cuesta un
# frame de latencia (~33 ms); 1 lo desactiva.
PRESS_HOLD_FRAMES = 2

SCROLL_GAIN = 0.15  # clicks de rueda por px de cámara desplazado verticalmente
SCROLL_INVERT = False  # signo de REL_WHEEL: confirmar sobre hardware real

# Landmarks de MediaPipe Hands usados. 9 (MCP del medio) es el ancla del cursor:
# es un punto del palmo, así que NO se mueve al pinzar. Usar la punta de los dedos
# hacía que el propio pinch arrastrara el cursor antes de cruzar el umbral.
WRIST, THUMB_TIP, INDEX_TIP, MIDDLE_MCP, MIDDLE_TIP, RING_TIP = 0, 4, 8, 9, 12, 16

# Gate de movimiento: sin mano y sin nada moviéndose no se corre MediaPipe (el detector de palma
# es lo más caro). Se compara una miniatura 32x24 con la del frame anterior.
# ponytail: diferencia por canal (0-255) para contar una celda como cambiada. Calibración: ver MOTION_CELLS.
MOTION_PIX_THR = 20
# ponytail: celdas cambiadas (de 768) para despertar la inferencia. Calibrar con la cámara real sin mano:
# p99 del ruido (flicker de exposición) debe quedar < MOTION_CELLS. Una mano a ~100 px de span cubre ~5x5 celdas.
MOTION_CELLS = 3
# ponytail: inferir al menos cada N frames (0.2 s) aunque no haya movimiento: cubre prender el toggle
# con la mano ya quieta delante de la cámara. En reposo quedan ~1/N de las inferencias.
IDLE_FORCE_EVERY = 6
# Frames (0.5 s) tras la última mano vista en los que se sigue infiriendo aunque no haya
# movimiento: si MediaPipe pierde la mano un frame (quieta, motion blur) la recupera al frame
# siguiente, igual que sin gate. Solo después de medio segundo sin mano entra el gate.
TRACK_GRACE = 15

FPS_REPORT_EVERY = 2.0  # s. El Hz del emisor baja a 0 en reposo (hilo dormido): es lo esperado

# Tuning en vivo bajo --preview: tecla -> (knob, factor). Pasos multiplicativos porque
# estos knobs abarcan órdenes de magnitud; un paso aditivo sería inútil en un extremo.
TUNING_KEYS = {
    "[": ("min_cutoff", 1 / 1.2),
    "]": ("min_cutoff", 1.2),
    "-": ("beta", 1 / 1.5),
    "=": ("beta", 1.5),
    "+": ("beta", 1.5),
    "o": ("d_cutoff", 1 / 1.3),
    "p": ("d_cutoff", 1.3),
    ",": ("ease", 1 / 1.15),
    ".": ("ease", 1.15),
    ";": ("sensitivity", 1 / 1.1),
    "'": ("sensitivity", 1.1),
}
TUNING_LIMITS = {
    "min_cutoff": (0.05, 30.0),
    "beta": (0.0005, 2.0),
    "d_cutoff": (0.05, 5.0),
    "ease": (0.02, 0.99),  # 1.0 sería no interpolar; >1 oscilaría
    "sensitivity": (0.5, 6.0),
}


def get_dist(p1, p2, w, h):
    return math.hypot((p1.x - p2.x) * w, (p1.y - p2.y) * h)


def should_infer(frames_since_hand, changed, frames_since_infer, hold=IDLE_FORCE_EVERY, grace=TRACK_GRACE):
    """Gate de movimiento: ¿hay que correr MediaPipe en este frame? Función pura.

    `frames_since_hand` = frames desde la última inferencia que vio una mano (0 = la vio
    recién). Mientras sea < grace se infiere siempre: con mano presente el gate no existe.
    """
    return frames_since_hand < grace or changed >= MOTION_CELLS or frames_since_infer >= hold


def sensitivity_for_span(hand_span, base=SENSITIVITY):
    """Compensa la distancia a la cámara: mano más lejos (span menor) -> más sensible.

    El clamp es lo que evita el ZeroDivisionError cuando muñeca y MCP caen en el mismo
    píxel (mano muy lejos, o glitch de detección), que tiraba la app entera.
    """
    return base * HAND_SPAN_REF / max(hand_span, MIN_HAND_SPAN)


def smooth_span(prev, raw, ease=SPAN_EASE):
    """EMA del hand_span. `prev` None (primer frame, o la mano reapareció) arranca en raw
    en vez de barrer desde un valor viejo."""
    return raw if prev is None else prev + ease * (raw - prev)


def apply_tuning_key(key, tuning):
    """Ajusta un knob si la tecla está mapeada. Devuelve True si cambió algo."""
    entry = TUNING_KEYS.get(chr(key)) if 32 <= key < 127 else None
    if entry is None:
        return False
    name, factor = entry
    lo, hi = TUNING_LIMITS[name]
    tuning[name] = min(hi, max(lo, tuning[name] * factor))
    return True


def draw_overlay(frame, tuning, fps, emit_hz):
    lines = [
        f"{fps:4.1f} fps camara   {emit_hz:3.0f} Hz emisor",
        f"[ ]  min_cutoff {tuning['min_cutoff']:6.2f} Hz  suavidad en reposo",
        f"- =  beta       {tuning['beta']:6.4f}     respuesta al barrido",
        f"o p  d_cutoff   {tuning['d_cutoff']:6.2f} Hz  jitter en reposo",
        f", .  ease       {tuning['ease']:6.2f}     suavidad/lag del emisor",
        f"; '  sens       {tuning['sensitivity']:6.2f}",
        "q    salir (imprime los valores)",
    ]
    for i, text in enumerate(lines):
        pos = (8, 20 + 19 * i)
        # Contorno negro y luego verde: legible sobre cualquier fondo de cámara.
        for color, thick in (((0, 0, 0), 3), ((0, 255, 0), 1)):
            cv2.putText(
                frame, text, pos, cv2.FONT_HERSHEY_SIMPLEX, 0.45, color, thick, cv2.LINE_AA
            )


def pick_gesture(active, dists, enter_thr, exit_thr, pending=None, hold=PRESS_HOLD_FRAMES):
    """Un gesto a la vez, con histéresis y confirmación de `hold` frames.

    Sin exclusión mutua, al pinzar el medio (click derecho) el índice lo sigue y
    dispara también el izquierdo. Mientras un gesto está activo ningún otro puede
    empezar; gana el pinch más cerrado de los que cruzan el umbral de entrada.

    `pending` es (gesto, cuenta): el mismo gesto tiene que repetirse `hold` frames
    seguidos para apretar. Solo se debouncea el PRESS; el release sale al primer frame a
    propósito, porque un botón que se queda trabado es peor que uno que se suelta de más.

    Devuelve (nuevo_active, evento, nuevo_pending), con evento None | ("press", g) |
    ("release", g). Función pura: testeable sin cámara ni uinput.
    """
    if active is not None:
        if dists[active] > exit_thr:
            return None, ("release", active), None
        return active, None, None

    candidates = [g for g, d in dists.items() if d < enter_thr]
    if not candidates:
        return None, None, None
    gesture = min(candidates, key=lambda g: dists[g])

    # Cambiar de gesto reinicia la cuenta: dudar entre índice y medio no debe sumar.
    count = pending[1] + 1 if pending and pending[0] == gesture else 1
    if count < hold:
        return None, None, (gesture, count)
    return gesture, ("press", gesture), None


def drag_anchor(x, y, press, offset, break_px):
    """Ancla del cursor mientras un botón está apretado.

    Devuelve (punto, offset). punto None = congelado: el caller no llama a move(), el
    objetivo del emisor queda fijo y el cursor se queda literalmente quieto, que es lo que
    hace que el click aterrice donde se apuntó.

    Pasado break_px el gesto es un arrastre. Devolver `press` en ese primer frame y fijar
    el offset ahí engancha el arrastre al punto congelado: no hay salto, y como `press` es
    el mismo valor que el filtro ya tiene suavizado, su derivada sale ≈0 y tampoco hay
    tirón.
    """
    if offset is not None:
        return (x + offset[0], y + offset[1]), offset
    if math.hypot(x - press[0], y - press[1]) < break_px:
        return None, None
    return press, (press[0] - x, press[1] - y)


def accumulate_scroll(accum, delta_px, gain):
    """Acumula fracciones para no perder movimiento por truncamiento.

    Devuelve (clicks_enteros, resto). int() trunca hacia cero, así que restarle el
    mismo entero deja el residuo simétrico en signo (sin sesgo hacia arriba o abajo).
    """
    accum += delta_px * gain
    clicks = int(accum)
    return clicks, accum - clicks


def detect_screen_size():
    """pyautogui falla en Wayland; hyprctl da la resolución exacta y rápido."""
    try:
        output = subprocess.check_output(["hyprctl", "monitors", "-j"]).decode("utf-8")
        monitors = json.loads(output)
        return monitors[0]["width"], monitors[0]["height"]
    except Exception as e:
        print(f"Error detectando resolución Hyprland, usando fallback: {e}")
        return 1920, 1200


def open_camera(path=None):
    if path:  # --video: reproducir un archivo; sin v4l2-ctl ni cap.set
        return cv2.VideoCapture(path)
    # La cámara viene con exposure_dynamic_framerate=1: con poca luz alarga la
    # exposición y cae a ~12 fps. Apagarlo la deja fija en 30 fps. Esto es LA
    # optimización de rendimiento de este archivo: sin ella el loop va a ~12 fps
    # por más rápido que sea el resto.
    # No usar CAP_PROP_BUFFERSIZE=1: medido, empeora a 14.7 fps en esta cámara.
    try:
        subprocess.run(
            ["v4l2-ctl", "-d", CAMERA_DEVICE, "-c", "exposure_dynamic_framerate=0"],
            check=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"Aviso: no pude fijar el framerate de la cámara ({e}); seguirá a ~12 fps.")

    cap = cv2.VideoCapture(0)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, 30)
    return cap


def main():
    parser = argparse.ArgumentParser(description="Mouse virtual por gestos de mano.")
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Muestra la ventana de cámara (cuesta ms reales; el uso vía Quickshell es headless).",
    )
    parser.add_argument("--video", metavar="PATH", help="Lee de un archivo en vez de la cámara (a 30 fps).")
    parser.add_argument(
        "--trace",
        metavar="PATH",
        help="CSV por frame: frame_idx,detected,anchor_x,anchor_y,hand_span,infer_ms,changed.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="No crea el dispositivo uinput (el puntero real no se mueve); para benchmarks.",
    )
    parser.add_argument(
        "--cpu",
        action="store_true",
        help="Delegate CPU: escape si el delegate GPU falla en esta máquina.",
    )
    args = parser.parse_args()

    # pkill manda SIGTERM y Python muere sin correr el finally -> el device de uinput
    # queda colgado y se van acumulando. Convertirlo en SystemExit lo arregla.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    screen_w, screen_h = detect_screen_size()
    print(f"screen: {screen_w}x{screen_h}")

    cap = open_camera(args.video)
    if not cap.isOpened():
        print("Error: Cámara no detectada.")
        return 1

    landmarker = HandLandmarker.create_from_options(
        HandLandmarkerOptions(
            # Delegate GPU por defecto. Medido (Core Ultra 5 226V, sin mano, % de un core, intercalado):
            # legacy lite 45 %, Tasks CPU full 54 %, Tasks GPU full 24 % (infer p50 10 / p95 14.4 ms).
            # Carga bajo Wayland con EGL_PLATFORM por defecto (con gbm falla). --cpu = escape.
            base_options=BaseOptions(
                model_asset_path=MODEL_PATH,
                delegate=BaseOptions.Delegate.CPU if args.cpu else BaseOptions.Delegate.GPU,
            ),
            # VIDEO = síncrono con tracking entre frames (≈ static_image_mode=False legacy).
            # LIVE_STREAM no: es asíncrono y descarta frames; con la inferencia < 33 ms no gana.
            running_mode=RunningMode.VIDEO,
            num_hands=1,  # = max_num_hands
            min_hand_detection_confidence=0.7,  # = min_detection_confidence (detector de palma)
            # Bajo este umbral se pierde el tracking y vuelve a correr el detector de palma:
            # es el que cumple el rol del min_tracking_confidence legacy.
            min_hand_presence_confidence=0.7,
            min_tracking_confidence=0.7,  # IoU de la caja entre frames para seguir trackeando
        )
    )
    t_start = time.perf_counter()
    last_ts = -1  # detect_for_video exige timestamps (ms) estrictamente crecientes

    mouse = VirtualMouse(
        SCREEN_W=screen_w,
        SCREEN_H=screen_h,
        CAMERA_WIDTH=CAMERA_WIDTH,
        CAMERA_HEIGHT=CAMERA_HEIGHT,
        SENSITIVITY=SENSITIVITY,
        dry_run=args.dry_run,
    )

    tuning = {
        "min_cutoff": mouse.filter_x.min_cutoff,
        "beta": mouse.filter_x.beta,
        "d_cutoff": mouse.filter_x.d_cutoff,
        "ease": mouse.emitter.ease,
        "sensitivity": SENSITIVITY,
    }

    active_gesture = None
    pending_gesture = None  # (gesto, frames) a la espera de confirmar el press
    press_anchor = None  # punto congelado mientras hay un botón apretado
    drag_offset = None  # != None una vez que el gesto se convirtió en arrastre
    span_smooth = None
    scroll_accum = 0.0
    prev_scroll_y = None

    frame_count = 0
    fps, emit_hz = 0.0, 0.0
    fps_t0 = time.perf_counter()
    prev_frame_t = fps_t0

    trace_f = open(args.trace, "w", newline="") if args.trace else None
    trace = csv.writer(trace_f) if trace_f else None
    if trace:
        trace.writerow(["frame_idx", "detected", "anchor_x", "anchor_y", "hand_span", "infer_ms", "changed"])
    frame_idx = 0
    prev_tiny = None
    frames_since_hand = TRACK_GRACE  # arranca fuera de la gracia: sin mano hasta que se vea una
    frames_since_infer = 0
    next_t = time.perf_counter()  # pacing de --video

    try:
        # Loop en serie a propósito. Medido en Core Ultra 5 226V (legacy, CPU): read 8.3 ms +
        # process 25.3 ms = 33.6 ms, o sea 29.8 fps, que es el techo de esta cámara
        # (v4l2-ctl: 30 fps en todos los modos). Un hilo de captura dio x1.00 medido. Con la
        # API Tasks + GPU la inferencia es p50 10 / p95 14.4 ms, aún más holgado.
        # ponytail: si algún día la inferencia pasa de 33 ms, ahí sí conviene solapar con un hilo.
        #
        # CPU medida (sin mano, % de un core, --dry-run, 2026-10): legacy lite 45 % -> Tasks GPU
        # 24 % -> + gate de movimiento 11 %. Ver ~/.cache/virtual_mouse_bench/RESULTS.md.
        while cap.isOpened():
            if args.video:
                # Un archivo no bloquea en read(): sin esto el dt del One Euro y el emisor
                # no serían representativos.
                next_t += 1 / 30
                time.sleep(max(0, next_t - time.perf_counter()))
            ok, frame = cap.read()
            if not ok:
                break

            # dt real, no 1/30 asumido: los fps varían y el cutoff en Hz del filtro
            # One Euro solo significa algo si el dt es el verdadero.
            now = time.perf_counter()
            dt = now - prev_frame_t
            prev_frame_t = now

            frame = cv2.flip(frame, 1)  # espejo: mover la mano a la derecha va a la derecha

            tiny = cv2.resize(frame, (32, 24), interpolation=cv2.INTER_AREA)
            changed = (
                None if prev_tiny is None  # primer frame: siempre infiere, y la columna queda vacía
                else int((cv2.absdiff(tiny, prev_tiny).max(axis=2) > MOTION_PIX_THR).sum())
            )
            prev_tiny = tiny
            frames_since_infer += 1

            hands, infer_ms = None, 0.0
            frames_since_hand += 1
            if changed is None or should_infer(frames_since_hand, changed, frames_since_infer):
                image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)  # cv2 da BGR, MediaPipe quiere RGB
                ts_ms = int((now - t_start) * 1000)
                if ts_ms <= last_ts:
                    ts_ms = last_ts + 1
                last_ts = ts_ms
                t_inf = time.perf_counter()
                hands = landmarker.detect_for_video(
                    Image(image_format=ImageFormat.SRGB, data=image), ts_ms
                ).hand_landmarks
                infer_ms = (time.perf_counter() - t_inf) * 1000
                frames_since_infer = 0
                if hands:
                    frames_since_hand = 0

            if hands:
                lm = hands[0]  # num_hands=1; 21 NormalizedLandmark (.x .y)
                w, h = CAMERA_WIDTH, CAMERA_HEIGHT

                # Escala de la mano: normaliza umbrales y sensibilidad respecto de la
                # distancia a la cámara. Suavizado antes de usarlo para las dos cosas
                # (ver SPAN_EASE): crudo, su ruido entra en la sensibilidad —que se aplica
                # después del filtro— y mueve además la frontera del pinch.
                raw_span = max(get_dist(lm[WRIST], lm[MIDDLE_MCP], w, h), MIN_HAND_SPAN)
                span_smooth = hand_span = smooth_span(span_smooth, raw_span)
                mouse.update_sensitivity(
                    sensitivity_for_span(hand_span, tuning["sensitivity"])
                )

                anchor_x = lm[MIDDLE_MCP].x * w
                anchor_y = lm[MIDDLE_MCP].y * h
                if trace:
                    trace.writerow(
                        [frame_idx, 1, f"{anchor_x:.2f}", f"{anchor_y:.2f}", f"{raw_span:.2f}", f"{infer_ms:.2f}", changed]
                    )

                dists = {
                    "left": get_dist(lm[THUMB_TIP], lm[INDEX_TIP], w, h),
                    "right": get_dist(lm[THUMB_TIP], lm[MIDDLE_TIP], w, h),
                    "scroll": get_dist(lm[THUMB_TIP], lm[RING_TIP], w, h),
                }

                active_gesture, event, pending_gesture = pick_gesture(
                    active_gesture,
                    dists,
                    PINCH_ENTER * hand_span,
                    PINCH_EXIT * hand_span,
                    pending_gesture,
                )

                if event is not None:
                    action, gesture = event
                    if gesture == "scroll":
                        # Al re-engancharse, no arrastrar el delta de la vez anterior.
                        prev_scroll_y, scroll_accum = None, 0.0
                    else:
                        mouse.click(gesture, 1 if action == "press" else 0)
                        # Congelar desde acá hasta el release (o hasta que rompa el
                        # umbral y pase a arrastre).
                        press_anchor = (anchor_x, anchor_y) if action == "press" else None
                        drag_offset = None

                if active_gesture == "scroll":
                    if prev_scroll_y is None:
                        prev_scroll_y = anchor_y
                    # anchor_y crece hacia abajo en la imagen: mano arriba -> delta > 0
                    # -> REL_WHEEL positivo -> scroll hacia arriba.
                    delta = prev_scroll_y - anchor_y
                    prev_scroll_y = anchor_y
                    clicks, scroll_accum = accumulate_scroll(
                        scroll_accum, delta, SCROLL_GAIN
                    )
                    mouse.scroll(-clicks if SCROLL_INVERT else clicks)
                elif press_anchor is not None:
                    point, drag_offset = drag_anchor(
                        anchor_x,
                        anchor_y,
                        press_anchor,
                        drag_offset,
                        DRAG_BREAK * hand_span,
                    )
                    # point None = congelado: no llamar a move() deja el objetivo del
                    # emisor fijo, el lerp converge exacto y su dedup deja de escribir.
                    if point is not None:
                        mouse.move(point[0], point[1], dt)
                else:
                    # Durante el scroll la mano se mueve en vertical a propósito: mover
                    # el cursor a la vez sería un bug.
                    mouse.move(anchor_x, anchor_y, dt)
            else:
                if trace:
                    trace.writerow([frame_idx, 0, "", "", "", f"{infer_ms:.2f}", changed])
                mouse.reset_smoothing()  # no arrastrar velocidad vieja al reaparecer
                # El span también: al reaparecer la mano puede estar a otra distancia, y
                # barrer hasta ella con el EMA daría sensibilidad equivocada unos frames.
                span_smooth, pending_gesture = None, None
                if active_gesture is not None:
                    # La mano salió de cuadro: soltar el botón apretado (si no, queda
                    # trabado para siempre) y resetear el scroll (si no, al volver la
                    # mano arrastra el delta de la posición anterior de un golpe).
                    if active_gesture in ("left", "right"):
                        mouse.click(active_gesture, 0)
                    active_gesture, prev_scroll_y, scroll_accum = None, None, 0.0
                    press_anchor, drag_offset = None, None

            frame_idx += 1
            frame_count += 1
            elapsed = time.perf_counter() - fps_t0
            if elapsed >= FPS_REPORT_EVERY:
                fps = frame_count / elapsed
                emit_hz = mouse.emitter.pop_ticks() / elapsed
                print(f"{fps:.1f} fps cámara | {emit_hz:.0f} Hz emisor", file=sys.stderr)
                frame_count, fps_t0 = 0, time.perf_counter()

            if args.preview:
                draw_overlay(frame, tuning, fps, emit_hz)
                cv2.imshow("AI Mouse", frame)
                key = cv2.waitKey(1) & 0xFF
                if key == ord("q"):
                    break
                if apply_tuning_key(key, tuning):
                    mouse.filter_x.min_cutoff = tuning["min_cutoff"]
                    mouse.filter_y.min_cutoff = tuning["min_cutoff"]
                    mouse.filter_x.beta = tuning["beta"]
                    mouse.filter_y.beta = tuning["beta"]
                    mouse.filter_x.d_cutoff = tuning["d_cutoff"]
                    mouse.filter_y.d_cutoff = tuning["d_cutoff"]
                    mouse.emitter.ease = tuning["ease"]
    except KeyboardInterrupt:
        pass
    finally:
        if trace_f:
            trace_f.close()
        cap.release()
        landmarker.close()
        mouse.close()
        if args.preview:
            cv2.destroyAllWindows()
            # El ajuste solo se encuentra a sentimiento: imprimirlo es lo que evita
            # que se pierda al cerrar la ventana.
            print("\n# valores ajustados:")
            print(f"main.py:        SENSITIVITY = {tuning['sensitivity']:.2f}")
            print(f"VirtualMouse.py: MIN_CUTOFF = {tuning['min_cutoff']:.2f}")
            print(f"VirtualMouse.py: BETA       = {tuning['beta']:.4f}")
            print(f"VirtualMouse.py: D_CUTOFF   = {tuning['d_cutoff']:.2f}")
            print(f"VirtualMouse.py: EMIT_EASE  = {tuning['ease']:.2f}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
