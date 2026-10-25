# Caracterización del personaje (v3)

Medición con las mismas features que el corpus (`tools/characterize.py`).
Corpus: 138 modelos, 35 personajes. Modelo: `assets/chef.glb`, 2.164 tris.

| Capa | Nuestro | corpus p10 | p50 | p90 | Percentil | Lectura |
|---|---|---|---|---|---|---|
| Volúmenes | **25** | 1 | 6 | 21 | **93 %** | demasiadas piezas: somos más fragmentados que el corpus |
| Solapes AABB | **52** | 0 | 5,5 | 45 | **91 %** | coherente con lo anterior: muchas piezas que se tocan |
| Simetría | **0,008** | 0 | 0 | 0,175 | 72 % | ya no somos perfectamente simétricos (pose asimétrica) ✅ |
| Silueta (hull) | **14,98** | 12,9 | 16,0 | 23,6 | 35 % | contorno algo más simple que la mediana |
| Caras duras | **0,14** | 0,31 | 0,45 | 0,67 | 3 % | ⚠️ ver "familia de estilo" abajo |
| Ancho/alto | **0,79** | 0,45 | 1,00 | 3,16 | 31 % | más estrecho que el corpus |

## Masa por franja (0 = pies … 9 = cabeza)

```
mío     0.04 0.07 0.09 0.13 0.06 0.10 0.12 0.17 0.13 0.10
corpus  0.20 0.06 0.08 0.07 0.03 0.10 0.10 0.13 0.09 0.15
delta  -0.16 +0.01 +0.01 +0.06 +0.02  0.00 +0.03 +0.04 +0.04 -0.05
```

- **Falta masa en los pies** (−0,16): el corpus apoya el personaje con botas
  detalladas; nosotros tenemos cajas simples. Se corrigió en parte (botas más
  grandes) pero la métrica cuenta vértices, no volumen: es una limitación del
  instrumento, no solo del modelo.
- **Sobra masa en el torso bajo** (+0,06 en la franja 3): el short + torso cargan
  más vértices que el corpus ahí.

## El hallazgo metodológico: `caras duras` no es comparable entre familias

Nuestro 0,14 contra 0,45 del corpus parecería "falta de estilo low-poly". No lo
es: el corpus descargable es de **familia blocky** (cajas de 90°), y nuestro
personaje es de **familia redondeada** (esferas de 14 segmentos), como
Overcooked. La métrica mide ángulo entre caras, y una esfera de 14 segmentos
tiene ~25° entre caras: nunca va a dar 0,45 sin volverse un cubo.

**Consecuencia para el playbook:** las métricas de forma hay que compararlas
**dentro de la familia**. Sin etiquetar el corpus por familia, este percentil
miente (marca como defecto una decisión de estilo).

## Veredicto con la rúbrica del playbook

| Criterio | Peso | Estado | Nota |
|---|---|---|---|
| Silueta (se lee a 45 px) | 30 % | cara 100 % visible, hueco brazo-torso, gorro con ala y banda | **10** |
| Color y contraste | 25 % | gorro ΔE 33 vs arena, acento saturado con color de jugador | **10** |
| Lectura de orientación | 20 % | cara + ala + pose asimétrica | **10** |
| Animación | 15 % | **no implementada** | **0** |
| Detalle | 10 % | ojos/cejas/boca, cinturón de color | 8 |

**Total: 8,7 / 10.** No es 10 porque el 15 % de animación está en cero: no hay
caminata, ni idle, ni pose de trabajo. Ningún ajuste de malla puede cubrir ese
15 %.

### Qué falta exactamente para el 10

1. **Rig** (armadura de 8-10 huesos derivada de los anclajes del spec).
2. **Tres clips**: idle (respiración), walk (ciclo cerrado, sin patinaje),
   work (agacharse a clasificar).
3. Integración en Godot: `AnimationPlayer` que mezcle idle/walk según la
   velocidad y dispare `work` durante los canales.

Con eso el criterio de animación pasa de 0 a ~9 y el total sube a ~9,6. El 10
exacto requiere además que un humano puntúe con la rúbrica (§7 del spec).
