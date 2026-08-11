#!/usr/bin/env bash
set -euo pipefail

# Ecualizador paramétrico de 10 bandas sobre el sink de salida.
#
# El EQ NO es un módulo ni un nodo propio: es un filter-graph colgado del nodo del sink de
# hardware con la propiedad `audioconvert.filter-graph.0`. Desde PipeWire 1.4 audioconvert
# admite hasta 8 filter-graphs intercambiables EN CALIENTE dentro de cualquier nodo, así que
# cambiar las ganancias no toca el grafo de audio: no nacen ni mueren nodos, nadie se
# re-rutea, y las aplicaciones ni se enteran.
#
# Antes esto se montaba con libpipewire-module-parametric-equalizer declarado en un drop-in de
# pipewire.conf.d, lo que obligaba a `systemctl --user restart pipewire pipewire-pulse` en cada
# cambio de ganancia — context.modules solo se lee al arrancar el daemon. Ese reinicio mataba
# el grafo entero; en particular tumbaba la conexión de Spotify con pipewire-pulse, que al ser
# cliente Pulse no se reconecta solo y había que reiniciarlo a mano para recuperar sus nodos.
#
# Detalles del mecanismo que se pagaron con pruebas y no son evidentes:
#   - La propiedad es de solo escritura: leerla siempre devuelve "". No se puede consultar si
#     el grafo está puesto, así que aquí NUNCA se detecta — se re-aplica y punto (es idempotente).
#   - Un sink SUSPENDIDO ignora el set en silencio. Solo lo acepta mientras está `running`,
#     o sea con audio de verdad pasando. Por eso existe `recover`: el QML lo dispara cuando el
#     sink por defecto cambia o cuando le aparecen links.
#   - El valor es spa-json dentro de una cadena, así que las comillas interiores hay que
#     escaparlas. Con un solo nodo no hacen falta links (y los puertos de param_eq no se llaman
#     In/Out, así que intentar enlazarlo rompe el grafo entero en silencio).

HOME_DIR="${HOME}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
QS_DIR="${QUICKSHELL_CONFIG_DIR:-$CONFIG_DIR/quickshell}"
EQ_DIR="$QS_DIR/eq"
EQ_FILE="$EQ_DIR/parametric-eq.txt"
STATE_DIR="${XDG_STATE_HOME:-$HOME_DIR/.local/state}/quickshell"
STATE_FILE="$STATE_DIR/eq_filter_chain.state"

# Ranura de filter-graph. Hay 8 (0..7); la 0 es la nuestra. Usar una fija es lo que permite
# reemplazar el EQ sin apilar copias.
EQ_SLOT="audioconvert.filter-graph.0"

mkdir -p "$EQ_DIR" "$STATE_DIR"

FREQS=(31 63 125 250 500 1000 2000 4000 8000 16000)

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

check_deps() {
  local deps=(pactl pw-cli awk grep head sed)
  for c in "${deps[@]}"; do
    need_cmd "$c"
  done
}

read_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

# Solo hace falta recordar en qué sink quedó colgado el grafo, para poder limpiarlo al cambiar
# de salida. El volumen ya no se guarda: es el del sink de hardware, que gestiona PipeWire.
write_state() {
  cat > "$STATE_FILE" <<STATE
BASE_SINK=${BASE_SINK:-}
EQ_ENABLED=${EQ_ENABLED:-1}
STATE
}

default_sink() {
  pactl info | awk -F': ' '/^Default Sink:/ {print $2; exit}'
}

