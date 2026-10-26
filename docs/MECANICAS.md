# Mecánicas (rediseño 2026-10-26)

Se cambiaron para que la lógica cierre con la vida real y no bloquee al jugador.

## Circuito

1. **Montón** (PET / LATAS / VIDRIO) → tomás un residuo.
2. **Contenedor** (uno por tipo, coloreado y rotulado) → tirás el residuo.
   - correcto: `+4` puntos y el residuo desaparece (es "clasificar", pero de
     verdad: va al contenedor que corresponde).
   - equivocado: no entra, queda en la mano y penaliza.
3. **Dispensador de bolsas** → bolsa limpia (stock finito).
4. **Mostrador** → dejás un residuo, dejás la bolsa, y los fusionás.
5. **Lavadero** (pila de 3 + repisa de 3) → dejás las bolsas sucias y se lavan
   **solas** cada `WASH_TIME`; las limpias quedan apiladas en la repisa y las
   retirás cuando quieras. Ya no te quedás bloqueado lavando.
6. **Camión** → entregás la bolsa con los residuos que pide el pedido.

## Gaviotas

Aparecen cada ~18 s y **roban una bolsa limpia de la repisa** del lavadero (o un
residuo tirado en el piso), la ensucian y la tiran en la arena: hay que volver a
lavarla. Es la presión para no dejar todo acumulado.

## Colisiones

- Todas las celdas sólidas llevan una **pared invisible de 2 m**: con la altura
  real (0.55–0.95) la cápsula del jugador se trepaba al borde y quedaba "encima
  de todo".
- El jugador queda siempre a nivel del piso y **clavado dentro del mapa**.
- Un ítem en el piso tiene collider propio: no se lo atraviesa.
- El agua es sólida y ahora se ve (antes era una pared invisible).
