# Plan de modelado del personaje — handoff para revisión

> Documento para que otro modelo (Claude) razone sobre **el flujo**, no sobre el
> arte. La pregunta central es: *¿cómo hacemos que el lazo de iteración sea lo
> más barato, paralelo y medible posible, con un agente que no puede esculpir a
> mano ni ver el modelo en tiempo real?*

---

## 0. Qué necesito de vos

1. **Criticar el pipeline** de §5: qué fases se pueden fusionar, cuáles son
   prematuras, cuáles generan re-trabajo si se hacen en ese orden.
2. **Diseñar el lazo de iteración** de §6 con números concretos: tamaño de lote,
   qué se renderiza en Workbench vs Cycles, cuántas variantes por barrido, cómo
   se puntúan automáticamente.
3. **Decidir la arquitectura del generador**: parámetros en JSON + código que los
   consume, vs funciones Python con argumentos. Piénsalo para *muchas variantes*
   y para *poder volver atrás*.
4. **Responder las preguntas de §8** con una recomendación y su justificación.
5. Señalar qué parte del plan **no** puede llegar a 8,5/10 y por qué.

Formato de salida esperado: plan priorizado, con estimación de tiempo por fase,
decisiones tomadas (no menú de opciones) y el esquema de parámetros propuesto.

---

## 1. Contexto y estado actual (hechos medidos, no estimaciones)

**Proyecto:** `~/Projects/playa-limpiar` — prototipo jugable en Godot 4.7.2
(3D, renderer `gl_compatibility`) de un juego co-op de recolección de basura en
una playa, con la estructura de mecánicas de Overcooked 2. Público:
`github.com/Catech124/playa-limpiar`.

**Asset actual:** `assets/chef.glb`
- Generado por `tools/make_chef.py` (Blender 5.2.2 LTS, headless con `xvfb-run`).
- **3.072 triángulos · 9 materiales · ~100 KB · sin texturas** (color plano).
- Construido uniendo primitivas (esferas UV, cilindros, cajas con bevel).
- 9 materiales con nombre: `skin, shirt, shorts, hat, band, gloves, boots, eyes, mouth`.
- La remera y la cinta del sombrero se tiñen por jugador desde Godot
  (`scripts/player.gd`, sobreescribe la surface por nombre de material).

**Cómo se ve hoy (autoevaluación contra Overcooked 2): 5,5/10.** Funciona la
proporción cabeza/cuerpo y el pipeline; falla la silueta del gorro (ala plana en
vez de toque alto con lóbulos), el contraste con la arena, la cara (dos esferas y
una rayita), las manos (bolas) y la postura (rígida, simétrica).

**Escala y cámara (datos duros):**
- 1 celda del mapa = 1 unidad. Personaje ≈ 1,23 unidades de alto.
- Cámara fija: posición `(12, 24, 17.5)`, objetivo `(12, 0, 8)`, FOV 34°,
  inclinación ≈ 68° sobre la horizontal.
- En pantalla el personaje mide **≈ 45 px** de alto (1280×800).
- Color de la arena: `#DDB97F`. Contraste actual personaje/arena: ΔE ≈ 8
  (objetivo > 25).

**Herramientas existentes:**
- `tools/make_chef.py` — generador (Blender API) + hoja de vistas con Cycles.
- `scenes/ModelViewer.tscn` + `scripts/model_viewer.gd` — visor con 3 copias
  girando y bandera `--shot=path` para capturas automáticas.
- `tests/shot.gd` — capturas del juego (`--demo`, `--demo2`, `--closeup`,
  `--menu`, `--results`).
- `tests/headless_test.gd` — 24 comprobaciones de mecánicas (no toca el asset).

**Cómo verifico hoy:** renderizo por script y leo las imágenes; mido a ojo.

---

## 2. Objetivo y criterio de éxito (medible)

Subir el personaje de 5,5 a **8,5–9** sin cambiar el pipeline (sigue siendo
generado por script, reproducible y versionable).

Se acepta como terminado cuando **todo** esto pasa:

| Criterio | Umbral |
|---|---|
| Silueta reconocible a 64 px en 1 bit | se distingue cabeza, gorro, cuerpo y brazos |
| Proporción cabeza/total | 40–45 % (sin contar gorro) |
| Altura del gorro | 20–28 % de la altura total |
| Contraste con la arena (ΔE) | > 25 en el torso o el gorro |
| Presupuesto | ≤ 5.000 tris · ≤ 6 materiales en el GLB final (o 9 con textura atlas) |
| Lectura a la cámara real (45 px, 68°) | se identifica al jugador y su orientación |
| Animación | idle + walk + work + carry, exportadas en el GLB |
| Determinismo | mismo comando → mismo GLB (bit a bit o equivalente) |

---

## 3. Restricciones duras del entorno

- **Sin GUI**: todo headless. Blender por `--background` + `xvfb-run` cuando el
  render lo necesita. Godot por `--headless` para reglas y `xvfb-run` para capturas.
- **Sin tableta ni escultura manual**: el "esculpido" es matemático (desplazar
  vértices con caída de influencia), o modificadores (`Remesh`, `Subdivision`,
  `Shrinkwrap`, `Displace`, `Bevel`).
