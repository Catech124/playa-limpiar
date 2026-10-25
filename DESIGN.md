# Diseño — Playa Limpia (prototipo 3D, v0.1)

Documento de mecánicas. La pregunta que responde no es "¿cómo está programado
Overcooked 2?" sino **"¿qué piezas producen la sensación de caos cooperativo, y
cómo se traducen a recoger basura en una playa en 3D?"**.

---

## 1. Método: ingeniería inversa sin tocar el binario

Overcooked 2 es un juego cerrado; no se inspeccionó el ejecutable ni los assets.
El modelo se reconstruyó con fuentes públicas y observación del comportamiento:

- **Diseño declarado por el estudio** (Ghost Town Games): el *deep dive* de
  Overcooked explica las tres palancas del original — reparto de tareas, demoras
  (ollas que tardan, platos que vuelven sucios) y un **reloj con objetivo**
  (pasar de "entregá pedidos" a "entregá la mayor cantidad en X minutos").
- **Entrevistas de la secuela**: el lanzamiento de ítems nace de un problema de
  diseño concreto (niveles que separaban a los jugadores y los dejaban sin tareas
  alcanzables).
- **Análisis de crítica y wikis de niveles**: tiempos de ronda (3:00–4:00),
  recetas, umbrales de estrellas, obstáculos (cintas, plataformas móviles).
- **Observación del juego**: qué interacción gana cuando dos son válidas, cómo se
  encola el trabajo, qué se puede lanzar y qué no.

Lo que se extrae no es el código: es el **contrato de mecánicas** —qué decide el
jugador, qué relojes lo presionan y qué geometría lo obliga a coordinarse.

---

## 2. Anatomía de Overcooked (modelo reconstruido)

Cada pieza tiene una función. La columna derecha es la prueba de que no es
decorativa: si la quitás, el juego cambia de género.

| Pieza | Función de diseño | Qué pasa si se quita |
|---|---|---|
| **Receta como cadena de estados** (crudo → cortado → cocido → emplatado → servido) | Convierte un objeto en un proceso con pasos | El juego se vuelve "recoger y entregar": sin decisiones |
| **Una mano** (1 ítem por chef) | Fuerza a soltar, turnarse y usar mostradores | Cada jugador cocina solo; desaparece la interdependencia |
| **Mostradores (buffers)** | Memoria espacial del trabajo en curso | Todo el trabajo vive en las manos: no se puede planificar en paralelo |
| **Canales de tiempo** (cortar, lavar: mantener el botón) | Compra tiempo al jugador y lo ancla a un lugar | Si preparar es instantáneo, el reloj no duele |
| **Fuentes separadas** (cajas de ingrediente) | Obligan a viajar y a decidir el orden de las vueltas | Si todo está junto, la cocina no tiene geografía |
| **Sumidero de validación** (mostrador de servir) | El juego comprueba el pedido: no vale "casi" | No hay forma de fallar; desaparece la tensión del último paso |
| **Retorno sucio** (platos que vuelven) | Crea un segundo bucle que compite por la misma atención | Se puede producir sin fin: el juego se vuelve un *idle* |
| **Reloj global + paciencia por comanda** | Fija el ritmo y obliga a **priorizar** | Sin reloj no hay coste de oportunidad; sin paciencia no hay prioridades |
| **Layout con huecos** | La distancia es la que crea la cooperación | Un pasillo único convierte el co-op en "dos personas haciendo lo mismo" |
| **Impulso / lanzar** | Movilidad y alcance a través de huecos | Los mapas separados se vuelven injugables |
| **Peligros** (fuego, ratas) | Castigan la acumulación y el abandono | El jugador óptimo acumula sin riesgo y el juego se aplana |

**Tesis del original:** el núcleo no es cocinar. Es **interdependencia forzada**:
descomposición de tareas + restricción espacial + un reloj compartido.

---

## 3. Traducción a Playa Limpia

