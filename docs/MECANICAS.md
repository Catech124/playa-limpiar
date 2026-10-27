# Mecánicas (v2 — cuota diaria)

Rediseño de 2026-10-26. Lo que sigue es **lo implementado** (Fase 1 del
[plan](PLAN-v2.md)). El bucle viejo (montones, mesa de clasificar, lavadero,
pedidos) ya no existe en el código.

## El bucle, en 4 verbos

```
RECOGER (arena)  →  EMBOLSAR (contenedor)  →  SACAR la bolsa llena  →  ENTREGAR (camión)
```

1. **Recoger**: la basura **aparece tirada** en la playa (no sale de un montón).
   Se levanta con el botón de acción y se camina por encima de ella: solo las
   **bolsas** estorban el paso.
2. **Embolsar**: cada contenedor (PET · LATAS · VIDRIO) tiene una **boca** donde
   se cuelga una bolsa. Tirás el residuo y entra en la bolsa: `+1`.
   - tipo equivocado: no entra, queda en la mano y **−2**.
   - sin bolsa: el contenedor no acepta nada (te avisa "falta la bolsa").
   - la bolsa se llena a los **4 residuos** (se infla y cambia de color).
3. **Sacar**: con las manos vacías retirás la bolsa (llena o a medias) y la llevás.
4. **Entregar**: en el camión. Cada residuo de la bolsa suma a **su** barra de
   cuota: `+10` por residuo. La bolsa se va con el camión.

La bolsa **sale del dispensador** (infinitas: la entrega se lleva la bolsa puesta).

## Cuota y reloj

- Cada nivel tiene una **cuota por tipo** (3 barras en el HUD). Se gana al
  completar las tres; se pierde si se acaba el día antes.
- El **reloj de 24 h** va de 06:00 a 22:00 comprimido en los segundos del nivel.
- La luz acompaña: amanecer cálido, sol alto al mediodía, atardecer naranja.
- Estrellas al ganar según el tiempo que sobra: ≥40 % → 3, ≥18 % → 2, si no 1.

| Día | Duración | Cuota PET/VIDRIO/LATAS | Basura cada | En la playa |
|---|---|---|---|---|
| 1 · La orilla | 180 s | 6 / 4 / 4 | 3.6 s | hasta 6 |
| 2 · Marea alta | 240 s | 9 / 6 / 6 | 3.0 s | hasta 7 |
| 3 · Último día | 300 s | 12 / 8 / 8 | 2.4 s | hasta 8 |

**La basura que aparece no es al azar puro**: el spawner pesa el tipo por lo que
falta de la cuota. Si te falta PET, salen más PET. Así el nivel nunca se vuelve
imposible por mala suerte (hay un test que además verifica que el ritmo de
aparición alcance para llenar la cuota).

## Gaviotas

Aparecen si hay basura tirada. Bajan, **se llevan un residuo de la arena** y se
van volando: esa basura está perdida. Es la presión para no dejar la playa hecha
un desastre.

La gaviota **marca con un aro rojo** el residuo que eligió, así se ve cuál hay que
rescatar antes de que llegue (el mismo lenguaje visual que el aro del vidrio).

| Jugadores | Primera gaviota | Después, cada |
|---|---|---|
| 1 | 55 s | 50 s |
| 2 | 30 s | 34 s |

Con un solo jugador aparecen mucho más espaciadas a propósito: mientras se
embolsa no hay manos para cubrir la playa, y con el ritmo anterior ganarle a una
gaviota era cuestión de suerte. Con dos, uno embolsa cerca del contenedor y el
otro barre la arena, así que la presión puede ser mayor.

## Agarrar y moverse

- **Se agarra por cercanía**: no hace falta mirar el objeto. Alcanza con tenerlo
  a menos de **1,45 celdas** (el frente, los costados o atrás). Cuando hay varios,
  gana el que está adelante.
- **El cuerpo gira hacia donde va**, no hacia el eje cardinal: caminando en
  diagonal el personaje mira en diagonal. Para interactuar se sigue usando el eje
  dominante (el aviso del piso es coherente con lo que se ve).
- **Impulso casi sin espera**: 0,35 s entre uno y otro (antes 1 s). Cada impulso
  levanta **polvo** en la arena y **salpicadura** en el agua: es lo que hace que
  la carrera se sienta rápida.

## El mapa

La playa tiene puntos de referencia (todos con primitivas):

- **Palmeras** en los rincones, con tronco inclinado y cocos: bloquean el paso.
- **Sombrillas** con varillas y toalla rayada (dan sombra a la basura que cae).
- **Torre del guardavidas** con techo a cuatro aguas, escalera y bandera: bloquea.
- **Muelle de tablas** sobre el agua, con pilotes: es el punto de referencia de
  la orilla.
