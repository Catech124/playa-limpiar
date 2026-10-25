# Patrones del corpus (no reglas)

Dos observadores independientes sobre el mismo material:

- **Imágenes**: 7 lotes analizados por DeepSeek (44 personajes + props).
- **Mallas**: 35 personajes medidos con `tools/corpus_features.py` + `corpus_archetypes.py`.

Cuando los dos coinciden sin haberse visto, el patrón es sólido. Cuando discrepan,
el que miente es el instrumento, no el corpus.

---

## Capa 1 — Proporción y masa

| Patrón | Evidencia imágenes | Evidencia malla |
|---|---|---|
| Cabeza desproporcionada | 1/3 a 1/1 del total (chibi), 6/8 · 7/8 · 8/8 según lote | masa en la franja superior **0,28-0,33** |
| Punto más ancho | cabeza u hombros | ancho/alto 0,59 (blocky) a 0,95 (mini) |
| Cintura vacía | hueco visible entre brazos y torso | franja media (4) = **0,00** de la masa |
| Piernas cortas | 1/3 inferior compacto | masa en franjas 0-3: 0,09-0,13 |

**Constante del corpus:** cabeza + torso se llevan casi toda la masa; las
extremidades son muñones. Es el "juguete", no el humano.

## Capa 2 — Descomposición (el "encimado")

| Patrón | Imágenes | Malla |
|---|---|---|
| Volúmenes por personaje | **4-6** (cabeza, torso, 2 brazos, 2 piernas) | mediana **6** componentes |
| Cómo se unen | se **interpenetran** en las articulaciones | mediana **6-8** pares de AABB solapados |
| Piezas flotantes | **0/8 en todos los lotes** | 0 detectadas |

**Hallazgo central:** el solape **no es un error de modelado, es el método de
ensamblado**. Un personaje low-poly se construye metiendo la cabeza en el torso
y los brazos en los hombros. "Encimado" no significa "mal hecho": significa
"sin intención". Lo que sí es un defecto es el solape *visible* desde la cámara.

## Capa 3 — Silueta

| Patrón | Evidencia |
|---|---|
| Legibilidad por **espacio negativo** | huecos axila-antebrazo, entrepierna, entre piernas: 5/8 · 8/8 · 8/8 |
| Extremidades separadas del torso | 8/8 en los lotes de personajes |
| Complejidad de contorno | hull_ratio 12,9-14,8 (círculo = 12,6): contornos casi circulares |

**Contradicción aparente resuelta:** la silueta es "simple" (casi circular) pero
legible, porque la lectura no viene del contorno externo sino de los **huecos
internos**. Un bloque con dos ranuras se lee mejor que un contorno complicado.

## Capa 4 — Color

| Patrón | Imágenes |
|---|---|
| Tonos por personaje | **2-4 planos**, sin texturas (8/8) |
| Contraste de valor | alto, entre pelo/gorra oscura y piel clara; o ropa vs piel |
| Dónde va el acento saturado | **torso** (ropa) o **cabeza** (pelo/visor); en props, en los extremos |

La malla no puede confirmarlo: el color de estos modelos vive en la textura y mi
extractor todavía lee 0 en los que no la tienen. **Deuda pendiente.**

## Capa 5 — Cara y propósito

| Patrón | Imágenes | Malla |
|---|---|---|
| Rasgos | ojos de punto oscuro; boca y nariz casi nunca | — |
| Proporción de cara | tercio **inferior** del bloque craneal; 10-20 % de la superficie frontal | — |
| Pelo/gorro | mitad superior de la cabeza | — |
| Señal de propósito | color + accesorio (delantal, mochila, visor, bastón) | — |

**Esto solo lo puede ver la imagen.** La malla no sabe qué *oficio* sugiere un
personaje: eso vive en el color, el accesorio y el contexto.

## Capa 6 — Simetría (la excepción que confirma)

| Observador | Dato |
|---|---|
| Malla | simetría p50 **0,000**, p90 0,01 → **100 % simétricos** |
| Imágenes | 1 excepción asimétrica en todo el corpus (un audífono) |

**El corpus profesional de low-poly es simétrico.** Overcooked rompe esa norma a
propósito: caras asimétricas, gorros torcidos, accesorios de un solo lado. Ese es
uno de los motivos por los que se recuerda.

---

## Las 5 constantes (consenso de los dos observadores)

1. **4-6 volúmenes** primitivos por personaje.
2. **Intersección en las articulaciones**; cero piezas flotantes.
3. **Espacio negativo** en la silueta (axilas, entrepierna) como fuente de legibilidad.
4. **Paleta plana de 2-4 tonos** con acento saturado en torso o cabeza.
5. **Cabeza sobredimensionada** y extremidades cortas.

## Las 3 excepciones notables

1. Personaje "robot/traje" (bloque monocromático sin cuello): rompe la norma de
   "humanoide con ropa" y sigue leyéndose.
2. Personaje con cabeza **más grande que el torso** (1:1): rompe la proporción
   1:3-1:4 del resto.
3. El único asimétrico del corpus (audífono): demuestra que la asimetría es
   posible sin perder lectura.

## Qué implica para nuestro personaje

| Constante | Estado nuestro |
|---|---|
| 4-6 volúmenes | ✅ 6 (cabeza, torso, shorts, 2 brazos, 2 piernas) |
| Intersección en articulaciones | ✅ brazos dentro del torso |
| Espacio negativo | ✅ corregido: brazos separados del torso (hueco triangular) |
| Paleta plana + acento | ✅ gorro crema (ΔE 27) + cinta saturada con color de jugador |
| Cabeza dominante | ✅ |
| Cara en tercio inferior | ✅ ojos 0.046 + cejas + boca ancha: 100 % visible desde la cámara del juego |
| Simetría | ⏸ sigue perfecta: la asimetría intencional queda para la próxima iteración |

**Conclusión operativa:** nuestro modelo ya cumple las constantes de
construcción; lo que le falta son las tres palancas que el corpus usa para
leerse: **hueco entre brazos y torso**, **acento de color saturado** y **cara
más grande que dos puntos**. La asimetría es la única donde conviene apartarse
del promedio.

## Deuda del método

- Los lotes de imágenes se armaron por orden de archivo: **dos lotes cayeron en
  props** (bastones, sillas de ruedas, audífonos). DeepSeek lo detectó solo
  ("la muestra mezcla 4 humanoides con 4 objetos"). Hay que filtrar por personaje
  antes de armar la hoja.
- La paleta no está medida en malla: falta leer color por vértice o muestrear el
  atlas correctamente.
- 35 personajes siguen siendo pocos: los clusters separan *packs* (pureza 85 %).
