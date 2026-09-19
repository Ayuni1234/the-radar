"""Mirror the live GitHub Pages deployment of The Radar for local debugging."""
import concurrent.futures
import os
import re
import urllib.request

BASE = "https://ayuni1234.github.io/the-radar/"
DEST = "build/live-mirror/the-radar"

# Known Flutter web output files + site metadata.
KNOWN = [
    "index.html",
    "flutter_bootstrap.js",
    "flutter_service_worker.js",
    "flutter.js",
    "main.dart.js",
    "main.dart.mjs",
    "main.dart.wasm",
    "favicon.png",
    "manifest.json",
    "version.json",
    ".last_build_id",
    ".nojekyll",
    "assets/AssetManifest.json",
    "assets/AssetManifest.bin",
    "assets/FontManifest.json",
    "assets/NOTICES",
    "assets/fonts/MaterialIcons-Regular.otf",
    "assets/packages/cupertino_icons/assets/CupertinoIcons.ttf",
]


def fetch(path):
    url = BASE + path
    out = os.path.join(DEST, path.replace("/", os.sep))
    os.makedirs(os.path.dirname(out) or DEST, exist_ok=True)
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            data = r.read()
        with open(out, "wb") as f:
            f.write(data)
        return (path, len(data), None)
    except Exception as e:  # noqa: BLE001
        return (path, 0, str(e))


def main():
    os.makedirs(DEST, exist_ok=True)
    results = {}

    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        for path, size, err in ex.map(fetch, KNOWN):
            results[path] = (size, err)
            mark = "OK " if err is None else f"MISS ({err[:40]})"
            print(f"{mark:8} {path} [{size}]")

    # Follow references found in index.html + asset manifests.
    refs = set()
    idx_path = os.path.join(DEST, "index.html")
    if os.path.exists(idx_path):
        html = open(idx_path, encoding="utf-8", errors="ignore").read()
        refs |= set(re.findall(r'(?:src|href)="([^":]+)"', html))

    for manifest in ("assets/AssetManifest.json", "assets/FontManifest.json"):
        p = os.path.join(DEST, manifest.replace("/", os.sep))
        if os.path.exists(p):
            refs |= set(re.findall(r'"([^"]+\.(?:png|jpg|jpeg|webp|svg|woff2?|ttf|json|bin))"', open(p, encoding="utf-8", errors="ignore").read()))

    refs = {r.lstrip("/") for r in refs if not r.startswith(("http", "data:"))}
    todo = sorted(refs - set(KNOWN))
    if todo:
        print(f"\n-- following {len(todo)} referenced files --")
        with concurrent.futures.ThreadPoolExecutor(8) as ex:
            for path, size, err in ex.map(fetch, todo):
                mark = "OK " if err is None else "MISS"
                print(f"{mark:8} {path} [{size}]")

    total = sum(1 for s, e in results.values() if e is None)
    print(f"\nMirrored {total} files to {DEST}")


if __name__ == "__main__":
    main()
