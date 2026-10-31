# Playa Limpia — plan roguelike

Decisiones tomadas: run de **7 días** con opción de **seguir infinito en la misma
seed**, **mapa procedural** por run y **conchas** que se cambian por desbloqueos
permanentes.

## Hecho ya

- `scripts/pixel.gd`: fuente 5x7 dibujada píxel a píxel (sin fuentes del
  sistema) + paleta + paneles e íconos.
- `scripts/ui_home.gd`: pantalla de inicio pixel art con los dos personajes
  (retratos renderizados del modelo real) y **tienda de conchas**. La jugadora 2
  arranca **bloqueada en negro** con candado y precio; al comprarla se juega en
  cooperativo.
- `scripts/save_game.gd`: conchas, desbloqueos y récords en
  `user://playa_save.cfg`. Se ganan 3 conchas por día (+2 si sobra más de 1 min).

## El bucle

```
MENÚ (elegir 1 o 2 jugadores)
  └─ nueva run: seed aleatoria → playa generada
       DÍA 1 … DÍA 7 (o hasta fallar)
         jugar la jornada (cuota + reloj)
         si cuota cumplida → elegir 1 de 3 CARTAS → siguiente día
         si NO → fin de la run (se cobran las conchas)
       al día 7: "seguir en la misma seed" (infinito, la cuota sigue subiendo)
  └─ conchas → desbloqueos permanentes (save en disco)
```

## Días

`d` = día (0-based). Todo sale de `(seed, d)`:

| Qué | Fórmula |
|---|---|
| ancho del mapa | `22 + rand(0,2) + min(d,3)` |
| filas de arena | `7 + rand(0,2)` |
| cuota por tipo | `base × 1.28^d` (base = 6/4/4) |
| intervalo de basura | `max(1.4, 3.6 × 0.92^d)` |
| basura en el agua | `min(0.45, 0.08 × d)` |
| NPCs | `min(3, 1 + d/2)` |
| modificador | 1 de 8, elegido con la seed |

## Generador de playa (`scripts/beach_gen.gd`)

Marco fijo: fila 0 = muro de rocas, fila 1 = paseo (estaciones), arena en el
medio, `SEA_ROWS = 3` filas de mar abajo.

1. **Orilla ondulada**: `shore_y(x) = 1 + arena − 1 − max(0, round(amp·sin(x·f + φ)))`
   con `amp ∈ 0..2`, siempre dejando ≥ 5 filas de arena por columna.
2. **Estaciones en el paseo**: tres grupos (dispensador de 1, contenedores de 3,
   camión de 2-3) en **orden aleatorio**, separados por huecos de 1-5 celdas
   (repartiendo el espacio que sobra).
3. **Spawns**: 2 celdas de arena en la mitad de abajo, separadas ≥ 4.
4. **Decorado**: 3 palmeras (preferentemente los costados), 2 pares
   sombrilla+reposera, 1 torre cerca de la orilla, 1 muelle en una columna al
   azar y 4 detalles chicos. Todo con distancia mínima entre sí, de los spawns y
   de las estaciones.
5. **Validación** (si falla, se reintenta con otra sub-seed; a los 12 intentos
   cae al mapa hecho a mano):
   - BFS desde el spawn: todos los spawns, el dispensador, los tres contenedores
     y **todas** las celdas del camión tienen que ser alcanzables.
   - ≥ 35 celdas de arena libres (para que caiga basura).
   - El camión es un tramo contiguo (por construcción) y su fila de adelante es
     caminable.

## Cartas (se apilan toda la run)

| Carta | Efecto | Rareza |
|---|---|---|
| Sandalias de goma | +12 % velocidad | común |
| Guantes de trabajo | bolsa +1 | común |
| Carrito | +1 slot para llevar residuos | rara |
| Repelente | el tiburón tarda 40 % más | común |
| Comederos | las gaviotas se van solas | rara |
| Reciclador experto | +50 % puntos | rara |
| Reloj de arena | +15 s por día | común |
| Sombra extra | la basura del sol aguanta más | común |
| **Marea negra** (maldita) | cuota −15 %, +1 gaviota permanente | maldita |

3 cartas por día (4 con el desbloqueo), elegidas al azar sin repetir las ya
tomadas. Se aplican como multiplicadores/acumuladores en un `Stats` que leen
jugadores, spawner, gaviotas y cuota.

## Conchas y desbloqueos

- 3 conchas por día completado, +2 extra si el día se cerró con ≥ 60 s de sobra.
- Desbloqueos: 4.ª carta en la oferta (10), empezar con una carta elegida (25),
  pool raro (40), **modelo de la jugadora 2** (15), dificultad + (50).
- Save: `user://playa_save.cfg` → conchas, desbloqueos, mejor día, runs jugadas.

## Fases

| # | Qué | Estado |
|---|---|---|
| 0 | `RunState` (autoload) + save/load + tests | parcial: `SaveGame` (conchas, desbloqueos, récords) + tests |
| 1 | `BeachGen` + validador + tests (seeds × días) | **en curso** |
| 2 | Enchufar el generador en `GridWorld`/`Levels` (decor y muelle variables) | pendiente |
| 3 | Cartas + `Stats` + pantalla de elección | pendiente |
| 4 | Modificadores diarios | pendiente |
| 5 | Conchas, desbloqueos y pantalla de progreso | **UI hecha**: menú pixel art con personajes y tienda; faltan cartas en la oferta |
| 6 | Continuar infinito + curva de dificultad + balance | pendiente |
