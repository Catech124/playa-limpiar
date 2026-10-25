# Playa Limpia — prototipo 3D (Godot)

Prototipo jugable de **recolección de basura en una playa** con la estructura de
mecánicas de *Overcooked 2*: cooperación forzada, pedidos con reloj, estaciones
separadas y bolsas sucias que hay que lavar.

Hecho en **Godot 4.7**, en **3D** y con cámara fija en ángulo como Overcooked.
Sin assets: todo es geometría primitiva, color y luces.

![captura](docs/captura.png)

## Requisitos

- **Godot 4.7** (probado con 4.7.2). Versiones 4.4+ deberían funcionar.
- Si no lo tenés: descargá el binario de
  [godotengine.org/download](https://godotengine.org/download) y descomprimilo.

## Jugar

```bash
godot --path .            # abre y corre el juego
```

O abrí `project.godot` desde el editor de Godot y presioná F5.

## Controles

| | Jugador 1 | Jugador 2 |
|---|---|---|
| Mover | `W A S D` | flechas |
| Acción | `ESPACIO` | `ENTER` |
| Impulso | `SHIFT` | `CTRL` |
| Lanzar | `E` | `.` |

`P` / `ESC` pausa · `R` reinicia · en el menú, `2` arranca co-op local y `D` abre
la caja de arena (sin reloj ni gaviotas).

## Cómo se juega

1. **Recogé** residuos de los montones (PET, latas, vidrio).
2. **Clasificá** en la mesa: mantené la acción 1,2 s.
3. **Cargá la bolsa**: dejá la bolsa en un mostrador y metele los residuos
   clasificados (capacidad 4).
4. **Entregá** la bolsa en el camión. Sólo vale si coincide exactamente con un pedido.
5. **Lavá**: cada entrega deja una bolsa sucia. Las bolsas son **finitas (5)**:
   si no lavás, te quedás sin bolsas.

## Estructura

```
project.godot          configuración (escena principal, renderer, ventana)
scenes/Main.tscn       escena raíz mínima: todo se construye por código
scripts/config.gd      TODOS los números del juego (tuning)
scripts/levels.gd      mapa en texto + props + segundos del sandbox
scripts/grid_world.gd  mapa de texto -> geometría 3D y semántica de celdas
scripts/cell_data.gd   una celda: tipo, estación, ítem
scripts/carry_item.gd  residuo / bolsa (datos)
scripts/item_visuals.gd geometría de los ítems
scripts/player.gd      movimiento, colisión, acción contextual, canales de trabajo
scripts/main.gd        reglas: fuentes, buffers, validación, entrega, estados
scripts/orders.gd      pedidos, paciencia, propina por rapidez
scripts/gulls.gd       gaviotas (el "ratón" de Overcooked)
scripts/hud.gd         HUD y pantallas, dibujados a mano
tests/headless_test.gd 24 comprobaciones de reglas (headless)
tests/shot.gd          capturas automáticas para verificación visual
DESIGN.md              ingeniería inversa de mecánicas + mapeo + números + roadmap
```

## Tests

**Reglas (sin ventana):**

```bash
godot --headless --path . -- --test
```

Corre 24 comprobaciones sobre las mismas funciones que usa el input real
(`player_use`, `player_channel`, `throw_item`): recoger, clasificar, fusionar en
la bolsa, entregar, rechazar, lavar, lanzar, expirar pedidos, fin de ronda y
reinicio. Sale con código 0 si todo pasa.

**Capturas (necesita display; funciona con Xvfb):**

```bash
xvfb-run -a godot --path . -- --shot=/tmp/pl.png --demo
```

Modos: `--demo`, `--demo2` (co-op), `--menu`, `--results`.

## Estado

v0.1 — prototipo de mecánicas en 3D. Lo implementado, lo que falta, las
decisiones y las preguntas abiertas están en [DESIGN.md](DESIGN.md).
