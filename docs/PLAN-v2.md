# Plan de implementación v2 (Playas Limpias)

Decisiones bloqueadas (las recomendadas en `DISENO-v2.md`):
4 min por nivel · **bolsa primero** · cuota **por tipo** · agua transitable ·
vidrio roto desaparece · cooperativo 2 jugadores se mantiene.

## Fase 1 — Bucle de cuota (jugable y divertido) — ✅ HECHA

| # | Paso | Archivos | Estado |
|---|---|---|---|
| 1.1 | Modo "cuota": nivel con zonas de spawn, 3 contenedores y camión | `levels.gd`, `config.gd` | ✅ |
| 1.2 | Basura que aparece tirada (playa y agua) con temporizador de 6 s | `spawner.gd` (nuevo), `carry_item.gd` | ✅ playa · agua en Fase 3 |
| 1.3 | Contenedores con boca de bolsa: depositar → la bolsa se llena | `main.gd`, `grid_world.gd` | ✅ |
| 1.4 | Camión: entregar la bolsa suma a la cuota por tipo | `main.gd` | ✅ |
| 1.5 | HUD: reloj de 24 h + 3 barras de cuota + avisos | `hud.gd` | ✅ |
| 1.6 | Fin de nivel: cuota cumplida / tiempo agotado | `main.gd` | ✅ |

Tests headless: **60** (meta 45+), incluidos los tres niveles comprobando que el
ritmo de aparición alcanza para llenar la cuota.

Decisiones que se resolvieron al implementar (no estaban en el plan):

- **El tipo se comprueba antes que la bolsa**: tirar vidrio en el contenedor de
  latas castiga aunque no haya bolsa colgada. Antes el aviso "falta la bolsa"
  tapaba el error del jugador (y el castigo nunca se aplicaba).
- **La bolsa cuelga dentro de la boca** (asoma el borde y el nudo, y sube con lo
  que lleva): afuera parecía un cono, adentro una bandeja.
- **El spawner pesa el tipo por lo que falta de la cuota** (mínimo 1 por tipo):
  el nivel no se puede volver imposible por azar.
- **La cámara no se abre sin freno** (11 → 15.5 unidades): a 24 los personajes
  quedaban del tamaño de una uña. Si los jugadores se separan mucho, uno puede
  quedar al borde de la pantalla, como en Overcooked.
- **La gaviota se lleva el residuo** (no lo tira en otro lado) y el −2 queda para
  la Fase 2, junto con el tope de castigos.
- **Los residuos se modelaron por silueta** (botella PET con etiqueta y tapa,
  botella de vidrio con cuello largo, lata con banda): un cilindro pelado no se
  distinguía desde la cámara alta.
- **La bolsa cuelga expandida como forro** del contenedor (plástico sobre el
  marco, falda por fuera y basura a la vista adentro). En la mano va más chica y
  al costado: al pecho tapaba al personaje entero.
- **La gaviota depende de cuántos jugadores hay** (55 s / cada 50 s solo;
  30 s / cada 34 s de a dos): con un jugador era imposible cubrir la playa.
- **La basura es un cuerpo rígido** (cápsula) con piso físico propio: cae desde
  0.55 m al aparecer, queda acostada y se puede patear. En la mano o en el pico
  de la gaviota se congela.
- **Materiales**: vidrio translúcido (alfa + rim), metal satinado (0.7) y PET
  opaco. Con metallic 1 la lata quedaba azul oscura por el reflejo del cielo.
- **El ítem va entre las manos** (pose de cargar), no al costado: era el bug de
  "aparecen al lado de las manos".

## Fase 2 — Presión — ✅ HECHA

| # | Paso | Estado |
|---|---|---|
| 2.1 | Basura que se hunde en el mar (−2) | ✅ 10 s, primera fila de agua |
| 2.2 | Vidrio que se rompe en la arena (−2) | ✅ a los 14 s |
| 2.3 | Gaviota que roba basura del piso (−2) | ✅ del piso |
| 2.4 | Aro de cuenta atrás + tope de 3 castigos/min | ✅ |

Decisiones de implementación:

- **La basura flotante va solo en la primera fila de agua** (se alcanza desde la
  orilla): el agua todavía no se camina, así que más adentro sería una pérdida
  garantizada. El agua pasó a ser un **escalón bajo (0.20 m)**: frena al jugador
  igual que una pared y deja flotar la basura.