node_id_by_name() {
  local type="$1"
  local name="$2"
  pw-cli ls "$type" | awk -v want="$name" '
    /^	id / {gsub(",","",$2); id=$2}
    /node.name = "/ {
      line=$0
      sub(/^.*node.name = "/,"",line)
      sub(/".*$/,"",line)
      if (line == want && id != "") { print id; exit }
    }
  '
}

sink_exists() {
  pactl list short sinks | awk '{print $2}' | grep -Fxq "$1"
}

first_real_sink() {
  pactl list short sinks | awk '{print $2}' | head -n1
}

running_real_sink() {
  pactl list short sinks | awk '$5 == "RUNNING" {print $2}' | head -n1
}

pick_best_sink() {
  local cur_sink="${1:-}"
  local remembered_sink="${2:-}"
  local running_sink=""
  if [[ -n "$cur_sink" ]] && sink_exists "$cur_sink"; then
    echo "$cur_sink"
    return
  fi
  if [[ -n "$remembered_sink" ]] && sink_exists "$remembered_sink"; then
    echo "$remembered_sink"
    return
  fi
  running_sink="$(running_real_sink || true)"
  if [[ -n "$running_sink" ]] && sink_exists "$running_sink"; then
    echo "$running_sink"
    return
  fi
  first_real_sink || true
}

ensure_gains() {
  if [[ "$#" -ne 10 ]]; then
    echo "Expected 10 gains, got $#" >&2
    exit 1
  fi

  local out=()
  for g in "$@"; do
    if [[ "$g" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
      out+=("$g")
    else
      out+=("0")
    fi
  done
  printf '%s\n' "${out[@]}"
}

# Formato AutoEQ/ParametricEQ. Sigue siendo la fuente de la verdad de las ganancias: lo lee
# `param_eq` al cargar el grafo, y el QML lo relee para hidratar los sliders al arrancar.
write_eq_file() {
  local gains=("$@")
  {
    echo "Preamp: 0 dB"
    for i in "${!FREQS[@]}"; do
      local idx=$((i + 1))
      echo "Filter ${idx}: ON PK Fc ${FREQS[$i]} Hz Gain ${gains[$i]} dB Q 1.000"
    done
  } > "$EQ_FILE"
}

eq_graph() {
  printf '{ nodes = [ { type = builtin name = eq label = param_eq config = { filename = %s } } ] }' "$EQ_FILE"
}

# $1 = node.name del sink, $2 = grafo ("" para quitarlo).
set_graph() {
  local sink="${1:-}" graph="${2:-}" id=""
  [[ -n "$sink" ]] || return 0
  id="$(node_id_by_name Node "$sink" || true)"
  if [[ -z "$id" ]]; then
    echo "Sink not found in the PipeWire graph: $sink" >&2
    return 1
  fi
  pw-cli s "$id" Props "{ params = [ \"$EQ_SLOT\" \"$graph\" ] }" >/dev/null
}

# param_eq lee el archivo AL CARGAR el grafo, así que para que unas ganancias nuevas surtan
# efecto hay que reemplazar el grafo, no solo reescribir el archivo. Se limpia antes de poner:
# no está documentado si audioconvert deduplica cuando el string entrante es idéntico, y dos
# llamadas de pw-cli cuestan milisegundos.
install_graph() {
  local sink="${1:-}"
  [[ -n "$sink" ]] || return 0
  set_graph "$sink" ""
  set_graph "$sink" "$(eq_graph)"
}

apply_eq() {
  local target_sink="${1:-auto}"
  shift
  local gains=("$@")

  read_state
  local cur_sink previous_sink
  cur_sink="$(default_sink || true)"
  previous_sink="${BASE_SINK:-}"

  if [[ "$target_sink" != "auto" ]]; then
    if ! sink_exists "$target_sink"; then
      echo "Requested sink not found: $target_sink" >&2
      exit 1
    fi
    BASE_SINK="$target_sink"
  else
    BASE_SINK="$(pick_best_sink "$cur_sink" "${BASE_SINK:-}")"
  fi

  write_eq_file "${gains[@]}"
  EQ_ENABLED=1
  write_state

  # Si el EQ estaba colgado de otro sink, dejarlo limpio: si no, el grafo viejo se queda ahí
  # y esa salida sigue ecualizada a espaldas del usuario.
  if [[ -n "$previous_sink" && "$previous_sink" != "${BASE_SINK}" ]]; then
    set_graph "$previous_sink" "" || true
  fi

  install_graph "$BASE_SINK"
  echo "applied file=$EQ_FILE sink=$BASE_SINK"
}

switch_eq_target() {
  local target_sink="${1:-}"

  read_state

  if [[ -z "$target_sink" ]]; then
    echo "Usage: $0 switch <target_sink>" >&2
    exit 2
  fi
  if ! sink_exists "$target_sink"; then
    echo "Requested sink not found: $target_sink" >&2
    exit 1
  fi

  if [[ -n "${BASE_SINK:-}" && "$BASE_SINK" != "$target_sink" ]]; then
    set_graph "$BASE_SINK" "" || true
  fi

  BASE_SINK="$target_sink"
  write_state

  if [[ "${EQ_ENABLED:-1}" == "1" ]]; then
    install_graph "$BASE_SINK"
  fi
  echo "switched target=$BASE_SINK"
}

disable_eq() {
  read_state
  local sink="${BASE_SINK:-}"
  [[ -n "$sink" ]] || sink="$(default_sink || true)"

  [[ -n "$sink" ]] && { set_graph "$sink" "" || true; }
  EQ_ENABLED=0
  write_state
  echo "disabled"
}

# Re-aplica el grafo al sink por defecto actual. Lo llama el QML cuando cambia el sink o
# cuando le aparecen links, que es el momento en que pasa de `suspended` a `running` y por
# fin acepta el filter-graph.
recover_eq() {
  read_state
  if [[ "${EQ_ENABLED:-1}" != "1" ]]; then
    echo "recovered (disabled)"
    return 0
  fi

  local sink
  sink="$(pick_best_sink "$(default_sink || true)" "${BASE_SINK:-}")"
  [[ -n "$sink" ]] || { echo "recovered (no sink)"; return 0; }

  if [[ -n "${BASE_SINK:-}" && "$BASE_SINK" != "$sink" ]]; then
    set_graph "$BASE_SINK" "" || true
  fi

  BASE_SINK="$sink"
  write_state
  install_graph "$sink"
  echo "recovered sink=$sink"
}

status_eq() {
  read_state
  echo "qs_dir=$QS_DIR"
  echo "eq_file=$EQ_FILE"
  echo "eq_slot=$EQ_SLOT"
  echo "base_sink=${BASE_SINK:-}"
  echo "eq_enabled=${EQ_ENABLED:-1}"
  echo "default_sink=$(default_sink || true)"
}

cmd="${1:-status}"
shift || true

check_deps

case "$cmd" in
  apply)
    if [[ "$#" -lt 10 ]]; then
      echo "Usage: $0 apply <10 gains> [target_sink|auto]" >&2
      exit 2
    fi
    target_sink="${11:-auto}"
    mapfile -t gains < <(ensure_gains "${@:1:10}")
    apply_eq "$target_sink" "${gains[@]}"
    ;;
  switch)
    switch_eq_target "${1:-}"
    ;;
  disable)
    disable_eq
    ;;
  recover)
    recover_eq
    ;;
  status)
    status_eq
    ;;
  *)
    echo "Usage: $0 {apply <10 gains> [target_sink|auto]|switch <target_sink>|disable|recover|status}" >&2
    exit 2
    ;;
esac