| Overcooked 2 | Playa Limpia (3D) | Qué se conserva |
|---|---|---|
| Caja de ingrediente | **Montón por tipo** (PET / latas / vidrio) | Fuente determinista y separada: se puede planificar |
| Tabla + cuchillo (mantener) | **Mesa de clasificar** (canal de 1,2 s) | Trabajo anclado a un lugar con tiempo |
| Plato | **Bolsa** (capacidad 4, stock 5) | Objeto-contenedor que se ensambla y vuelve sucio |
| Ensamblar en el plato | **Meter residuos clasificados en la bolsa** (sobre mostrador) | El buffer espacial es imprescindible |
| Mostrador de servir | **Camión de reciclaje** (valida el pedido) | Validación exacta: no vale "casi" |
| Plato sucio + fregadero | **Bolsa sucia + lavadero** (canal de 1,5 s) | Segundo bucle que compite por atención |
| Ratas | **Gaviotas** que roban residuos clasificados | Castigo a acumular en vez de entregar |
| Olla / quemar | *(pendiente: contenedor de acopio que se desborda)* | — |
| Fuego / extintor | *(pendiente)* | — |
| Cintas / plataformas móviles | *(pendiente: marea / tablones)* | — |

**Decisión clave:** las bolsas son **finitas** (5). Con bolsas infinitas el
lavadero no presiona nada y el bucle de ida y vuelta desaparece; con stock finito,
"entregar" también consume un recurso.

---

## 4. Bucle central

```
   montón ──recoger──▶ mano ──mantener 1,2 s──▶ clasificado ──soltar──▶ mostrador
                                                                            │
                                                   bolsa (capacidad 4) ◀────┘
                                                            │
                                                       llevar
                                                            ▼
                                                   camión (valida)
                                                            │ ✔
                                                            ▼
                                                    bolsa sucia
                                                            │
                                              lavar 1,5 s   ▼
                                                   bolsa limpia (vuelve al stock)
```

En paralelo: pedidos que aparecen, paciencia que baja, puntos que se pierden.

---

## 5. Números del prototipo y por qué

Todo vive en `scripts/config.gd` (una sola tabla) y `scripts/levels.gd` (mapa).

| Parámetro | Valor | Razón |
|---|---|---|
| Ronda | 180 s | Rondas de OC2: 3:00–4:00. Ciclo corto para iterar |
| Velocidad | 4,6 cel/s | Un chef de OC2 cruza la cocina en ~2 s; acá 1 celda = 1 unidad 3D |
| Impulso | 9,0 cel/s · 180 ms · CD 1 s | ~1,6 celdas: alcanza para un hueco, no para cruzar el mapa |
| Clasificar | 1,2 s | El "corte" de OC2 ronda 1–2 s por ítem |
| Lavar | 1,5 s | Debe doler pero menos que clasificar (mantenimiento) |
| Bolsa | cap. 4 | Permite pedidos de hasta 4 residuos sin microgestión |
| Stock de bolsas | 5 | Fuerza el bucle de lavado sin bloquear a un jugador lento |
| Pedidos | 1.º a los 2 s; luego cada 15 s; máx. 3 activos; paciencia 40 s; 1–3 residuos | Ritmo objetivo: ~22 s por comanda |
| Puntos | 30 base + 30 × fracción de paciencia | Entregar temprano paga el doble que al límite |
| Pedido perdido | −15 | Duele, no hunde |
| Estrellas | 160 / 320 / 480 | Provisionales (ver §7) |
| Lanzar | alcance 3,4 cel; 420 ms de vuelo | Sirve para mostradores, no para cruzar el mapa |
| Gaviotas | desde 24 s, luego cada 22 s | Castiga acaparar sin ser constante |

**Circuito del mapa** (24×14 celdas, 1 unidad por celda): montones en la fila 2,
mesas de clasificar en la 4, mostrador de acopio en (12–13, 5–6), camión abajo en
(10–11, 12), bolsas limpias en (9, 2) y lavadero en (14, 2).

---

## 6. Qué está implementado en v0.1 (Godot 3D)

**Sí:**
- Escena 3D con cámara fija en ángulo (estilo Overcooked), luces y sombras.
- Movimiento con colisión, impulso y orientación por eje (interacciones predecibles).
- Acción contextual de una sola tecla + aviso en pantalla de lo que haría.
- Canales de trabajo (clasificar / lavar) con progreso **que no se pierde** al soltar.
- Bolsas con capacidad, fusión sobre mostrador y validación exacta en el camión.
- Bolsas sucias, lavadero y **stock finito** de bolsas.
- Pedidos con cola, paciencia, propina por rapidez y penalización al perder uno.
- Lanzamiento con arco y aterrizaje (con fusión si cae sobre una bolsa).
- Gaviotas que roban residuos clasificados y los tiran en la arena.
- Co-op local de 2 jugadores en el mismo teclado.
- Pausa, reinicio, pantalla de resultados con estrellas y caja de arena de debug.
- 24 comprobaciones automáticas headless + capturas automáticas para revisar arte.

