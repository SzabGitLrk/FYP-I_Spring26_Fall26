#!/usr/bin/env python3
"""Offline server — serves WebApp + local CDN deps + Flask backend. No project files modified."""

import os, sys, urllib.request, shutil, subprocess, threading, mimetypes
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

BASE = Path(__file__).parent.resolve()
WEB  = BASE / 'WebApp'
LIB  = WEB  / 'lib'
THREE = LIB / 'three'
FA    = LIB / 'font-awesome'
PORT = 8000
FLASK_PORT = 5001  # matches api-client.js default

mimetypes.add_type('application/javascript', '.mjs')
mimetypes.add_type('font/woff2', '.woff2')
mimetypes.add_type('font/woff',  '.woff')
mimetypes.add_type('font/ttf',   '.ttf')

OK  = '[OK]'
INFO = '[..]'
DOWN = '[!!]'

# ── Dependency downloads ──────────────────────────────────────────────────────

NEEDED_CONTROLS = ['OrbitControls.js']
NEEDED_FBX_DEPS = [
    'libs/fflate.module.js',
    'curves/NURBSCurve.js',
    'curves/NURBSUtils.js',
]
FA_CDN = 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0'
NEEDED_FA_FILES = {
    'css/all.min.css': f'{FA_CDN}/css/all.min.css',
    'webfonts/fa-solid-900.woff2': f'{FA_CDN}/webfonts/fa-solid-900.woff2',
    'webfonts/fa-regular-400.woff2': f'{FA_CDN}/webfonts/fa-regular-400.woff2',
    'webfonts/fa-brands-400.woff2': f'{FA_CDN}/webfonts/fa-brands-400.woff2',
}

def _download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f'  -> {url.split("/")[-1]}')
    urllib.request.urlretrieve(url, dest)
    return dest

def ensure_threejs_controls():
    """Download missing Three.js addon files (OrbitControls, FBX deps, etc)."""
    missing = []
    for f in NEEDED_CONTROLS:
        if not (THREE / 'examples/jsm/controls' / f).exists():
            missing.append(f'controls/{f}')
    for f in NEEDED_FBX_DEPS:
        if not (THREE / 'examples/jsm' / f).exists():
            missing.append(f)
    if not missing:
        print(f'{OK} Three.js addons: present')
        return
    print(f'{INFO} Downloading Three.js addons...')
    for rel in missing:
        url = f'https://unpkg.com/three@0.160.0/examples/jsm/{rel}'
        dest = THREE / 'examples/jsm' / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        _download(url, dest)
    print(f'{OK} Three.js addons: done')

def ensure_fontawesome():
    """Download Font Awesome files from CDN if missing."""
    css = FA / 'css/all.min.css'
    if css.exists():
        print(f'{OK} Font Awesome: present')
        return
    print(f'{INFO} Downloading Font Awesome...')
    for rel, url in NEEDED_FA_FILES.items():
        dest = FA / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        _download(url, dest)
    print(f'{OK} Font Awesome: done')

# ── In-memory HTML rewriter ───────────────────────────────────────────────────

def rewrite_html(content: str) -> str:
    content = content.replace(
        'https://unpkg.com/three@0.160.0/build/three.module.js',
        '/lib/three/three.module.js')
    content = content.replace(
        'https://unpkg.com/three@0.160.0/examples/jsm/',
        '/lib/three/examples/jsm/')
    content = content.replace(
        'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css',
        '/lib/font-awesome/css/all.min.css')
    return content

# ── HTTP handler ──────────────────────────────────────────────────────────────

class OfflineHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB), **kwargs)

    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            return self._serve_rewritten_index()
        if self.path.startswith('/lib/three/'):
            return self._serve_local(THREE, self.path[len('/lib/three/'):])
        if self.path.startswith('/lib/font-awesome/'):
            return self._serve_local(FA, self.path[len('/lib/font-awesome/'):])
        return super().do_GET()

    def _serve_rewritten_index(self):
        path = WEB / 'index.html'
        if not path.exists():
            return self.send_error(404)
        raw = path.read_bytes()
        html = rewrite_html(raw.decode('utf-8'))
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(html.encode())))
        self.end_headers()
        self.wfile.write(html.encode('utf-8'))

    def _serve_local(self, base: Path, rel: str):
        fp = (base / rel).resolve()
        if not fp.exists() or not fp.is_file():
            return self.send_error(404)
        self.send_response(200)
        ct, _ = mimetypes.guess_type(str(fp))
        self.send_header('Content-Type', ct or 'application/octet-stream')
        self.send_header('Content-Length', str(fp.stat().st_size))
        self.end_headers()
        with open(fp, 'rb') as f:
            shutil.copyfileobj(f, self.wfile)

    def log_message(self, fmt, *args):
        print(f'  => {args[0]} {args[1]} {args[2]}')

# ── Flask backend starter ────────────────────────────────────────────────────

def start_flask():
    """Launch Flask backend on port 5001 in a subprocess."""
    flask_app = BASE / 'backend' / 'app.py'
    if not flask_app.exists():
        print(f'{DOWN} Flask backend not found at backend/app.py - skipping')
        return
    env = os.environ.copy()
    env['FLASK_PORT'] = str(FLASK_PORT)
    env_file = BASE / 'backend' / '.env'
    if not env_file.exists():
        env_file.write_text(f'FLASK_PORT={FLASK_PORT}\n')
    print(f'{INFO} Starting Flask backend on :{FLASK_PORT}...')
    proc = subprocess.Popen(
        [sys.executable, str(flask_app)],
        cwd=str(BASE / 'backend'),
        env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0)
    def tail():
        for line in proc.stdout:
            print(f'  [Flask] {line.decode().rstrip()}')
    threading.Thread(target=tail, daemon=True).start()

# ── WebSocket server starter ────────────────────────────────────────────────

def start_ws_server():
    """Launch sign-to-text HTTP prediction server on port 5002."""
    ws_app = BASE / 'backend' / 'server.py'
    if not ws_app.exists():
        print(f'{DOWN} Prediction server not found at backend/server.py - skipping')
        return
    print(f'{INFO} Starting Sign-to-Text prediction server on :5002...')
    proc = subprocess.Popen(
        [sys.executable, str(ws_app)],
        cwd=str(BASE / 'backend'),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0)
    def tail():
        for line in proc.stdout:
            print(f'  [WS] {line.decode().rstrip()}')
    threading.Thread(target=tail, daemon=True).start()

# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    os.chdir(str(WEB))

    ensure_threejs_controls()
    ensure_fontawesome()

    # Start Flask + WebSocket server in background
    threading.Thread(target=start_flask, daemon=True).start()
    threading.Thread(target=start_ws_server, daemon=True).start()

    server = ThreadingHTTPServer(('0.0.0.0', PORT), OfflineHandler)
    sep = '=' * 55
    print(f'\n{sep}')
    print(f'  BridgeSign AI - Offline Server')
    print(f'  URL:  http://localhost:{PORT}')
    print(f'  Ctrl+C to stop')
    print(f'{sep}\n')

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print(f'\n{OK} Server stopped')
        server.server_close()

if __name__ == '__main__':
    main()
