# Dispensador de bolsas y camión de entrega

Los dos son low-poly retro, generados por código en `~/botes/estaciones.py`
(bpy + Blender 5.2), igual que los botes recicladores. La fuente de verdad es el
script: no hay nada modelado a mano.

## Piezas

| Pieza | GLB en el juego | Medidas (m) | Notas |
|---|---|---|---|
| Dispensador de bolsas | `assets/dispensador.glb` | 0.81 × 0.76, 1.07 de alto | cuerpo a 8 caras, pila de bolsas dobladas arriba sujetas por una barra, dos bolsas saliendo de la ranura del frente |
| Camión de entrega | `assets/camion.glb` | 2.09 × 1.07, 1.11 de alto | cabina naranja, caja con costillas, lona con cinchas, compuerta trasera con bisagras y escalón, 3 ruedas por lado, calcomanía de reciclaje |

Los dos vienen **apoyados en el piso y con el frente hacia +Z** (en Blender miran
a −Y), así que en el juego se colocan **sin rotación**. El camión se escala en
largo para ocupar exactamente el tramo de celdas que pide el mapa (`DD` = 2
celdas en el nivel 1) y arranca en `x = 0` del tramo.

## Cómo los usa el juego

`scripts/station_models.gd`:

- `StationModels.build_bags()` → dispensador centrado, apoyado, escalado a 0.95.
- `StationModels.build_truck(largo)` → camión escalado a `largo` celdas.

`grid_world._build_station()` los coloca en los tiles `bags` / `delivery`. Si el
GLB no está, cae a una caja simple para no romper el mapa.

## Regenerar

```bash
cd ~/botes
blender -b --factory-startup --python estaciones.py -- --pieza ambos --exportar \
        --vista iso --res 1400x900 --muestras 32 --nombre estaciones
cp estaciones/dispensador.glb ~/Projects/playa-limpiar/assets/dispensador.glb
cp estaciones/camion.glb ~/Projects/playa-limpiar/assets/camion.glb
```

Opciones: `--pieza dispensador|camion|ambos`, `--vista iso|frente|lado|arriba|detalle`,
`--res WxH`, `--muestras N`, `--motor CYCLES|EEVEE`, `--piso 0|1`, `--exportar`.

## Decisiones que se ven en el juego

- **La cámara del juego mira desde arriba (42°)**, así que lo que identifica cada
  estación tiene que estar en la cara de arriba: por eso la pila de bolsas del
  dispensador va sobre el techo y no dentro de un escaparate frontal.
- Se probaron y descartaron: ventana con rollo de bolsas (el cuerpo es sólido, la
  ventana quedaba enterrada), pictograma lateral (se leía como una “C”), estante
  delantero (la cámara alta solo veía su tapa).
- El azul del dispensador es más claro que el de la carrocería del camión a
  propósito: en el juego las caras verticales reciben poca luz (la luz viene de
  arriba) y un azul medio se veía casi negro.
