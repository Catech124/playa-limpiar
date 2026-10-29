# Prompt para Claude — modelo del personaje (Playa Limpia)

> Copiá todo el bloque de abajo y pegálo en Claude. Es autocontenido: describe el
> juego, cómo está armado el personaje hoy y qué se le pide.

---

## Contexto

Estoy haciendo **Playa Limpia**, un juego cooperativo de 2 jugadores hecho en
**Godot 4.7** (renderer **Compatibility**), en 3D, con estética low-poly y
primitivas (sin assets importados). El bucle es tipo *Overcooked*: juntar basura
de la playa, embolsarla en contenedores y entregarla en un camión antes de que se
termine el día. Hay gaviotas que roban basura y un tiburón si te metés al mar.

El personaje jugable y los NPCs se construyen **por código** en un solo archivo:
`scripts/char_model.gd` (GDScript, `class_name CharModel`). No hay GLB, no hay
texturas: todo son `BoxMesh`, `CylinderMesh`, `SphereMesh`, `TorusMesh` y
`PrismMesh` con `StandardMaterial3D` de color plano.

Quiero que me ayudes a que el personaje se parezca lo más posible a una
referencia que tengo (un chico de playa estilo juguete):

- Sombrero de paja de ala ancha, copa baja y redondeada.
- Pelo castaño, rizado, con volumen bajo el ala.
- Ojos grandes: esclerótica blanca, iris marrón, pupila negra y un brillo.
- Cejas gruesas, nariz de botón, sonrisa chica, cachetes rosados.
- Camiseta blanca con rayas horizontales azules y mangas cortas.
- Short azul marino, piernas cortas de piel.
- Sandalias azules con tira blanca en Y.
- Guantes de trabajo marrones.
- Proporciones chibi: cabeza grande, cuerpo corto y ancho, brazos y piernas
  cortos.

## Cómo se ve en el juego

- Cámara **alta en 3/4**, a ~12 unidades del personaje (una celda = 1 unidad).
- El personaje mide **~0.85 unidades** de alto: en pantalla son ~120 px.
- Por eso lo que importa es la **silueta y los colores**, no el detalle fino.
- Estilo: contorno negro por *casco invertido* (el material lleva un `next_pass`
  con `cull_mode = CULL_FRONT` y `grow`), colores planos, sin sombras en el
  sombrero para que no tape la cara.

## API que NO se puede romper

```gdscript
static func build(shirt: Color, hat := "straw") -> Node3D
```

- Devuelve un `Node3D` con estos nodos con nombre exacto (la animación los busca
  y los rota): **`arm_l`, `arm_r`, `leg_l`, `leg_r`, `head`, `hat`**.
- El jugador rota `arm_*` en X (caminar/cargar/pique/nadar), `leg_*` en X,
  `head` en X/Z y `hat` no se toca.
- `HAND_CARRY` (`Vector3`) indica dónde quedan las manos con la pose de cargar:
  ahí se ancla el objeto que lleva el jugador. Si cambiás el largo de los brazos,
  hay que actualizarlo.
- `hat` acepta `"straw"` (jugador) y `"cap"` (NPC, gorrita).
- `shirt` es el color de la remera (los NPCs usan colores distintos).
- Se permite agregar nodos hijos, materiales y geometría libremente **dentro** de
  esas bisagras, y cambiar cualquier número.

## Medidas actuales (unidades del mundo)

| Parte | Valor actual |
|---|---|
| Alto total | ~0.85 (sombrero incluido) |
| Cabeza | esfera `r = 0.195`, centro en `y = 0.700` |
| Bisagra de cabeza | `y = 0.520` |
| Torso (camiseta) | cono de `y = 0.285` a `0.520`, radio `0.190` abajo → `0.125` arriba, 7 bandas alternadas blanco/azul |
| Short | cilindro `y = 0.188..0.308`, radio `0.168`, más un ruedo toroide |
| Piernas | cilindros `r = 0.056`, alto `0.16`, desde `y ≈ 0.205` hacia abajo |
| Sandalias | esfera aplastada `r = 0.072` escala `(1.0, 0.40, 1.60)` + 3 tiras blancas |
| Brazos | bisagra en `(±0.145, 0.435)`; hombro esfera `r = 0.062`, manga cilindro `r = 0.058`, antebrazo `r = 0.040`, guante esfera `r = 0.052` |
| Manos al cargar | `HAND_CARRY = (0, 0.300, 0.215)` |
| Sombrero | ala `CylinderMesh r = 0.272` + borde toroide `0.256..0.276`; copa cilindro `r = 0.146..0.160`, alto `0.125`; domo encima |
| Pelo | 14 racimos de esferas `r = 0.058` + 3 de flequillo `r = 0.070` |
| Ojos | esclerótica `r = 0.056` (escala z 0.26), iris `r = 0.036`, pupila `r = 0.020`, brillo `r = 0.011` |
| Cejas | caja `0.080 × 0.024 × 0.024` |
| Boca | 1 caja `0.048 × 0.010` + 2 comisuras de `0.020` |