- **Cuello de botella del agente**: el lazo es `script → render → mirar → corregir`,
  ~20-40 s por ciclo; 60-100 ciclos por hora. La observación es una imagen fija,
  no un modelo girando.
- **Trampas de la API de Blender 5.2 ya encontradas** (no repetir):
  - Los nodos del material se buscan **por tipo** (`BSDF_PRINCIPLED`,
    `OUTPUT_MATERIAL`, `BACKGROUND`), no por nombre: los nombres cambiaron en 5.x.
  - Los colores son **lineales**: hay que convertir desde hex sRGB o el personaje
    sale casi blanco.
  - `bpy.context.object` después de `join()` + añadir cámara apunta a la cámara.
  - El ala del sombrero demasiado ancha **tapa la cara** a 68° de cámara.
- **Godot**: `gl_compatibility`. Sin subsurface scattering ni SDFGI. El brillo se
  controla con `sun 0.75 / ambient 0.40 / exposure 0.95`; por encima de eso los
  materiales se queman a blanco.

---

## 4. Diagnóstico del asset actual (qué hay que arreglar)

1. **Gorro**: ala plana + copa baja. En Overcooked el toque es alto y lobulado:
   es el 30 % del reconocimiento del personaje.
2. **Contraste**: beige sobre arena pálida. El personaje se camufla.
3. **Cara**: dos esferas negras, una nariz y una barra. Sin cejas, sin expresión,
   sin asimetría. En Overcooked la cara es **textura**, no geometría.
4. **Manos**: bolas. Sin pulgar, sin muñeca.
5. **Brazos**: cilindros rectos simétricos, sin articulación.
6. **Postura**: de pie, rígida. Sin inclinación ni asimetría.
7. **Ropa**: color plano sin pliegues, cuello, pañuelo ni ruedo.
8. **Animación**: ninguna (se desliza).

---

## 5. Pipeline propuesto (a criticar y reordenar)

| Fase | Contenido | Técnica | ¿Re-trabajo si va después? |
|---|---|---|---|
| **0** | Barrido de gorro (12 variantes) | Generador paramétrico + hoja de contacto + métricas | No |
| **A** | Volumen orgánico del cuerpo | Metaballs → `convert` → `Remesh` voxel → `Decimate` | **Sí**: cambia la malla base, invalida UVs y pesos |
| **B** | Cara pintada | UV del cráneo + textura 1024² pintada con PIL | No (depende de A) |
| **C** | Ropa con volumen | Malla aparte + `Solidify` + `Subdivision` + `Displace` | No |
| **D** | Manos y props | Manopla con pulgar, prop de espera | No |
| **E** | Rig + animación | Armadura + `ARMATURE_AUTO` + 4 clips + `export_animations` | **Sí**: si A cambia, se re-pesan |
| **F** | Materiales y luz | Rugosidad por material, saturación, rim light | No |
| **G** | Verificación | 8 vistas, máscaras, métricas, test in-engine | No |

**Ordenación dudosa a propósito:** ¿conviene hacer E (rig) antes de C/D para
descubrir temprano si los pesos funcionan, o esperar a tener la malla final?
Argumentar.

---

## 6. El problema central: abaratar y paralelizar el lazo

Mi lazo es lento y de baja fidelidad. La hipótesis es que **el costo por
iteración se puede bajar de ~30 s a ~5 s** y que el ancho de banda se puede
multiplicar con barridos. Necesito que valides o refutes esto con un diseño.

Piezas que quiero que consideres:

1. **Separar generación de render.** Un proceso Blender que genere *N* variantes
   y las guarde (GLB + JSON de parámetros + métricas) sin renderizar; otro que
   renderice en lote. ¿Vale la pena el pipeline en dos etapas o el arranque de
   Blender (~2 s) es despreciable frente al render?
2. **Workbench para máscaras, Cycles solo para la final.** El test de silueta
   necesita alfa y 1 bit: ¿Workbench con `film_transparent` a 256 px alcanza?
3. **Hoja de contacto**: 12 variantes en una grilla con etiqueta. ¿12 es el
   número correcto para una decisión estética, o conviene 6+6 en dos rondas?
4. **Métricas automáticas por variante** (para pre-filtrar antes de mirar):
   - IoU de silueta contra el recorte de referencia (alineado por pies y eje)
   - ratio cabeza/total y gorro/total desde el bounding box de la máscara
   - ΔE del color dominante del torso/gorro contra la arena
   - lectura a 64 px (¿cuántos componentes conexos? ¿se separan brazos?)
   ¿Qué umbrales descartan una variante sin intervención humana?
5. **Barridos factoriales vs búsqueda secuencial.** Con 5 parámetros y 3 valores
   cada uno son 243 combinaciones: ¿factorial completo con pre-filtro por
   métrica, o optimización secuencial (coordinate descent) con 2 rondas?
6. **Caché y reproducibilidad**: hash de parámetros → GLB. Evita regenerar y
   permite volver a cualquier variante.
