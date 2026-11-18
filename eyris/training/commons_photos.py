"""Download freely licensed photos from Wikimedia Commons by search term.

    python commons.py <out_dir> <per_term> "group=term one|term two" ...

Each group becomes a folder; photos are saved 640 px wide.
"""
import hashlib
import json
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

API = "https://en.wikipedia.org/w/api.php"
UA = {"User-Agent": "EyrisEvalBot/1.0 (offline evaluation of an accessibility app; low volume)"}


def get(url, timeout=60):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
                return r.read()
        except Exception as error:  # noqa: BLE001
            last = error
            time.sleep(2 + 3 * attempt)
    raise last


def search(term, limit):
    urls, offset = [], 0
    while len(urls) < limit and offset < 500:
        q = urllib.parse.urlencode({
            "action": "query", "format": "json", "generator": "search",
            "gsrsearch": f"{term} filetype:bitmap", "gsrnamespace": 6, "gsrlimit": 50,
            "gsroffset": offset, "prop": "imageinfo", "iiprop": "url|mime|size",
            "iiurlwidth": 960,
        })
        try:
            data = json.loads(get(f"{API}?{q}"))
        except Exception as error:  # noqa: BLE001
            print('search failed', term, error, flush=True)
            break
        pages = data.get("query", {}).get("pages", {})
        if not pages:
            break
        for page in sorted(pages.values(), key=lambda p: p.get("index", 0)):
            info = (page.get("imageinfo") or [{}])[0]
            if info.get("mime") == "image/jpeg" and info.get("width", 0) >= 500 and info.get("thumburl"):
                urls.append((hashlib.md5(page["title"].encode()).hexdigest()[:12], info["thumburl"]))
        offset += 50
        if "continue" not in data:
            break
    return urls[:limit]


def main():
    out, per = Path(sys.argv[1]), int(sys.argv[2])
    for spec in sys.argv[3:]:
        group, terms = spec.split("=", 1)
        folder = out / group
        folder.mkdir(parents=True, exist_ok=True)
        seen, jobs = set(), []
        for term in terms.split("|"):
            for pid, url in search(term, per):
                if pid not in seen:
                    seen.add(pid)
                    jobs.append((folder / f"{group}_{pid}.jpg", url))

        def fetch(job):
            path, url = job
            if path.exists() and path.stat().st_size > 2000:
                return 1
            try:
                path.write_bytes(get(url))
                return 1
            except Exception:  # noqa: BLE001
                return 0

        with ThreadPoolExecutor(2) as pool:
            ok = sum(pool.map(fetch, jobs))
        print(f"{group}: {ok}/{len(jobs)} photos", flush=True)


if __name__ == "__main__":
    main()
