#!/usr/bin/env python3
"""Fetch Objects365 photos of floor-standing air conditioners without
downloading the whole dataset (hundreds of GB).

    python objects365_ac.py scan      # categories of every photo (~50 MB)
    python objects365_ac.py boxes N   # boxes of the N row groups richest in ACs
    python objects365_ac.py fetch     # the photos, cut out of the zip parts

Annotations: Hugging Face jxu124/objects365 (parquet, read column by column
with HTTP range requests). Photos: hieupth/objects365_384_squared, zip parts
whose files are stored uncompressed, so each photo is one range request once
the part's central directory is known. Those photos are letterboxed to
384 x 384; the padding is cut off again here.

Objects365 has one "Air Conditioner" class for wall, window, ceiling and
floor units. A box counts as a standing unit when it is clearly taller than
wide and not small; photos whose AC boxes are all wall units become photos
without a standing AC, which teaches the model the difference.
"""
import io
import json
import os
import struct
import sys
from concurrent.futures import ThreadPoolExecutor

import requests

OUT = 'D:/dev/eyris_work/hazard/o365'
ANN = 'https://huggingface.co/datasets/jxu124/objects365/resolve/main/data/'
IMG = 'https://huggingface.co/datasets/hieupth/objects365_384_squared/resolve/main/'
AC_ID = 84
TALL = 1.3         # height / width of a standing unit's box
MIN_HEIGHT = 0.08  # of the photo height


def parquet_files():
    tree = requests.get('https://huggingface.co/api/datasets/jxu124/objects365/tree/main/data',
                        timeout=120).json()
    return sorted(t['path'].split('/')[-1] for t in tree if t['path'].endswith('.parquet'))


class RangeFile(io.RawIOBase):
    """Read-only remote file: every read is one HTTP range request, so
    pyarrow fetches exactly the column chunks it decodes and nothing else."""

    def __init__(self, url):
        self.source, self.pos = url, 0
        self.resolve()

    def resolve(self):
        # The Hub redirects to a signed CDN address; ask for it once.
        head = requests.get(self.source, headers={'Range': 'bytes=0-0'}, timeout=120)
        self.url = head.url
        self.size = int(head.headers['Content-Range'].split('/')[1])

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else (self.pos + offset if whence == 1 else self.size + offset)
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        n = min(n, self.size - self.pos)
        if n <= 0:
            return b''
        for attempt in range(5):
            try:
                r = requests.get(self.url, timeout=300,
                                 headers={'Range': f'bytes={self.pos}-{self.pos + n - 1}'})
                if r.status_code == 206 and len(r.content) == n:
                    self.pos += n
                    return r.content
                if r.status_code in (401, 403):
                    self.resolve()
            except Exception:
                pass
        raise IOError(f'range read failed at {self.pos}')

    def readinto(self, b):
        data = self.read(len(b))
        b[:len(data)] = data
        return len(data)


def open_parquet(name):
    import pyarrow.parquet as pq
    return pq.ParquetFile(RangeFile(ANN + name), pre_buffer=False, buffer_size=0)


def scan():
    os.makedirs(OUT, exist_ok=True)

    def one(name):
        path = f'{OUT}/scan_{name}.json'
        if os.path.exists(path):
            return json.load(open(path))
        pf = open_parquet(name)
        rows = []
        for g in range(pf.metadata.num_row_groups):
            t = pf.read_row_group(g, columns=['anns_info.list.item.category_id'])
            cats = t.column(0).to_pylist()
            n_ac = sum(1 for row in cats if row and any(c['category_id'] == AC_ID for c in row))
            rows.append((name, g, n_ac))
        json.dump(rows, open(path, 'w'))
        print(name, sum(r[2] for r in rows), 'photos with an AC', flush=True)
        return rows

    with ThreadPoolExecutor(7) as pool:
        result = [r for rows in pool.map(one, parquet_files()) for r in rows]
    json.dump(result, open(f'{OUT}/scan.json', 'w'))


def boxes(n_groups):
    import glob
    scan_rows = [r for p in glob.glob(f'{OUT}/scan_*.json') for r in json.load(open(p))]
    scan_rows.sort(key=lambda r: -r[2])
    chosen = scan_rows[:n_groups]
    keep = json.load(open(f'{OUT}/photos.json')) if os.path.exists(f'{OUT}/photos.json') else {}
    done = {tuple(x) for x in keep.get('_groups', [])}
    by_file = {}
    for name, g, _ in chosen:
        if (name, g) not in done:
            by_file.setdefault(name, []).append(g)
    columns = ['image_path', 'image_info.width', 'image_info.height',
               'anns_info.list.item.bbox', 'anns_info.list.item.category_id']

    def one(name):
        pf = open_parquet(name)
        found = {}
        for g in by_file[name]:
            for row in pf.read_row_group(g, columns=columns).to_pylist():
                acs = [a['bbox'] for a in row['anns_info'] or [] if a['category_id'] == AC_ID]
                if acs:
                    found[os.path.basename(row['image_path'])] = dict(
                        w=row['image_info']['width'], h=row['image_info']['height'], ac=acs)
        print(name, len(found), 'photos with an AC', flush=True)
        return name, found

    with ThreadPoolExecutor(7) as pool:
        for name, found in pool.map(one, list(by_file)):
            keep.update(found)
            keep.setdefault('_groups', []).extend([name, g] for g in by_file[name])
    json.dump(keep, open(f'{OUT}/photos.json', 'w'))
    print(len(keep) - 1, 'photos with an AC,',
          sum(1 for n, i in keep.items() if n != '_groups' and standing(i)), 'with a standing unit')