7. **Versionado de assets**: ¿carpeta por versión (`assets/v2/…`) o un solo
   archivo con el parámetro en el nombre y el `main` apuntando al elegido?

---

## 7. Fase 0 concreta: barrido de 12 gorros

**Objetivo:** elegir la forma del gorro midiendo, no discutiendo.

**Parámetros por variante** (5):
| Parámetro | Valores |
|---|---|
| `tipo` | toque lobulado · sombrero de paja abombado · gorra de visera · pamela curva |
| `altura_copa` | 0.10 · 0.16 · 0.22 |
| `lobulos` | 3 · 4 (solo toque) |
| `ala` | 0.00 · 0.18 · 0.26 (radio relativo) |
| `banda` | fina · gruesa · sin banda |

**Salida por variante:** `gorro_<hash>.glb` + `gorro_<hash>.json` (parámetros y
métricas) + render frontal y 3/4 en una hoja de contacto de 12 celdas.

**Selección:** pre-filtro por métricas (§6.4) → miro la hoja → elijo 2 → segunda
ronda solo con las variables del ganador.

**Pregunta para Claude:** ¿esta fase 0 se hace con el cuerpo actual (contexto
realista) o con una cabeza proxy neutra? Sospecho que con el cuerpo actual,
porque el gorro compite con los hombros en la silueta.

---

## 8. Preguntas abiertas (responder con recomendación)

1. **Malla base**: ¿metaballs + remesh voxel + decimate, o subsurf + shrinkwrap
   sobre esferas, o mantener primitivas con más segmentos + `Smooth`? Mi miedo
   con metaballs es la silueta "derretida"; mi miedo con primitivas es el
   aspecto de bloques pegados.
2. **Cara**: ¿textura pintada proyectada frontal (mi apuesta) o geometría?
   ¿Cómo manejo el UV del cráneo para que la proyección no se deforme al girar?
3. **Animación sin ver movimiento**: ¿cómo valido timing y peso con imágenes
   fijas? ¿Tiras de 8 frames por ciclo + análisis de arcos basta, o hay una
   forma mejor (por ejemplo, comparar posiciones de huesos contra una referencia
   numérica de curvas de animación)?
4. **Pesos**: `ARMATURE_AUTO` sobre una malla unida por metaballs — ¿funciona o
   conviene rig rígido por partes (que en este estilo casi no deforma)?
5. **Orden**: ¿A→B→C→D→E o E temprano como prueba de riesgo?
6. **Cuánto vale la pena**: ¿hay un punto donde el esfuerzo por punto de calidad
   se dispara y conviene aceptar 8 y pasar a mecánicas?

---

## 9. Riesgos y planes B

| Riesgo | Plan B |
|---|---|
| Metaball/remesh da formas blandas | Base por primitivas + subsurf + `Shrinkwrap` y ajuste de perfiles |
| Decimate destruye la silueta | Decimate planar + `Smooth by Angle`; o modelar directo en baja |
| Pesos automáticos fallan | Rig rígido por partes (cabeza, torso, brazos, piernas como objetos separados) |
| La textura de la cara no se alinea al girar | Proyección UV desde frente + seams en la nuca; aceptar leve estiramiento lateral |
| El gorro gana el barrido pero se ve mal en juego | El criterio final es el test in-engine (§2), no la hoja de contacto |
| Ciclos insuficientes | Barridos factoriales con pre-filtro + caché por hash |

---

## 10. Entregables

1. `tools/gen_chef.py` con parámetros externos (JSON) y caché por hash.
2. `assets/chef_v2.glb` (malla + textura de cara + rig + 4 clips).
3. `docs/metricas-<fecha>.json` + hoja de contacto del barrido.
4. Un `.blend` limpio (`assets/chef_base.blend`) con topología, UVs, rig y pesos
   para que un humano lo pueda pulir sin empezar de cero.
5. Actualización de `docs/modelo-preview.png` y del visor.

---

## Anexo A — Cómo "veo" el modelo (restricción de percepción)

- Renderizo 8 vistas ortográficas + tiras de frames y **leo las imágenes**.
- Soy bueno en errores gruesos (silueta, proporción, color) y flojo en curvatura
  fina y tensión de planos.
- Por eso el plan prioriza **métricas numéricas** sobre juicio visual: máscaras,
  IoU, ratios de bounding box, ΔE, conteo de componentes a 64 px.
- Toda decisión estética que no se pueda medir necesita una hoja de contacto con
  variantes para elegir, no una iteración a ciegas.

## Anexo B — Comandos de referencia

```bash
# generar el asset actual + hoja de vistas
xvfb-run -a blender --background --python tools/make_chef.py

# visor del personaje (3 copias girando)
godot --path . scenes/ModelViewer.tscn

# captura automática del visor
xvfb-run -a godot --path . --rendering-driver opengl3 \
  res://scenes/ModelViewer.tscn -- --shot=/tmp/visor.png

# captura in-engine a la cámara real del juego
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --resolution 1280x800 -- --shot=/tmp/juego.png --closeup

# tests de mecánicas (no toca el asset)
godot --headless --path . -- --test
```
