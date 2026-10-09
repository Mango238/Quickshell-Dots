import math
import threading
import time

from evdev import UInput, ecodes, AbsInfo

# --- Filtro One Euro (Casiez, Roussel & Vogel, CHI 2012). Knobs con sentido físico:
# Medido extremo a extremo (filtro + emisor + map_to_screen, ruido de landmark σ=1.5 px,
# secuencia pareada entre candidatos). El lag se mide a 100 px/s, que es el régimen de
# apuntado fino; a velocidad de barrido el término beta lo deja en ~0 en todos los casos.
#
#     min_cutoff/beta/d_cutoff    jitter reposo    lag apuntado
#     1.2 / 0.02 / 1.0  (antes)       9.5 px          23.3 px
#     0.6 / 0.04 / 0.25 (ahora)       6.4 px          19.0 px
#
# O sea: NO es un trade-off, el punto viejo estaba adentro de la frontera de Pareto.
MIN_CUTOFF = 0.6  # Hz. Suavidad en reposo: más bajo = más suave (y más pegajoso al arrancar).
BETA = 0.04  # Cuánto se abre el filtro con la velocidad: más alto = menos lag al barrer.

# Hz. Cutoff del filtro de la derivada. El paper usa 1.0, pero con el ruido de landmarks
# de esta cámara esa velocidad falsa abre el cutoff adaptativo justo en reposo, que es
# cuando no querés que se abra. Es el knob que más jitter saca sin costar respuesta.
D_CUTOFF = 0.25

# --- Emisor. La cámara entrega 30 fps y la pantalla refresca a 60: emitir un evento
# por frame de cámara hace que el puntero salte 75-90 px de golpe y solo se actualice
# en uno de cada dos vsyncs. Ningún filtro arregla eso; hay que emitir más seguido.
EMIT_RATE = 120.0  # Hz de eventos ABS
EMIT_EASE = 0.35  # lerp por tick hacia el objetivo (~24 ms de constante a 120 Hz)


def _lowpass_alpha(cutoff, dt):
    """Alpha de un low-pass de primer orden para un cutoff en Hz y un paso dt en s."""
    tau = 1.0 / (2.0 * math.pi * cutoff)
    return 1.0 / (1.0 + tau / dt)


def map_to_screen(nx, ny, sensitivity, screen_w, screen_h):
    """(nx, ny) normalizados [0,1] del frame -> píxeles absolutos de pantalla.

    Restamos 0.5 antes de escalar para que el "zoom" del área activa ocurra desde el
    centro del frame y no desde la esquina. Clamp a [0,1] para no salirse de pantalla.
    Con sensibilidad 2.2 el área activa es el 45% central del frame (291 de 640 px).
    """
    sx = min(1.0, max(0.0, (nx - 0.5) * sensitivity + 0.5))
    sy = min(1.0, max(0.0, (ny - 0.5) * sensitivity + 0.5))
    return sx * screen_w, sy * screen_h


class OneEuroFilter:
    """Filtro 1€ sobre un eje.

    La diferencia clave frente a un EMA de alpha adaptativo: la estimación de
    velocidad se filtra ANTES de usarla para fijar el cutoff. Derivándola de un solo
    frame (como hacía la versión anterior) la *fuerza del suavizado tiembla* junto con
    el ruido del landmark, y eso es exactamente lo que se siente áspero.
    """

    def __init__(self, min_cutoff=MIN_CUTOFF, beta=BETA, d_cutoff=D_CUTOFF):
        self.min_cutoff = min_cutoff
        self.beta = beta
        self.d_cutoff = d_cutoff
        self.x_prev = None
        self.x_smooth = 0.0
        self.dx_smooth = 0.0

    def reset(self):
        """La mano volvió a entrar en cuadro: no arrastrar velocidad vieja."""
        self.x_prev = None
        self.dx_smooth = 0.0

    def __call__(self, x, dt):
        if self.x_prev is None or dt <= 0.0:
            self.x_prev = self.x_smooth = x
            self.dx_smooth = 0.0
            return x

        # Derivada cruda -> low-pass fijo. Este suavizado de la velocidad es el que
        # evita que el cutoff (y por lo tanto el suavizado) oscile con el ruido.
        dx = (x - self.x_prev) / dt
        self.dx_smooth += _lowpass_alpha(self.d_cutoff, dt) * (dx - self.dx_smooth)

        # Cutoff adaptativo: quieto -> min_cutoff (suave); rápido -> se abre (sin lag).
        cutoff = self.min_cutoff + self.beta * abs(self.dx_smooth)
        self.x_smooth += _lowpass_alpha(cutoff, dt) * (x - self.x_smooth)

        self.x_prev = x
        return self.x_smooth


