"""
Baja personajes 3D de OpenGameArt (CC0 / CC-BY) para romper la correlación
"pack = estilo" del corpus Kenney.

    python3 tools/corpus_fetch_oga.py [--max 25]

Solo acepta licencias CC0 / CC-BY. Anota autor y licencia en corpus/LICENCIAS.md.
Prefiere archivos que se puedan importar sin abrir un .blend (obj/fbx/gltf/glb).
"""

import io
import os
import re
import sys
import urllib.parse
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.join(ROOT, "corpus")
OGA = os.path.join(CORPUS, "oga")

UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) corpus-research/1.0"}
SEARCH = ("https://opengameart.org/art-search-advanced?"
          "keys=character&field_art_type_tid%5B%5D=10&field_art_licenses_tid%5B%5D=4"
          "&field_art_licenses_tid%5B%5D=17981&sort_by=count&sort_order=DESC&page={page}")
# 4 = CC0, 17981 = CC-BY 3.0 (los dos ids que usa OGA)
EXT_OK = (".obj", ".fbx", ".gltf", ".glb")
MODEL_OK = ("obj", "fbx", "gltf", "glb")


def get(url, timeout=90):
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=timeout).read()


def search_slugs(pages=2):
    slugs = []
    for p in range(pages):
        html = get(SEARCH.format(page=p)).decode("utf-8", "ignore")
        for m in re.findall(r'href="/content/([a-z0-9\-]+)"', html):
            if m not in slugs:
                slugs.append(m)
    return slugs


def asset_info(slug):
    url = f"https://opengameart.org/content/{slug}"
    html = get(url, timeout=60).decode("utf-8", "ignore")

    files = sorted(set(re.findall(
        r'https://opengameart\.org/sites/default/files/[^"\']+\.(?:zip|obj|fbx|gltf|glb)', html)))
    lic = "desconocida"
    for pat in ("CC0", r"CC-BY 4\.0", r"CC-BY 3\.0", r"CC-BY-SA 3\.0"):
        if re.search(pat, html, re.I):
            lic = re.sub(r"\s+", " ", re.search(pat, html, re.I).group(0))
            break
    author = ""
    m = re.search(r'Author:\s*<[^>]*>([^<]+)<', html)
    if m:
        author = m.group(1).strip()
    return files, lic, author


def importable(files):
    direct = [f for f in files if f.lower().endswith(EXT_OK)]
    if direct:
        return direct[0]
    zips = [f for f in files if f.lower().endswith(".zip")]
    return zips[0] if zips else None


def main():
    limit = 25
    if "--max" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--max") + 1])

    os.makedirs(OGA, exist_ok=True)
    slugs = search_slugs(2)
    print(f"resultados: {len(slugs)}")

    lines = []
    got = 0
    for slug in slugs:
        if got >= limit:
            break
        try:
            files, lic, author = asset_info(slug)
            if "CC" not in lic:
                continue
            target = importable(files)
            if not target:
                print(f"  - {slug}: sin archivo importable")
                continue

            dest = os.path.join(OGA, slug)
            os.makedirs(dest, exist_ok=True)
            data = get(target, timeout=180)

            if target.lower().endswith(".zip"):
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    names = z.namelist()
                    if not any(n.lower().endswith(EXT_OK + (".blend",)) for n in names):
                        print(f"  - {slug}: zip sin modelos")
                        continue
                    z.extractall(dest)
            else:
                ext = os.path.splitext(target)[1]
                with open(os.path.join(dest, "model" + ext), "wb") as fh:
                    fh.write(data)

            got += 1
            lines.append(f"- **{slug}** — {lic} — autor: {author or 's/d'} — {target}\n")
            print(f"  + {slug} ({lic})")
        except Exception as exc:  # noqa: BLE001
            print(f"  ! {slug}: {exc}")

    with open(os.path.join(CORPUS, "LICENCIAS.md"), "a") as fh:
        fh.write("\n## OpenGameArt\n")
        fh.writelines(lines)
    print(f"\nOK oga={got} en {OGA}")


if __name__ == "__main__":
    main()
