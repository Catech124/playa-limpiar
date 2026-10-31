# Personajes jugables

Cada jugador usa un GLB distinto (los dos comparten los nombres de las piezas,
así que el mismo **rig automático** sirve para los dos).

| Jugador | Modelo | Fuente |
|---|---|---|
| J1 | `assets/kid.glb` | pescador low-poly (chico) |
| J2 | `assets/mujer.glb` | mujer **suave** (`~/lowpoly-pescador/mujer_suave.glb`) |

`player.gd` elige el modelo en `setup()` con `MODELOS[index % MODELOS.size()]`;
si el GLB de la mujer no está, cae al del chico y, si tampoco, al personaje de
primitivas. Agregar un tercer modelo es sumar una ruta al array (y otra entrada
en `GameConfig.KEYMAPS`).

## Variante suave (bordes redondeados)

El pescador y la jugadora 2 salen del mismo generador (`~/lowpoly-pescador/build.py`)
en dos versiones: *lowpoly* (normales planas) y *suave* (más segmentos + normales
por esquina con corte a 42°). El juego usa la **suave** para los dos.

```bash
cd ~/lowpoly-pescador
python3 - <<'EOF'
import build as B, lib3d as L
L.DETALLE = 1.9          # más segmentos = silueta más redonda
parts = B.build_mujer()
L.DETALLE = 1.0
B.set_mujer(False)
L.auto_smooth(parts, 42.0)                       # normales suaves, filo >42° duro
L.export_glb(parts, "mujer_suave.glb", smooth=True)
EOF
```

`build_mujer()` estaba roto: usaba `DENIM_D` (denim oscuro de los puños) sin
definirlo. Ya está definido en `build.py` con el color real del modelo
(`#3f5b7d`), así que la variante se puede regenerar.

## Menú: idle con gestos

El modelo del menú usa **el mismo rig** que el jugador (`CharModel.construir_rig`)
y no gira: respira, se balancea apenas y cada 4-8 s hace un gesto:

- **saludo**: levanta el brazo derecho, agita la mano, inclina la cabeza y
  agranda un poco la boca (sonrisa); después vuelve a idle.
- **sorpresa**: abre los ojos, levanta las cejas, echa la cabeza atrás y da un
  saltito.

Ojo con los GLB: la geometría viene **horneada** y todos los nodos comparten el
origen del modelo, así que escalar un ojo directamente lo escala desde los pies
(la cara se rompe). Cada pieza que hay que escalar se envuelve en un pivote en
**su** centro (`_pivote_en_centro`).

## Qué necesita un modelo para que el rig lo agarre

El rig se arma solo al cargar (`_prepare_external`) y agrupa mallas **por
prefijo de nombre** en seis bisagras: `arm_l`, `arm_r`, `leg_l`, `leg_r`,
`head`, `hat`. Para que un modelo nuevo funcione tiene que traer, en el mismo
GLB plano (sin huesos), piezas que empiecen con:

| Bisagra | Prefijos |
|---|---|
| `arm_l` / `arm_r` | `manga-1`/`manga1`, `brazo-1`/`brazo1`, `guante-1`/`guante1`, `pulgar-1`/`pulgar1`, `mangaCuff-1`/`mangaCuff1` |
| `leg_l` / `leg_r` | `pierna-1`/`pierna1`, `pie-1`/`pie1`, `suela-1`/`suela1`, `filo-1`/`filo1`, `plant-1`/`plant1`, `dedo-1_`/`dedo1_`, `banda-1`/`banda1` |
| `head` | `cabeza`, `oreja-1`/`oreja1`, `pelo`, `ojo-1_`/`ojo1_`, `ceja-1`/`ceja1`, `rubor-1`/`rubor1`, `nariz`, `boca`, `pestana` |
| `hat` | `ala_`, `copa_`, `cyl`, `sphere` |

Los dos modelos se modelan **mirando a +Z** (en Blender, hacia −Y) y con el piso
en `z = 0`; `CharModel.fit_model()` los escala a 0.92 de alto.

## Pose de cargar (dos manos)

No usa ángulos fijos: al cargar el modelo se mide el centro de los guantes y se
calcula el **cuaternión** que lleva cada mano al punto de agarre (adelante, al
centro y algo debajo del hombro). El lado del hombro se deduce de la **posición
del pivote** (`x` en el espacio del cuerpo), no del nombre: en el modelo de la
mujer `arm_l` está en −X, al revés que en el pescador, y con el signo del nombre
las manos se abrían hacia afuera en vez de cerrarse sobre el objeto.
