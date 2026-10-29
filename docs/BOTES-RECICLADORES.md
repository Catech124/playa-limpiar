# Botes recicladores (assets/botes_reciclaje.glb)

Los tres contenedores del juego son el paquete **low-poly retro** generado con
Blender (`~/botes/botes.py`). Ahí vive la fuente de verdad; acá solo se copia el
GLB ya exportado.

## Qué trae el GLB

- **Tres botes en fila** a `x = -0.655, 0, +0.655`, 1.05 m de alto, 0.56 × 0.68
  de planta (medida real de un contenedor de dos ruedas).
- Orden y color: **VIDRIO** verde (`cuerpo_VIDRIO`), **PET** amarillo
  (`cuerpo_PET`), **METAL/LATAS** gris (`cuerpo_METAL`). El color no se adivina:
  se lee el **nombre del material** de cada `cuerpo`.
- La tapa es un nodo aparte (`tapa`, `tapa_001`, `tapa_002`) con el **origen en la
  bisagra**: rotando `rotation.x` se abre. En `scripts/bin_model.gd` se renombra
  a `Lid`.
- Adentro hay bolsa negra (`bolsa*`) y latas (`m_lata*`): el juego las **oculta**
  porque dibuja su propio forro cuando cuelgan una bolsa.

## Cómo se usa

`scripts/bin_model.gd` (`BinModel.build(tipo)`):

1. instancia el GLB y deja **un solo** bote (el que corresponde al tipo del tile);
2. lo centra, lo apoya en el piso y lo escala a 0.95 m;
3. lo gira 180° para que la placa PUSH mire a la cámara (+Z).

`grid_world._build_station` lo coloca en cada tile `bin` y guarda la tapa en
`CellData.bin_lid`, que `main._tick_bin_lids()` abre 104° cuando hay una bolsa
colgada y cierra cuando se la llevan.

## Regenerar

```bash
cd ~/botes
blender -b --factory-startup --python botes.py -- --piso 0 --exportar   # .blend + .glb
cp final/botes.glb ~/Projects/playa-limpiar/assets/botes_reciclaje.glb
```

Ojo: Godot sanea los nombres del GLB (`tapa.001` → `tapa_001`), así que cualquier
búsqueda por nombre tiene que aceptar el guion bajo.