Paleta: piel `#F5BF99`, rayas `#5985CC`, short `#243366`, paja `#CCA87B`,
paja oscura `#A8824F`, pelo `#613B21`, iris `#6B4529`, guantes `#8C613D`,
sandalias `#5285D1`.

## Restricciones duras

1. **Sin texturas ni assets externos**: solo mallas primitivas y
   `StandardMaterial3D`. Nada de `ShaderMaterial` con texturas.
2. **Godot 4.7, renderer Compatibility**: cuidado con transparencias (se usa solo
   en cachetes y contornos) y con `grow` (funciona en este renderer).
3. **Debe leerse desde arriba y de lejos**: evitar detalles menores a ~0.02
   unidades y evitar geometría que solo se ve de frente.
4. **Nada de sombras duras** del ala sobre la cara: el sombrero va con
   `cast_shadow = OFF`.
5. **Presupuesto**: el personaje se dibuja 2 veces (jugador + NPCs), así que
   mantenerlo por debajo de ~120 `MeshInstance3D` en total. Hoy hay ~60.
6. **Sin intersecciones visibles grandes** entre piezas (el contorno negro
   delata las costuras).
7. Todo el código va en `scripts/char_model.gd`, en las funciones
   `_build_legs`, `_build_torso`, `_build_arms`, `_build_head`, `_build_hair`,
   `_build_face`, `_build_hat`, usando el helper `_mesh(parent, mesh, color, pos)`.

## Cómo verifico los cambios

Render de vista previa en ~3 segundos (sin abrir el juego):

```bash
xvfb-run -a -s "-screen 0 640x640x24" godot --path . scenes/CharPreview.tscn \
  --resolution 640x640 -- --out=/tmp/char.png        # de frente
#  agregando  --side   sale de costado
```

## Qué necesito de vos

1. Proponé **cambios concretos de código** (funciones completas o diffs) para que
   el modelo se parezca más a la referencia, priorizando lo que se nota a 120 px:
   silueta del sombrero, volumen del pelo, tamaño/posición de los ojos,
   proporciones del cuerpo y de las extremidades.
2. Explicá **por qué** cada cambio mejora la lectura desde la cámara alta y qué
   números tocaste.
3. Si algo no se puede lograr con primitivas, decilo y proponé la alternativa más
   cercana (por ejemplo, simular el ala ondulada con tramos que se solapan, o el
   trenzado con un toroide más oscuro).
4. Mantené la API y los nombres de las bisagras, y avisá si hay que actualizar
   `HAND_CARRY`.
5. Devolvé el código listo para pegar (GDScript válido para Godot 4.7), no
   pseudocódigo.

## Archivo actual (resumen de la estructura)

```gdscript
class_name CharModel
extends RefCounted

const HEAD_R := 0.195
const HEAD_Y := 0.700
const HINGE_Y := 0.520
const SHOULDER_X := 0.145
const SHOULDER_Y := 0.435
const HAND_CARRY := Vector3(0.0, 0.300, 0.215)
const TORSO_BOTTOM := 0.285
const TORSO_TOP := 0.520
const TORSO_R_BOTTOM := 0.190
const TORSO_R_TOP := 0.125

static func build(shirt: Color, hat := "straw") -> Node3D:
    var root := Node3D.new()
    root.name = "CharModel"
    _build_legs(root)
    _build_torso(root)
    _build_arms(root)
    _build_head(root, hat)
    return root

# _build_legs / _build_torso / _build_arms / _build_head /
# _build_hair / _build_face / _build_hat / _mesh
```