def standing(info):
    out = []
    for x1, y1, x2, y2 in info['ac']:
        bw, bh = x2 - x1, y2 - y1
        if bw > 0 and bh / bw >= TALL and bh / info['h'] >= MIN_HEIGHT:
            out.append((x1, y1, x2, y2))
    return out


def rng(name, start, end):
    for _ in range(4):
        try:
            r = requests.get(IMG + name, headers={'Range': f'bytes={start}-{end}'}, timeout=300)
            if r.status_code in (200, 206):
                return r.content
        except Exception:
            pass
    raise IOError(f'range {name} {start}-{end}')


def central_directory(part):
    path = f'{OUT}/cd_{part}.json'
    if os.path.exists(path):
        return json.load(open(path))
    head = requests.get(IMG + part, headers={'Range': 'bytes=0-0'}, timeout=120)
    total = int(head.headers['Content-Range'].split('/')[1])
    tail = rng(part, total - 65536, total - 1)
    i = tail.rfind(b'PK\x06\x06')
    if i >= 0:
        cd_size, cd_off = struct.unpack('<QQ', tail[i + 40:i + 56])
    else:
        i = tail.rfind(b'PK\x05\x06')
        cd_size, cd_off = struct.unpack('<II', tail[i + 12:i + 20])
    cd = rng(part, cd_off, cd_off + cd_size - 1)
    entries, p = {}, 0
    while p + 46 <= len(cd) and cd[p:p + 4] == b'PK\x01\x02':
        csize, usize = struct.unpack('<II', cd[p + 20:p + 28])
        nlen, xlen, clen = struct.unpack('<HHH', cd[p + 28:p + 34])
        off = struct.unpack('<I', cd[p + 42:p + 46])[0]
        fname = cd[p + 46:p + 46 + nlen].decode()
        extra = cd[p + 46 + nlen:p + 46 + nlen + xlen]
        q = 0
        while q + 4 <= len(extra):
            tag, size = struct.unpack('<HH', extra[q:q + 4])
            if tag == 1:
                vals = extra[q + 4:q + 4 + size]
                k = 0
                if usize == 0xFFFFFFFF:
                    usize = struct.unpack('<Q', vals[k:k + 8])[0]; k += 8
                if csize == 0xFFFFFFFF:
                    csize = struct.unpack('<Q', vals[k:k + 8])[0]; k += 8
                if off == 0xFFFFFFFF:
                    off = struct.unpack('<Q', vals[k:k + 8])[0]
            q += 4 + size
        entries[os.path.basename(fname)] = (off, csize)
        p += 46 + nlen + xlen + clen
    json.dump(entries, open(path, 'w'))
    return entries


def fetch():
    from PIL import Image
    photos = json.load(open(f'{OUT}/photos.json'))
    photos.pop('_groups', None)
    wanted = {n: i for n, i in photos.items() if standing(i)}
    print(len(photos), 'photos with an AC,', len(wanted), 'with a standing unit', flush=True)
    os.makedirs(f'{OUT}/images', exist_ok=True)
    os.makedirs(f'{OUT}/labels', exist_ok=True)
    tree = requests.get('https://huggingface.co/api/datasets/hieupth/objects365_384_squared/tree/main',
                        timeout=120).json()
    parts = sorted(t['path'] for t in tree if t['path'].startswith('images_part'))
    located = {}
    for part in parts:
        if all(n in located for n in wanted):
            break
        cd = central_directory(part)
        for n in wanted:
            if n in cd and n not in located:
                located[n] = (part, *cd[n])
        print(part, len(located), 'of', len(wanted), 'located', flush=True)

    def one(n):
        if os.path.exists(f'{OUT}/images/{n}'):
            return True
        part, off, size = located[n]
        blob = rng(part, off, off + 30 + 300 + size)
        nlen, xlen = struct.unpack('<HH', blob[26:30])
        data = blob[30 + nlen + xlen:30 + nlen + xlen + size]
        info = wanted[n]
        w, h = info['w'], info['h']
        im = Image.open(io.BytesIO(data)).convert('RGB')
        side = im.width
        s = side / max(w, h)
        cw, ch = round(w * s), round(h * s)
        px, py = (side - cw) // 2, (side - ch) // 2
        im = im.crop((px, py, px + cw, py + ch))
        im.save(f'{OUT}/images/{n}', quality=95)
        with open(f'{OUT}/labels/{n[:-4]}.txt', 'w') as f:
            for x1, y1, x2, y2 in standing(info):
                f.write(f'2 {(x1 + x2) / 2 / w:.6f} {(y1 + y2) / 2 / h:.6f} '
                        f'{(x2 - x1) / w:.6f} {(y2 - y1) / h:.6f}\n')
        return True

    with ThreadPoolExecutor(6) as pool:
        ok = sum(pool.map(lambda n: one(n) if n in located else False, list(wanted)))
    print('fetched', ok, flush=True)


if __name__ == '__main__':
    step = sys.argv[1]
    if step == 'scan':
        scan()
    elif step == 'boxes':
        boxes(int(sys.argv[2]))
    else:
        fetch()
