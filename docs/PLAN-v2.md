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

## Fase 2 — Presión

| # | Paso |
|---|---|
| 2.1 | Basura que se hunde en el mar a los 6 s (−2) |
| 2.2 | Vidrio que se rompe a los 6 s en la arena (−2) |
| 2.3 | Gaviota que roba basura del piso o de la bolsa (−2) |
| 2.4 | Aro de cuenta regresiva sobre cada basura + tope de 3 castigos/min |

## Fase 3 — Mar y tiburón

| # | Paso |
|---|---|
| 3.1 | Zona de agua transitable (orilla) con profundidad |
| 3.2 | Aleta a los 3 s, mordida a los 6 s (−3 y te devuelve a la arena) |
| 3.3 | Basura flotante que vale +2 |

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
