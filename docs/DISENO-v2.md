# Diseño — "Playa Limpia" v2 (propuesta, 2026-10-26)

> Esto es para discutir, no está implementado.

## 1. El bucle, en 4 verbos

```
RECOGER (playa o agua) → LLEVAR (al contenedor) → EMBOLSAR (cuando se llena) → ENTREGAR (camión)
```

Eso es todo. Cada verbo tiene un solo botón contextual (el que ya existe) y cada
uno tiene un feedback claro: el ítem se achica/crece, suena, sale un toast.

## 2. Contenedores: ¿llenar y luego embolsar, o bolsa primero?

**Recomiendo bolsa primero.** Es más fácil de animar y se lee mejor:

1. Tomás una bolsa del dispensador.
2. La dejás en la boca del contenedor (la bolsa queda colgada, se hunde un poco).
3. Cada residuo que tirás **entra en la bolsa** y la bolsa se infla (una sola
   animación: escala + un balanceo).
4. Cuando la bolsa tiene N residuos se marca "LLENA" (cambio de color) y la
   llevás al camión. Ponés otra.

Por qué esta y no la otra:
- La alternativa (llenar el contenedor y después vaciarlo en la bolsa) necesita
  **dos** estados y **dos** animaciones (llenar + vaciar) y deja al jugador
  esperando 2 s mirando una barra.
- Con bolsa primero el jugador nunca espera: tirás y seguís.
- Desventaja: si no hay bolsa, el contenedor no acepta nada → hay que ir a
  buscarla. Eso **es** el ritmo que buscás (ida y vuelta), no un castigo.

## 3. Cuota: por tipo (recomendado) o general

**Por tipo, 3 barras** (PET / VIDRIO / LATAS):

- justifica que haya exactamente 3 contenedores;
- enseña el reciclaje sin un verbo raro de "clasificar";
- el HUD tiene algo lindo: 3 íconos con contador que se llenan;
- evita la estrategia degenerada de "junto todo y ya".

Una barra **general** la dejaría como objetivo secundario/bonus ("+50 pts si
entregás 20 en total"), no como meta del nivel.

## 4. Duración y reloj

Overcooked: cada turno dura ~3–4 minutos. Con penalizaciones activas, 10 min se
hace largo y castiga. **Recomiendo 4 minutos** para el nivel de playa:

| Nivel | Duración | Cuota (PET/VIDRIO/LATAS) | Spawn |
|---|---|---|---|
| 1 (tutorial) | 3:00 | 6 / 4 / 4 | lento |
| 2 | 4:00 | 9 / 6 / 6 | normal |
| 3 (final) | 5:00 | 12 / 8 / 8 | rápido + NPCs |

Reloj de 24 h comprimido: **1 s real = 6 min de juego** (24 h / 4 min). El HUD
muestra `14:30` y un arco sol/luna. Se puede usar el `DirectionalLight3D` que ya
existe para que el nivel pase de mañana a atardecer: es gratis y da urgencia.

## 5. Penalizaciones (todas −2 y con motivo visible)

| Situación | Regla | Feedback |
|---|---|---|
| Basura en el mar | se hunde a los **6 s** | burbujas + "Se hundió" |
| Gaviota | roba un ítem del piso o de la bolsa | "¡Gaviota!" + se lo lleva volando |
| Vidrio en la arena | a los **6 s** un NPC lo pisa y se rompe | "Vidrio roto" |
| Basura sin recoger | el ítem tiene un aro que se cierra | aro rojo + tic-tac |

**Tope de castigo:** como máximo 3 penalizaciones por minuto cuentan (después
solo avisan). Si no, un jugador que se distrae 20 s pierde la partida sin poder
remontar.

## 6. Mar y tiburón

- Se puede entrar al agua (hasta cierta profundidad) a buscar basura flotante.
- **3 s en el agua:** aparece la aleta + aviso.
- **6 s:** mordida → −3, te devuelve a la arena y soltás lo que llevabas.
- El tiburón no necesita IA: nada en línea recta hacia el jugador y desaparece.

Esto convierte "entrar al agua" en una decisión: la basura del agua vale más
(+2 por ítem) porque el riesgo es real.

## 7. NPCs

2–3 NPCs de fondo con un loop simple (caminan a la orilla, tiran basura, vuelven).
No interactúan con el jugador: son **la fuente visible** de la basura. La basura
aparece en un radio cerca de ellos, no en el aire.

## 8. Mundos

Todo data-driven en `levels.gd`: `world`, `spawn_table`, `quota`, `duration`,
`hazards`. Playa (mar/tiburón) y bosque (río/serpiente o barranco) comparten el
bucle y cambian solo los datos y la paleta.

## 9. Qué se queda y qué se va

**Se queda:** grilla y colliders, cámara de cooperativo, personaje y animaciones,
bolsas (`CarryItem`), gaviotas, contorno, HUD base.

**Se va:** montones (`pile`), mesas de clasificar (`sort`), lavadero y bolsas
sucias (`wash`), sistema de pedidos por cliente (`OrderBook`).

**Se transforma:** los 3 contenedores actuales pasan a ser los receptáculos de
bolsa; el camión pasa a ser la entrega de cuota.

## 10. Preguntas para decidir antes de implementar

1. **Duración:** ¿4 min (recomendado) o te gusta más 5–10?
2. **Bolsa:** ¿bolsa primero (recomendado) o contenedor primero?
3. **Cuota:** ¿por tipo (recomendado) o general?
4. **Agua:** ¿se puede entrar a buscar basura flotante (recomendado) o solo
   desde la orilla con un rastrillo?
5. **Vidrio roto:** ¿desaparece (simple) o queda un charco de vidrio que hay que
   barrer (más profundo)?
6. **Cooperativo:** ¿se mantiene 2 jugadores (la cámara ya lo soporta)?
