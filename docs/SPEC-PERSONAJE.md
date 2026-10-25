# Spec congelado — personaje v2

> Nada de esto se decide mirando: son números. Si algo no se puede medir, no
> entra al spec. Congelado antes de escribir geometría para no iterar a ciegas.

---

## 1. Proporciones (unidades del juego: 1 celda = 1 unidad)

| Medida | Valor | Tolerancia | De dónde sale |
|---|---|---|---|
| Altura total (suela → punta del gorro) | **1.24** | ±0.03 | cuerpo actual 1.23 + gorro nuevo |
| Altura de la cabeza (mentón → coronilla) | **0.50** | ±0.02 | ≈ 42 % del total sin gorro |
| Diámetro de cabeza | **0.51** | ±0.02 | esfera casi perfecta (más ancha que alta) |
| Altura del gorro sobre la coronilla | **0.26** | ±0.04 | 20–28 % del total |
| Ancho de hombros | **0.44** | ±0.02 | 1.6× cadera |
| Ancho de cadera | **0.28** | ±0.02 | |
| Largo de brazo (hombro → muñeca) | **0.30** | ±0.02 | 2 segmentos |
| Diámetro de mano (manopla) | **0.15** | ±0.01 | |
| Largo de pierna visible | **0.16** | ±0.02 | entre short y bota |
| Inclinación del torso | **4°** | ±2° | quita el aire de "muñeco" |

**Regla dura:** cabeza + gorro ≥ 55 % de la altura total. Es lo que hace que el
personaje se lea a 45 px.

## 2. Anclajes (se derivan del spec, no se dibujan)

Todos en coordenadas locales, con los pies en `z = 0`. El rig se **genera** desde acá.

| Anclaje | Posición |
|---|---|
| `feet` | `(±0.088, 0, 0.00)` |
| `knee` | `(±0.088, 0, 0.155)` |
| `hip` | `(±0.075, 0, 0.30)` |
| `pelvis` | `(0, 0, 0.31)` |
| `spine` | `(0, 0, 0.44)` |
| `neck` | `(0, 0, 0.60)` |
| `head` | `(0, 0, 0.83)` — centro de la esfera craneal |
| `head_top` | `(0, 0, 1.08)` — coronilla, base del gorro |
| `shoulder` | `(±0.205, 0, 0.575)` |
| `elbow` | `(±0.262, 0, 0.47)` |
| `wrist` | `(±0.30, 0, 0.40)` |
| `hat_anchor` | `(0, 0, 1.08)`, radio de apoyo `0.19` |

El gorro **solo** puede leer `hat_anchor` (posición y radio). Así, cuando cambie
el cuerpo, revalidar el gorro cuesta una corrida.

## 3. Paleta (hex sRGB; el script convierte a lineal)

| Rol | Hex | Nota |
|---|---|---|
| Piel | `#E8B48A` | |
| Camiseta (J1 / J2) | `#F2B544` / `#3EA8D8` | la pisa el color de jugador |
| Short | `#2F3B52` | oscuro: ancla el contraste |
| Bota | `#232A33` | |
| Guante | `#EDEFEC` | |
| Paja / gorro | `#D9B36A` | a decidir en el barrido |
| Cinta del gorro | **color de jugador** | identidad desde cámara alta |
| Ojos | `#15181D` | |
| Boca | `#A85A4E` | |
| Arena (referencia) | `#DDB97F` | para medir contraste |

**Contraste mínimo:** ΔE(CIELAB) ≥ 25 entre el torso o el gorro y la arena.

## 4. Umbrales de aceptación por variante

Se miden sobre la máscara ortográfica frontal salvo que se indique otra cosa.

| Métrica | Descarte duro | Aceptable |
|---|---|---|
| Cabeza / total (sin gorro) | fuera de 0.36–0.49 | 0.40–0.45 |
| Gorro / total | fuera de 0.17–0.31 | 0.20–0.28 |
| ΔE (albedo) vs `#DDB97F` | < 15 | > 25 |
| Cara visible desde la cámara del juego (68°) | < 85 % del área frontal | ≥ 95 % |
| Componentes conexos a 64 px | ≠ 1 | 1 |
| Perfil de ancho por filas: mínimos locales | ≠ 3 (gorro–cuello–cintura) | 3 |
| Triángulos | > 5.000 | ≤ 3.500 |
| Materiales | > 6 en el export final | ≤ 6 |

**Calibración obligatoria:** correr las métricas sobre el chef actual (v1) antes
de confiar en los umbrales. Si v1 cae fuera de banda en algo, el umbral está mal,
no el modelo.

## 5. Cámara de verificación (la única que cuenta)

- Posición `(12, 24, 17.5)`, objetivo `(12, 0, 8)`, FOV vertical 34°.
- Personaje de 1.24 unidades → **≈ 45 px** de alto en 1280×800.
- Toda decisión estética se toma con esta vista. Las vistas bonitas son para el
  README, no para decidir.

## 6. Límites de proceso (para no inflar el tiempo)

- Máximo **3 iteraciones** por fase. A la tercera: se acepta o se baja el umbral.
- Una imagen por decisión: hoja de contacto, no capturas sueltas.
- Las métricas descartan antes de que yo mire: si no pasa los umbrales, no se ve.
- Se corta en **8/10** de calidad percibida a 45 px. Del 8 al 8.5 el costo se
  triplica y en juego no se nota.
- Fuera de alcance v2: pliegues de tela, pulgares, cejas, más de 2 expresiones.

## 7. Rúbrica de cierre (para que el número sea falsable)

| Peso | Criterio | Cómo se mide |
|---|---|---|
| 30 % | Silueta | reconocible a 64 px en 1 bit; ratios del §4 |
| 25 % | Color y contraste | ΔE medido sobre píxel iluminado en Godot |
| 20 % | Lectura de orientación | se distingue hacia dónde mira a 45 px |
| 15 % | Animación | patinaje de pie ≈ 0, loop cerrado, amplitud de bob en rango |
| 10 % | Detalle | solo se evalúa en menú/resultados |

Al final: una pasada de 10 minutos de una persona ajena con la rúbrica. Sin eso,
la nota es mi opinión sobre mi propio trabajo.