class CursorEmitter:
    """Escribe ABS_X/ABS_Y a EMIT_RATE Hz interpolando hacia el último objetivo.

    Desacopla la tasa de salida de los 30 fps de la cámara: convierte los saltos de
    75-90 px por frame en pasos de ~19 px y garantiza una posición fresca en cada
    refresco de 60 Hz de la pantalla.
    """

    def __init__(self, ui, rate=EMIT_RATE, ease=EMIT_EASE):
        self.ui = ui
        self.period = 1.0 / rate
        self.ease = ease
        self.cond = threading.Condition()
        self.target = None  # None mientras no hubo ninguna mano
        self.pos = None  # posición actual interpolada, float
        self.last_sent = None  # último (int, int) escrito
        self.ticks = 0
        self.running = True
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()

    def set_target(self, x, y):
        with self.cond:
            self.target = (x, y)
            self.cond.notify()

    def _idle(self):
        """Nada que emitir: sin objetivo, o ya convergido. Llamar bajo self.cond."""
        return self.target is None or self.pos == self.target

    def pop_ticks(self):
        """Ticks desde la última consulta. Diagnóstico: prueba que los Hz son reales (0 en reposo: el hilo duerme)."""
        n, self.ticks = self.ticks, 0
        return n

    def _tick(self):
        """Un paso de interpolación. Devuelve (x, y) enteros a escribir, o None."""
        with self.cond:
            target = self.target
        if target is None:
            return None

        if self.pos is None:
            self.pos = target  # primer objetivo: aparecer ahí, no barrer desde (0,0)
        else:
            dx, dy = target[0] - self.pos[0], target[1] - self.pos[1]
            if abs(dx) < 0.01 and abs(dy) < 0.01:
                # snap: < 0.01 px es imperceptible, y sin él el lerp nunca iguala a target
                # y el hilo no podría dormir.
                self.pos = target
            else:
                self.pos = (self.pos[0] + self.ease * dx, self.pos[1] + self.ease * dy)

        out = (int(self.pos[0]), int(self.pos[1]))
        if out == self.last_sent:
            return None  # a 120 Hz reenviar la misma posición entera es puro desperdicio
        self.last_sent = out
        return out

    def _loop(self):
        next_tick = time.perf_counter()
        while self.running:
            with self.cond:
                # _idle() y wait() bajo el mismo lock: set_target no puede colarse en medio.
                if self._idle() and self.running:
                    self.cond.wait()
                    next_tick = time.perf_counter()  # no pagar la deuda del sueño
                    continue
            out = self._tick()
            if out is not None:
                self.ui.write(ecodes.EV_ABS, ecodes.ABS_X, out[0])
                self.ui.write(ecodes.EV_ABS, ecodes.ABS_Y, out[1])
                self.ui.syn()
            self.ticks += 1

            next_tick += self.period
            delay = next_tick - time.perf_counter()
            if delay > 0:
                time.sleep(delay)
            else:
                next_tick = time.perf_counter()  # nos atrasamos: no acumular deuda

    def stop(self):
        with self.cond:
            self.running = False
            self.cond.notify()
        self.thread.join(timeout=1.0)


class _NullUInput:
    """UInput que no hace nada (--dry-run)."""

    def write(self, *a):
        pass

    def syn(self):
        pass

    def close(self):
        pass


class VirtualMouse:
    def __init__(
        self,
        SCREEN_W: int,
        SCREEN_H: int,
        CAMERA_WIDTH: int,
        CAMERA_HEIGHT: int,
        SENSITIVITY: float,
        dry_run: bool = False,
    ):
        self.SCREEN_W = SCREEN_W
        self.SCREEN_H = SCREEN_H
        self.CAMERA_WIDTH = CAMERA_WIDTH
        self.CAMERA_HEIGHT = CAMERA_HEIGHT
        self.SENSITIVITY = SENSITIVITY

        # Capacidades del dispositivo virtual. ABS_X/ABS_Y porque posicionamos en
        # absoluto (la mano mapea a una zona de la pantalla), no en relativo.
        cap = {
            ecodes.EV_KEY: [ecodes.BTN_LEFT, ecodes.BTN_RIGHT, ecodes.BTN_MIDDLE],
            ecodes.EV_REL: [ecodes.REL_WHEEL],
            ecodes.EV_ABS: [
                (
                    ecodes.ABS_X,
                    AbsInfo(value=0, min=0, max=SCREEN_W, fuzz=0, flat=0, resolution=0),
                ),
                (
                    ecodes.ABS_Y,
                    AbsInfo(value=0, min=0, max=SCREEN_H, fuzz=0, flat=0, resolution=0),
                ),
            ],
        }
        # dry_run: el bench excluye las escrituras a uinput (microsegundos por evento);
        # el CursorEmitter sigue corriendo igual.
        self.ui = _NullUInput() if dry_run else UInput(cap, name="Python-AI-Mouse", version=0x1)

        self.filter_x = OneEuroFilter()
        self.filter_y = OneEuroFilter()
        self.emitter = CursorEmitter(self.ui)

    def update_sensitivity(self, value: float):
        self.SENSITIVITY = value

    def reset_smoothing(self):
        self.filter_x.reset()
        self.filter_y.reset()

    def move(self, finger_x, finger_y, dt):
        # Se filtra en px de CÁMARA, antes de amplificar. La sensibilidad es dinámica
        # (depende de la distancia de la mano), así que filtrar en px de pantalla haría
        # que el comportamiento del filtro dependiera de esa distancia; en px de cámara
        # los knobs quedan en px/s y son estables.
        fx = self.filter_x(finger_x, dt)
        fy = self.filter_y(finger_y, dt)

        target_x, target_y = map_to_screen(
            fx / self.CAMERA_WIDTH,
            fy / self.CAMERA_HEIGHT,
            self.SENSITIVITY,
            self.SCREEN_W,
            self.SCREEN_H,
        )
        # No se escribe acá: el emisor interpola hacia este objetivo a 120 Hz.
        self.emitter.set_target(target_x, target_y)

    def click(self, button, state):
        if button == "left":
            btn = ecodes.BTN_LEFT
        elif button == "right":
            btn = ecodes.BTN_RIGHT
        else:
            return

        self.ui.write(ecodes.EV_KEY, btn, state)
        self.ui.syn()

    def scroll(self, clicks: int):
        """clicks ya viene entero y acumulado por el caller (ver accumulate_scroll)."""
        if not clicks:
            return
        self.ui.write(ecodes.EV_REL, ecodes.REL_WHEEL, clicks)
        self.ui.syn()

    def close(self):
        self.emitter.stop()  # antes de ui.close(): el hilo escribe sobre self.ui
        self.ui.close()
