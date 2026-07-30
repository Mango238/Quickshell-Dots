#!/usr/bin/env python3
"""Renderiza fórmulas LaTeX a PNG transparentes para el preview del editor.

Lo llama Services/MathRender.qml con un único argumento JSON:

    {"dir": ..., "color": "#rrggbb", "size": 24, "dpi": 110,
     "jobs": [{"key": "<hash>", "tex": "...", "path": "..."}, ...]}

Imprime una línea por fórmula: "OK <key> <ancho> <alto>" o "FAIL <key>".

El motor es LaTeX de verdad (latex + dvipng), así que entiende mhchem (\\ce),
\\boxed, \\cancel y el resto de lo que aparece en notas exportadas de pandoc.
Sin texlive instalado no imprime ningún OK y el preview deja las fórmulas como
texto plano.

Todas las fórmulas pendientes van en UN documento, una por página: arrancar
LaTeX es lo caro, no componer cada fórmula. Si el lote sale incompleto —una
fórmula con error de sintaxis puede arruinar su página— se reintenta una por
una, para que un error no se lleve puestas las fórmulas buenas de la nota.
"""

import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

PREAMBLE = r"""\documentclass{article}
\usepackage[T1]{fontenc}
\usepackage[utf8]{inputenc}
\usepackage{amsmath}
\usepackage{amssymb}
\IfFileExists{mhchem.sty}{\usepackage[version=4]{mhchem}}{\providecommand{\ce}[1]{\mathrm{#1}}}
\IfFileExists{cancel.sty}{\usepackage{cancel}}{\providecommand{\cancel}[1]{#1}}
\pagestyle{empty}
\begin{document}
\fontsize{%(size)d}{%(leading)d}\selectfont
"""


def prepare(tex):
    # Un salto de línea no significa nada dentro de matemática, pero una línea
    # en blanco sí: corta el párrafo y rompe el $$...$$. Se aplanan todos.
    return re.sub(r"\s*\n\s*", " ", tex).strip()


def dims(path):
    """Ancho y alto desde la cabecera PNG, sin depender de Pillow."""
    with open(path, "rb") as f:
        return struct.unpack(">II", f.read(24)[16:24])


def fg(color):
    """'#rrggbb' al 'rgb R G B' que espera dvipng."""
    c = color.lstrip("#")
    r, g, b = (int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return "rgb %.3f %.3f %.3f" % (r, g, b)


def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, timeout=120).returncode


def batch(texs, cfg, workdir):
    """Compone `texs` (una por página) y devuelve {índice: ruta del PNG}."""
    doc = PREAMBLE % {"size": cfg["size"], "leading": int(cfg["size"] * 1.2)}
    doc += "\\newpage\n".join("\\[%s\\]\n" % prepare(t) for t in texs)
    doc += r"\end{document}" + "\n"
    with open(os.path.join(workdir, "f.tex"), "w", encoding="utf-8") as f:
        f.write(doc)

    # nonstopmode y sin -halt-on-error: una fórmula rota no debe abortar el lote.
    run(["latex", "-interaction=nonstopmode", "-no-shell-escape", "f.tex"], workdir)
    if not os.path.exists(os.path.join(workdir, "f.dvi")):
        return {}

    run(["dvipng", "-T", "tight", "-bg", "Transparent", "-fg", fg(cfg["color"]),
         "-D", str(cfg["dpi"]), "-q", "-o", "p%d.png", "f.dvi"], workdir)

    out = {}
    for i in range(len(texs)):
        p = os.path.join(workdir, "p%d.png" % (i + 1))
        if os.path.exists(p):
            out[i] = p
    return out


def main():
    cfg = json.loads(sys.argv[1])
    os.makedirs(cfg["dir"], exist_ok=True)

    pending = []
    for job in cfg["jobs"]:
        if os.path.exists(job["path"]):
            try:
                w, h = dims(job["path"])
                print("OK %s %d %d" % (job["key"], w, h))
                continue
            except Exception:
                pass          # PNG truncado de una corrida anterior: rehacerlo
        pending.append(job)

    if not pending:
        return 0

    if not shutil.which("latex") or not shutil.which("dvipng"):
        sys.stderr.write("falta latex o dvipng (texlive-mathscience, texlive-binextra)\n")
        for job in pending:
            print("FAIL %s" % job["key"])
        return 1

    workdir = tempfile.mkdtemp(prefix="qs-math-")
    try:
        done = batch([j["tex"] for j in pending], cfg, workdir)

        # Lote incompleto: se reintenta lo que falta de a una, así el error de
        # una fórmula no se lleva puestas las demás.
        if len(done) != len(pending):
            for i, job in enumerate(pending):
                if i in done:
                    continue
                sub = tempfile.mkdtemp(prefix="qs-math-1-", dir=workdir)
                one = batch([job["tex"]], cfg, sub)
                if 0 in one:
                    done[i] = one[0]

        for i, job in enumerate(pending):
            src = done.get(i)
            if not src:
                sys.stderr.write("%s: latex no produjo salida\n" % job["tex"][:60])
                print("FAIL %s" % job["key"])
                continue
            shutil.move(src, job["path"])
            w, h = dims(job["path"])
            print("OK %s %d %d" % (job["key"], w, h))
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
