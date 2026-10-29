#!/usr/bin/env bash
# Vista previa del personaje sin abrir el juego (~3 s).
#   tools/ver-char.sh [salida.png] [--npc] [--side]
OUT="${1:-/tmp/char-preview.png}"
shift 2>/dev/null || true
cd "$(dirname "$0")/.." || exit 1
xvfb-run -a -s "-screen 0 640x640x24" godot --path . scenes/CharPreview.tscn \
  --resolution 640x640 -- --out="$OUT" "$@" 2>&1 | grep -E "preview ->|SCRIPT ERROR" || true
