#!/usr/bin/env python3
"""Fetch the Bangladesh manhole photos (Mendeley Data 10.17632/7zzcmv2wz7.1,
CC BY 4.0): one folder per class, no boxes.

    python mendeley_manholes.py <out dir> <class prefix> [limit]

Class prefixes: Uncovered_Manhole, Broken_Manhole, Square_Manhole,
Good_Manhole, Speed_breaker. Reads <out dir>/meta.json (the dataset record
from https://data.mendeley.com/public-api/datasets/7zzcmv2wz7).
"""
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor


def main():
    out, prefix = sys.argv[1], sys.argv[2]
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else None
    files = [f for f in json.load(open(f'{out}/meta.json', encoding='utf-8'))['files']
             if f['filename'].lower().startswith(prefix.lower())]
    files.sort(key=lambda f: f['filename'])
    if limit:
        files = files[::max(1, len(files) // limit)][:limit]
    os.makedirs(f'{out}/{prefix}', exist_ok=True)

    def one(f):
        path = f'{out}/{prefix}/{f["filename"]}'
        if os.path.exists(path):
            return
        for attempt in range(5):
            try:
                # Mendeley answers 403 to urllib's own User-Agent.
                req = urllib.request.Request(f['content_details']['download_url'],
                                             headers={'User-Agent': 'curl/8.9.1'})
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
                if len(data) == f['size']:
                    break
            except OSError:
                if attempt == 4:
                    raise
        with open(path + '.part', 'wb') as fh:
            fh.write(data)
        os.replace(path + '.part', path)

    # Each file costs a redirect and a fetch; the line is slow to answer,
    # so many run at once.
    with ThreadPoolExecutor(8) as pool:
        list(pool.map(one, files))
    print(prefix, len(files), 'files')


if __name__ == '__main__':
    main()
