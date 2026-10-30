#!/bin/bash
# Abre Playa Limpia en la ventana del agente (log en /tmp/opencode/game.log).
# Vive en el repo a propósito: /tmp/opencode se borra y el lanzador se perdía.
GODOT=/home/ada/.local/bin/godot
cd "$(dirname "$0")/.." || exit 1
mkdir -p /tmp/opencode
echo "=== arranque $(date -Is) ===" >> /tmp/opencode/game.log
exec "$GODOT" --path . 2>&1 | tee -a /tmp/opencode/game.log
