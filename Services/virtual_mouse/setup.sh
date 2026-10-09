#!/bin/sh
# Crea/actualiza el venv del mouse virtual y baja el modelo. Idempotente.
#   ./setup.sh            (usa python3.15; PYTHON=python3.x ./setup.sh para otro)
set -e
cd "$(dirname "$0")"
PY=${PYTHON:-python3.15}
[ -x venv/bin/python ] || "$PY" -m venv venv
venv/bin/python -m pip install -q --upgrade pip
venv/bin/python -m pip install -q -r requirements.txt
# Modelo full float16 oficial de MediaPipe Tasks (no viene en el wheel).
[ -f hand_landmarker.task ] || curl -fL -o hand_landmarker.task \
  https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
venv/bin/python -c "import mediapipe, cv2, evdev; print('ok mediapipe', mediapipe.__version__, 'opencv', cv2.__version__)"
