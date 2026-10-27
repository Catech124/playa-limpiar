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

| Jugadores | Primera gaviota | Después, cada |
|---|---|---|
| 1 | 55 s | 50 s |
| 2 | 30 s | 34 s |

Con un solo jugador aparecen mucho más espaciadas a propósito: mientras se
embolsa no hay manos para cubrir la playa, y con el ritmo anterior ganarle a una
gaviota era cuestión de suerte. Con dos, uno embolsa cerca del contenedor y el
otro barre la arena, así que la presión puede ser mayor.

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

Fase 2 (presión): basura que se hunde, vidrio que se rompe, castigo de la
gaviota y tope de 3 castigos por minuto.
Fase 3 (mar): agua transitable, aleta, tiburón.
Fase 4 (mundo): NPCs que tiran basura, nivel bosque.
