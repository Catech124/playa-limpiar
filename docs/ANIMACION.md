# Animación del personaje

No hay esqueleto ni animaciones importadas: el GLB trae **bisagras** (nodos
vacíos) y Godot las rota por código. Es lo más barato que se ve bien en un
prototipo y no ata el asset a un rig que después haya que rehacer.

## Bisagras que exporta `tools/gen_chef.py`

| Nodo | Pivote | Qué mueve |
|---|---|---|
| `arm_l` / `arm_r` | hombro `(±0.075, 0, 0.50)` | manga + brazo + guante |
| `leg_l` / `leg_r` | cadera `(±0.068, 0, 0.375)` | pierna + zapatilla |
| `head` | cuello `(0, 0, 0.60)` | cabeza + orejas + cara |
| `hat` | cuello `(0, 0, 0.60)` | gorro (acompaña a la cabeza) |

Se crean con `hinge()` en el generador: un `Empty` en el pivote y los objetos
del miembro como hijos con `matrix_parent_inverse`, así rotar el vacío gira la
extremidad **alrededor de la articulación** y no del origen del modelo.

## Qué anima `player.gd`

`_animate(delta)` corre cada frame de física y usa `walk_phase` (avanza con el
movimiento) más un reloj para la respiración:

- **quieto** — piernas rectas, cabeza y brazos con una respiración suave
  (±0.02 rad), cabeza con un vaivén mínimo.
- **caminando** — piernas alternadas ±0.62 rad, brazos en oposición ±0.55 rad,
  cabeza con cabeceo al doble de frecuencia. El cuerpo ya venía con un rebote
  vertical (`_body_mesh.position.y`).
- **llevando una caja** — los brazos van adelante y un poco abiertos
  (-1.15 rad), así se lee que está cargando aunque la caja sea un cubo.

## Verificación

```bash
godot --headless --path . -- --test      # 29/29 incluye 4 tests del rig
```

Tests: las 6 bisagras existen, caminar mueve las piernas en oposición, quieto
las deja rectas, y con carga los brazos van adelante.

Para ver el ciclo de caminata sin jugar:

```bash
xvfb-run -a blender --background --python /tmp/anim_check.py   # 4 fases → PNG
```