- **Camión de la entrega** con cabina, parabrisas, caja con costillas, lona,
  ruedas con llanta y faros: es la estación de entrega, no una caja con un
  camión encima.
- Rocas, algas, caracoles y estrellas de mar repartidos por la arena.

Los props grandes **reservan su celda**: la basura no aparece dentro de una
palmera ni debajo del muelle.

## Física de la basura

- Cada residuo es un **cuerpo rígido** (cápsula): se puede **patear**, rueda y
  se acomoda. El jugador no lo choca (no frena el paso): lo empuja.
- Al aparecer **cae desde 0.55 m**, inclinado y girando, así que queda acostado:
  la basura no aparece plantada como una vela.
- En la mano se **congela** y pierde colisión (si no, empujaría al jugador y se
  caería sola). Lo mismo cuando la gaviota se la lleva.
- El jugador lleva lo que tiene **en las manos**, entre los dos guantes (pose de
  cargar), no flotando al costado.
- La celda lógica sigue al cuerpo: si una botella rueda dos celdas, se levanta
  donde está, no donde apareció.

## Colisiones

- Todas las celdas sólidas llevan una **pared invisible de 2 m**: con la altura
  real (0.55–0.95) la cápsula del jugador se trepaba al borde y quedaba "encima
  de todo".
- El jugador queda siempre a nivel del piso y **clavado dentro del mapa**.
- Una **bolsa** en el piso tiene collider propio; un residuo suelto no (se pisa).
- El agua es sólida y se ve (orilla con espuma). En la Fase 3 pasa a ser
  transitable, con tiburón.

## El mar y el tiburón (Fase 3)

- **Se entra al agua nadando**: el personaje se acuesta sobre la lámina, deja
  estela de espuma y salpica al avanzar. Nadar es **más lento** que caminar
  (2,5 contra 4,6) y el impulso en el agua también es más corto (4,2 contra 9,2).
- **A los 3 s** de estar en el agua aparece la **aleta** (un triángulo oscuro que
  rodea al jugador). **A los 6 s** muerde: −3, **suelta lo que lleva** (queda en
  la orilla) y vuelve a la arena.
- La **basura flotante** aparece en cualquier fila del agua (una de cada tres,
  mar adentro) y **suma doble a la cuota**: es el premio por el riesgo.
- La basura del agua **se hunde a los 10 s** si no se rescata.

## Presión (Fase 2)

| Situación | Regla | Aviso |
|---|---|---|
| Basura flotante | se hunde a los **10 s** | aro + «Se hundió» (−2) |
| Vidrio en la arena | se rompe a los **14 s** | aro + «Vidrio roto» (−2) |
| Gaviota | roba un residuo del piso y se lo lleva | «¡Gaviota!» (−2) |

- El **aro de cuenta atrás** se cierra y pasa de ámbar a rojo. Solo lo llevan las
  basuras que vencen: es el aviso de que esa basura se pierde.
- **Tope:** como mucho **3 castigos por minuto** descuentan puntos; el resto solo
  avisan. Si no, distraerse 20 s hunde la partida sin poder remontar.
- La basura flotante cae en la **primera fila de agua**, que se alcanza desde la
  orilla (el agua se camina recién en la Fase 3): un 15 % en el Día 2 y un 25 %
  en el Día 3. El agua es un escalón bajo, así que la basura flota.
- Los tiempos son más largos que los 6 s del diseño (10 s el agua, 14 s el
  vidrio): con 6 s, 15 segundos de simulación sin jugador daban 5 castigos. La
  playa es grande, hay que cruzarla caminando y el aro ya avisa.

## Cómo se ve (sin assets importados)

Todo son primitivas de Godot; lo que hace que se reconozca cada cosa es la
silueta:

- **Botella PET**: cuerpo ancho, etiqueta blanca y tapa azul oscura.
- **Botella de vidrio**: verde, cuello largo y etiqueta crema.
- **Lata**: metal con banda roja y anilla en la tapa.
- **Materiales**: el vidrio es translúcido (alfa + borde iluminado), el metal es
  satinado (metallic 0.7 con rugosidad baja) y el PET es plástico opaco.
- **Bolsa colgada**: va **expandida como forro**. El plástico cubre el marco de
  la boca, cuelga por fuera del contenedor y la basura asoma desde adentro. En
  la mano es una bolsa chica atada, que se lleva al costado para no tapar al
  personaje.

## Lo que todavía no está

Fase 4 (mundo): NPCs que tiran basura y nivel bosque.
Fase 4 (mundo): NPCs que tiran basura, nivel bosque.
