# Referencia medida → parámetros del personaje

Este documento existe porque el modelado se hacía "a ojo" y el modelo no se
parecía a la lámina. Ahora cada proporción sale de **medir la lámina** y se
verifica con los mismos números sobre el render.

## 1. Medición de la lámina

Script: `tools/ref_metrics.py` (clasifica por color y mide la silueta).

```bash
python3 tools/ref_metrics.py --img docs/referencia.png --crop 40,80,305,470 --label REF
python3 tools/ref_metrics.py --img /tmp/opencode/views/frente.png --label MIO
```

Valores de la lámina (fracciones de la altura total del personaje, H):

| Medida | Referencia | Modelo (antes) | Modelo (ahora) |
|---|---|---|---|
| Ancho del ala | 0.608 | 0.384 | 0.590 |
| Ancho de cabeza (con orejas) | 0.561 | 0.245 | 0.546 |
| Envergadura de brazos (T-pose) | 0.701 | 0.331 | 0.727 |
| Ancho del torso | 0.259 | 0.369 | 0.262 |
| Ancho de piernas | 0.225 | 0.230 | 0.251 |
| Alto de la camiseta | 0.193 | 0.256 | 0.190 |
| Alto del pantalón | 0.239 | 0.279 | 0.240 |

Bandas verticales de la lámina: gorro 0–14.5 %, cabeza 14.5–56.6 %
(ojos 28.8 %, cejas 24.9 %, nariz 34 %, boca 39.4 %), camiseta 55.6–74.9 %,
pantalón 75.7–99.7 %.

## 2. Medidas de detalle tomadas de la lámina

- **Cabeza**: 0.74 de ancho × 0.57 de alto (más ancha que alta), con
  mandíbula que se angosta hacia el mentón y frente que se angosta hacia
  arriba (huevo, no óvalo).
- **Orejas**: 0.17 de alto, a la altura de los ojos, saliendo ~0.05 del cráneo.
- **Ojos**: diámetro ≈ 12 % del ancho de cabeza, separados 2.4 diámetros.
- **Nariz**: cuña de 4.2 % de H de ancho, con volumen (no un punto).
- **Boca**: "ω" de dos arcos chicos, justo bajo la nariz.
- **Gorro**: copa 0.56 del radio de cabeza de ancho, ala ≈ 1 radio de cabeza,
  cinta **rosa-malva** (`#B98683`, no marrón), ala gruesa con el borde
  redondeado y caída en los costados (silla de montar).
- **Camiseta**: cuello bajo, hombros que bajan, manga corta que cae un poco.
- **Pantalón**: holgado, con ruedo sobre la zapatilla.
- **Paleta**: piel `#E39F7C`, camiseta `#F2D14F`, pantalón `#3B4166`,
  paja `#DDBE86`, guantes/zapatillas `#F2F2EE`.

## 3. Cómo se construye ahora

- `lathe()` — superficie de revolución desde un perfil `[(r, z), ...]`. El
  gorro y la camiseta son UN perfil continuo, no primitivas pegadas.
- `head_point()` — ancla cada detalle de la cara sobre el elipsoide craneal,
  así no quedan flotando (era el defecto principal del modelo anterior).
- `pose` — `"t"` reproduce la lámina (hoja de turnaround) y `"down"` es la
  pose jugable con los brazos caídos. El juego usa `chef_game.glb`.

## 4. Reproducir

```bash
# ambas poses en una corrida
cat > /tmp/two.json <<'EOF'
{ "base": {}, "variants": [ { "id": "chef",      "body": { "pose": "t" } },
                            { "id": "chef_game", "body": { "pose": "down" } } ] }
EOF
xvfb-run -a blender --background --python tools/gen_chef.py -- --sweep /tmp/two.json --out /tmp/tv --export
cp /tmp/tv/chef_game.glb assets/chef.glb     # el juego
godot --headless --path . --import && godot --headless --path . -- --test
```

Imágenes de control: `docs/referencia.png` (lámina), `docs/modelo-4vistas.png`
(turnaround propio con la misma pose) y `docs/modelo-en-juego.png`.