**No (a propósito, para la siguiente iteración):**
- Cocina con temporizador y quemado (el "contenedor de acopio" que se desborda).
- Fuego / extintor.
- Recibir ítems lanzados por otro jugador (catch).
- Cintas, marea, tablones móviles.
- Animación de personajes, sonido, partículas.
- Progresión de niveles y guardado.

---

## 7. Calibración (pendiente de re-medir en 3D)

Los números de §5 vienen de la maqueta de papel/2D previa, donde un bot que jugaba
rondas completas con teclado real medía **~22 s por comanda** (8 entregas, 480
puntos, 0 pedidos perdidos). **En 3D todavía no se re-midió**: el arnés headless
valida reglas, no ritmo.

Cómo recalibrar (en este orden):
1. Jugar 3 rondas y anotar: entregas, pedidos perdidos y en qué momento se
   desborda la cola.
2. Si la cola nunca se llena → subir `ORDER_INTERVAL`/bajar `ORDER_PATIENCE`.
3. Si es imposible llegar → bajar `ORDER_MAX_ITEMS` o acortar el circuito
   (mover el mostrador de acopio hacia las mesas).
4. Mover las estrellas a ~45 % / 70 % / 100 % del puntaje de una buena partida.

Los umbrales actuales (160/320/480) son provisionales hasta ese paso.

---

## 8. Decisiones de diseño tomadas

1. **Montón por tipo, no montón aleatorio.** Un montón que escupe un residuo al
   azar rompe la planificación. En OC2 cada caja da un ingrediente: se copia eso.
2. **Clasificar en la mano (no sobre la mesa).** Se conserva la exigencia
   espacial (hay que ir a la mesa) y se elimina la ambigüedad de "¿esta tecla
   agarra o clasifica?", el principal riesgo de usabilidad.
3. **Bolsa sobre mostrador, no en la mano.** Es el "plato" de OC2 y crea el
   buffer: podés dejar la bolsa a medio llenar e ir por otro residuo.
4. **Stock finito de bolsas.** Convierte el lavado en parte del bucle y no en un
   castigo opcional.
5. **Validación exacta del pedido.** Si la bolsa no coincide, no entra: el último
   paso tiene que poder fallar.
6. **Cámara fija y aviso contextual.** Sin tutorial: el texto sobre el jugador es
   la documentación del juego. La cámara no sigue al jugador porque el jugador
   tiene que poder leer la cocina entera y planificar.
7. **Todo el mapa visible de un vistazo.** Es la razón de que el layout sea ancho
   y no un pasillo: la información espacial es parte del puzzle.

---

## 9. Hoja de ruta de pulido (3D)

- **Fase 2 — presión real:** contenedor de acopio que se desborda (el "quemado"),
  fuego en la arena y extintor; gaviotas en bandada.
- **Fase 3 — co-op de verdad:** recibir ítems lanzados, clasificar en paralelo
  (dos jugadores sobre la misma mesa aceleran) y un nivel con el equipo separado
  por agua, donde lanzar sea obligatorio.
- **Fase 4 — contenido:** más residuos (orgánico, redes, microplásticos), pedidos
  con variantes ("sin vidrio") y marea que sube y tapa celdas.
- **Fase 5 — juice:** animación de caminar/clasificar, sonido por acción,
  partículas, sacudida del camión al entregar, música con capas según el caos.
- **Fase 6 — meta:** mapa de niveles, estrellas por nivel, desbloqueo progresivo.

---

## 10. Preguntas abiertas

- **¿Una mano es suficiente?** Con 1 ítem por jugador el juego es fiel a OC2, pero
  el tema (recolectar) invita a cargar más. Probar "bolsa en la mano + 1 residuo
  en la otra" en la fase 3.
- **¿La penalización por pedido perdido debería ser puntos o bolsas?** Con stock
  finito, castigar con recursos puede ser más temático que restar puntos.
- **¿La cámara fija alcanza en 3D?** Overcooked la usa porque los chefs son
  siempre visibles; acá las estaciones de 0,8 de alto tapan parcialmente al
  jugador cuando está detrás. Si molesta: bajar la altura de las estaciones o
  hacerlas translúcidas cuando hay un jugador detrás.
