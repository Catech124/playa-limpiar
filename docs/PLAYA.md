# Palmera, sombrilla y reposera

Las tres son low-poly retro, generadas por código en `~/botes/playa.py`
(bpy + Blender 5.2), igual que los botes, el dispensador y el camión.

| Pieza | GLB en el juego | Medidas (m) | Notas |
|---|---|---|---|
| Palmera | `assets/palmera.glb` | 2.30 de alto (2.52 con la corona), corona de ~2.0 de diámetro | tronco curvo en 8 tramos con anillos, 9 hojas (dos verdes alternados) y 3 cocos |
| Sombrilla | `assets/sombrilla.glb` | 1.31 de alto, toldo de 1.13 de diámetro | poste, base de madera, 8 paneles alternados, varillas en las costuras y punta |
| Reposera | `assets/reposera.glb` | 1.36 × 0.60, respaldo a 0.67 | largueros de madera, patas, travesaños y 9 fajas de tela sobre el perfil |

## Tela tintable

La sombrilla y la reposera se exportan con la tela **en blanco** y el juego la
tiñe por nodo:

- `toldo_a` → color de la sombrilla (los paneles pares; los impares `toldo_b`
  quedan crema, como las sombrillas de playa de verdad).
- `tela` → color de la reposera (las nueve fajas).

`scripts/prop_models.gd` hace el teñido con `material_override` y devuelve el
nodo listo para colocar.

## Cómo se usan

- `grid_world._palm()`: cada palmera gira al azar y cambia ~10 % de tamaño (si
  no, cuatro copias iguales se leen como clones). Collider cilíndrico de 0.16.
- `grid_world._umbrella()`: color de la paleta de playa, giro al azar.
- `grid_world._lounger()`: el 4.º dato del `DECOR` es el giro en grados; las
  tres del nivel 1 van a 0° (en fila, paralelas a la orilla). Reservan la celda
  (`tile.decor`) para que no aparezca basura encima, y llevan collider de 0.34.

## Regenerar

```bash
cd ~/botes
blender -b --factory-startup --python playa.py -- --pieza ambos --exportar \
        --vista iso --res 1400x900 --muestras 32 --nombre playa
cp playa/palmera.glb playa/sombrilla.glb playa/reposera.glb \
   ~/Projects/playa-limpiar/assets/
```

Opciones: `--pieza palmera|sombrilla|reposera|ambos`, `--vista iso|frente|lado|arriba|detalle`,
`--res WxH`, `--muestras N`, `--motor CYCLES|EEVEE`, `--piso 0|1`, `--exportar`,
`--toldo #RRGGBB` (solo para el render: tiñe los paneles `toldo_a`).