- **Los tiempos de vencimiento son más largos que los 6 s del diseño** (10 s el
  agua, 14 s el vidrio): medido en una simulación de 15 s sin jugador, con 6 s
  vencían 5 basuras. El aro avisa y el margen tiene que alcanzar para cruzar la
  playa caminando.
- **La gaviota roba solo del piso** (no de la bolsa colgada): sacar de la bolsa
  castigaba al que estaba embolsando, que es justo lo que hay que premiar.
- **El tope de castigos** se lleva con una ventana de 60 s. Los castigos que no
  descuentan igual se cuentan y se avisan («tope, no descuenta»).
- **Los castigos cuestan puntos, no tiempo**: la cuota se gana o se pierde por la
  basura entregada; el castigo empuja el puntaje y se ve en el resultado.

## Ajustes de jugabilidad (post Fase 2)

- **Agarre por cercanía**: radio de 1,45 celdas alrededor del jugador; lo de
  adelante tiene prioridad. Antes había que estar mirando la celda exacta.
- **Giro diagonal real**: el cuerpo mira a la dirección de movimiento; `facing`
  (eje dominante) queda solo para las interacciones.
- **Mapa con props**: palmeras, sombrillas con toalla, torre del guardavidas y
  muelle. Los grandes bloquean y reservan su celda para el spawner.

## Fase 3 — Mar y tiburón — ✅ HECHA

| # | Paso | Estado |
|---|---|---|
| 3.1 | Zona de agua transitable con profundidad | ✅ |
| 3.2 | Aleta a los 3 s, mordida a los 6 s y 5 s para reaparecer (sin puntos) | ✅ |
| 3.3 | Basura flotante que vale más | ✅ suma doble a la cuota |

Decisiones de implementación:

- **El agua tiene piso en otra capa** (capa 4): sostiene la basura flotante pero
  no al jugador, así se nada sin que un escalón invisible frene el paso.
- **Nadar es más lento** (2,5 contra 4,6) y el impulso en el agua es más corto
  (4,2 contra 9,2): entrar al mar es una decisión, no un atajo.
- **La animación de nado** es postura (el cuerpo se acuesta con el sombrero
  adelante) + estela de espuma + salpicaduras al avanzar. Las brazadas existen,
  pero el ala del sombrero tapa los hombros desde la cámara alta: lo que se lee
  es la postura y la estela.
- **El tiburón corre por jugador**: cada uno tiene su reloj de agua, así en co-op
  uno puede cubrir la orilla mientras el otro nada.
- **La basura del mar suma doble a la cuota** (no solo puntos): si no, el riesgo
  de nadar no se pagaba en la condición de victoria.
- **La mordida no destruye lo que llevabas**: lo deja en la orilla.
- **Las penalizaciones son solo de puntos**: la mordida del tiburón no descuenta,
  cuesta 5 s de espera; el contenedor equivocado no castiga, solo rechaza.
- **El tiburón es un modelo**: sale del agua, se abalanza y se hunde; la mordida
  deja una cuenta atrás en pantalla y se reaparece en el spawn del nivel.
- **El personaje nada parado** (flotando), no acostado: acostado se hundía la
  cara en un agua de 30 cm.
- **El tiburón se calienta**: cuanto más tiempo seguís en el agua, antes aparece
  la aleta y antes muerde (hasta la mitad del tiempo). Después de una mordida
  arranca más caliente todavía.

## Fase 4 — Mundo y vida

| # | Paso |
|---|---|
| 4.1 | NPCs que caminan a la orilla y tiran basura (visual) |
| 4.2 | Nivel bosque con río (mismos sistemas, otros datos) |
| 4.3 | Luz que va de mañana a atardecer según el reloj |

## Assets

### HUD (2D)
- **Íconos**: botella PET, botella de vidrio, lata, reloj/reloj de arena, aleta,
  gaviota, bolsa. Formato SVG → PNG 128 px.
- **Cómo**: se le piden los SVG a **Qwen** (como pediste) y se rasterizan; si la
  sesión no está disponible, se generan proceduralmente con Python/PIL (el
  proyecto ya es "assets básicos/procedurales").

### 3D
Todo con el mismo pipeline `tools/gen_*.py` (Blender headless, primitivas +
`lathe`), para que combine con el personaje:
- `gen_props.py`: contenedor (3 variantes de color/tapa), bolsa, botella, lata,
  bolsa de basura, gaviota, aleta de tiburón, NPC (variante del chef con gorra).
- Estilo: mismo contorno negro por casco invertido que el personaje.
