#!/usr/bin/env python3
"""Read single members of a remote zip with HTTP range requests, so that a
few hundred photos can be taken from a 1 GB archive on a slow line.

    python remote_zip.py list <url> [pattern]          # names and sizes
    python remote_zip.py get <url> <out dir> <regex>   # members whose name matches

The url may redirect (Kaggle's download link redirects to a signed Google
Storage url that accepts ranges).
"""
import os
import re
import struct
import sys
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor


def resolve(url):
    req = urllib.request.Request(url, headers={'Range': 'bytes=0-0'})
    with urllib.request.urlopen(req, timeout=60) as r:
        total = int(r.headers['Content-Range'].split('/')[1])
        return r.geturl(), total


def fetch(url, start, end, tries=5):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={'Range': f'bytes={start}-{end}'})
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            if len(data) == end - start + 1:
                return data
        except OSError:
            if attempt == tries - 1:
                raise
    raise IOError(f'short read {start}-{end}')


def members(url, total):
    tail = fetch(url, max(0, total - 65557), total - 1)
    at = tail.rfind(b'PK\x05\x06')
    entries, size, offset = struct.unpack('<HII', tail[at + 10:at + 20])
    if offset == 0xFFFFFFFF or entries == 0xFFFF:   # zip64
        loc = tail.rfind(b'PK\x06\x07')
        z64 = struct.unpack('<Q', tail[loc + 8:loc + 16])[0]
        rec = fetch(url, z64, z64 + 55)
        entries, size, offset = struct.unpack('<QQQ', rec[32:56])
    cd = fetch(url, offset, offset + size - 1)
    out, p = [], 0
    for _ in range(entries):
        (method, csize, usize, nlen, xlen, clen, local) = (
            struct.unpack('<H', cd[p + 10:p + 12])[0],
            *struct.unpack('<II', cd[p + 20:p + 28]),
            *struct.unpack('<HHH', cd[p + 28:p + 34]),
            struct.unpack('<I', cd[p + 42:p + 46])[0])
        name = cd[p + 46:p + 46 + nlen].decode('utf-8', 'replace')
        extra = cd[p + 46 + nlen:p + 46 + nlen + xlen]
        if 0xFFFFFFFF in (csize, usize, local):
            q = 0
            while q + 4 <= len(extra):
                tag, ln = struct.unpack('<HH', extra[q:q + 4])
                if tag == 1:
                    vals = list(struct.unpack('<' + 'Q' * (ln // 8), extra[q + 4:q + 4 + ln]))
                    if usize == 0xFFFFFFFF:
                        usize = vals.pop(0)
                    if csize == 0xFFFFFFFF:
                        csize = vals.pop(0)
                    if local == 0xFFFFFFFF:
                        local = vals.pop(0)
                q += 4 + ln
        out.append((name, method, csize, usize, local))
        p += 46 + nlen + xlen + clen
    return out


def read_member(url, m):
    name, method, csize, usize, local = m
    head = fetch(url, local, local + 29)
    nlen, xlen = struct.unpack('<HH', head[26:30])
    start = local + 30 + nlen + xlen
    data = fetch(url, start, start + csize - 1) if csize else b''
    if method == 8:
        data = zlib.decompress(data, -15)
    elif method != 0:
        raise ValueError(f'{name}: compression {method}')
    return data


def main():
    step, url = sys.argv[1], sys.argv[2]
    real, total = resolve(url)
    ms = members(real, total)
    if step == 'list':
        pat = re.compile(sys.argv[3]) if len(sys.argv) > 3 else None
        for m in ms:
            if pat is None or pat.search(m[0]):
                print(m[3], m[0])
        print(len(ms), 'members,', total, 'bytes')
        return
    out, pat = sys.argv[3], re.compile(sys.argv[4])
    todo = [m for m in ms if pat.search(m[0]) and not m[0].endswith('/')]
    todo = [m for m in todo if not os.path.exists(os.path.join(out, m[0]))]
    print(len(todo), 'members to fetch', sum(m[2] for m in todo) // 1024, 'KB', flush=True)

    # The line is slow to answer, not only slow to carry: members that lie
    # next to each other in the archive are fetched in one request.
    todo.sort(key=lambda m: m[4])
    spans, gap, most = [], 32 * 1024, 2 * 1024 * 1024
    for m in todo:
        end = m[4] + 30 + 1024 + m[2]   # header and name, generously
        if spans and m[4] - spans[-1][1] <= gap and end - spans[-1][0] <= most:
            spans[-1][1] = max(spans[-1][1], end)
            spans[-1][2].append(m)
        else:
            spans.append([m[4], end, [m]])

    def one(span):
        start, end, group = span
        blob = fetch(real, start, min(end, total) - 1)
        for name, method, csize, usize, local in group:
            p = local - start
            nlen, xlen = struct.unpack('<HH', blob[p + 26:p + 30])
            data = blob[p + 30 + nlen + xlen:p + 30 + nlen + xlen + csize]
            if method == 8:
                data = zlib.decompress(data, -15)
            path = os.path.join(out, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path + '.part', 'wb') as f:
                f.write(data)
            os.replace(path + '.part', path)
        return len(group)

    done = 0
    with ThreadPoolExecutor(4) as pool:
        for n in pool.map(one, spans):
            done += n
            print(done, len(todo), flush=True)
    print('done', done)


if __name__ == '__main__':
    main()
