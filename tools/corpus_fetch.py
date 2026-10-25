"""
Baja packs CC0 de Kenney para el corpus de análisis.

    python3 tools/corpus_fetch.py

Hace scraping de la página del pack (el .zip tiene un hash en la URL), descarga,
descomprime en corpus/<slug>/ y anota la licencia en corpus/LICENCIAS.md.

Todo el material es CC0 (Kenney). No se usa ningún asset propietario.
"""

import io
import os
import re
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.join(ROOT, "corpus")

PACKS = [
    "blocky-characters",
    "mini-characters",
    "mini-dungeon",
    "mini-forest",
    "tiny-city",
    "tiny-farm",
    "tiny-factory",
    "mini-skate",
]

UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) corpus-research/1.0"}


def fetch(url, timeout=60):
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=timeout).read()


def zip_url(slug):
    html = fetch(f"https://kenney.nl/assets/{slug}").decode("utf-8", "ignore")
    m = re.findall(r"https://kenney\.nl/media/pages/assets/[^\s\"'>]+\.zip", html)
    return m[0] if m else None


def main():
    os.makedirs(CORPUS, exist_ok=True)
    lines = ["# Corpus — licencias\n", "Todo el material de `corpus/` es **CC0** (Kenney, kenney.nl).\n"]
    total = 0

    for slug in PACKS:
        dest = os.path.join(CORPUS, slug)
        if os.path.isdir(dest) and any(os.scandir(dest)):
            print(f"ya existe: {slug}")
            continue

        url = zip_url(slug)
        if not url:
            print(f"sin zip: {slug}")
            continue

        print(f"bajando {slug} <- {url}")
        data = fetch(url, timeout=180)
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            z.extractall(dest)
            names = z.namelist()

        models = [n for n in names if n.lower().endswith((".glb", ".gltf", ".obj", ".fbx"))]
        total += len(models)
        lines.append(f"- **{slug}** — CC0, {len(models)} archivos de modelo — {url}\n")
        print(f"  {len(models)} modelos, {len(names)} archivos")

    with open(os.path.join(CORPUS, "LICENCIAS.md"), "w") as fh:
        fh.writelines(lines)
    print(f"\nTOTAL modelos: {total}")


main()
