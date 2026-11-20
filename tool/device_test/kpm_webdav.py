#!/usr/bin/env python3
"""Server WebDAV HTTPS minimo per le prove di KeePassMobile sul telefono.

Uso: python3 tool/device_test/kpm_webdav.py <cartella> <porta> <utente> <password>
Certificato autofirmato creato con openssl in <cartella>/../tls (CN=localhost).
Dal telefono: `adb reverse tcp:<porta> tcp:<porta>`, poi https://localhost:<porta>/.
Solo GET, HEAD, PUT, PROPFIND (profondità 0 e 1), OPTIONS, con autenticazione
Basic. Registra metodo e percorso di ogni richiesta (mai credenziali o contenuti).
"""
import base64
import hashlib
import os
import ssl
import subprocess
import sys
from email.utils import formatdate
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote, unquote
from xml.sax.saxutils import escape

ROOT, PORT, USER, SECRET = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
TLS = os.path.join(os.path.dirname(os.path.abspath(ROOT)), 'tls')
EXPECTED = 'Basic ' + base64.b64encode(f'{USER}:{SECRET}'.encode()).decode()


def certificate():
    os.makedirs(TLS, exist_ok=True)
    cert, key = os.path.join(TLS, 'cert.pem'), os.path.join(TLS, 'key.pem')
    if not os.path.exists(cert):
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt',
                        'ec_paramgen_curve:prime256v1', '-nodes', '-days', '30',
                        '-subj', '/CN=localhost', '-addext',
                        'subjectAltName=DNS:localhost,IP:127.0.0.1',
                        '-keyout', key, '-out', cert], check=True,
                       capture_output=True)
    der = ssl.PEM_cert_to_DER_cert(open(cert).read())
    fingerprint = ':'.join(f'{b:02X}' for b in hashlib.sha256(der).digest())
    return cert, key, fingerprint


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        print(f'{self.command} {unquote(self.path)} -> {args[1] if len(args) > 1 else ""}', flush=True)

    def _path(self):
        rel = unquote(self.path.split('?')[0]).lstrip('/')
        full = os.path.realpath(os.path.join(ROOT, rel))
        return full if full.startswith(os.path.realpath(ROOT)) else None

    def _auth(self):
        if self.headers.get('Authorization') == EXPECTED:
            return True
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="kpm"')
        self.send_header('Content-Length', '0')
        self.end_headers()
        return False

    def _empty(self, status):
        self.send_response(status)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def _body(self):
        length = int(self.headers.get('Content-Length') or 0)
        return self.rfile.read(length) if length else b''

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('DAV', '1')
        self.send_header('Allow', 'OPTIONS, GET, HEAD, PUT, PROPFIND')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def _get(self, head):
        self._body()
        if not self._auth():
            return
        path = self._path()
        if not path or not os.path.isfile(path):
            return self._empty(404)
        data = open(path, 'rb').read()
        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('ETag', '"' + hashlib.sha1(data).hexdigest() + '"')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        if not head:
            self.wfile.write(data)

    def do_GET(self):
        self._get(False)

    def do_HEAD(self):
        self._get(True)

    def do_PUT(self):
        data = self._body()
        if not self._auth():
            return
        path = self._path()
        if not path or os.path.isdir(path):
            return self._empty(409)
        existed = os.path.exists(path)
        tmp = path + '.kpm-upload'
        open(tmp, 'wb').write(data)
        os.replace(tmp, path)
        self._empty(204 if existed else 201)

    def do_PROPFIND(self):
        self._body()
        if not self._auth():
            return
        path = self._path()
        if not path or not os.path.exists(path):
            return self._empty(404)
        href = '/' + os.path.relpath(path, ROOT).replace(os.sep, '/').lstrip('.')
        items = [(href, path)]
        if os.path.isdir(path) and self.headers.get('Depth', '1') != '0':
            base = href if href.endswith('/') else href + '/'
            for name in sorted(os.listdir(path)):
                if name.startswith('.') or name.endswith('.kpm-upload'):
                    continue
                items.append((base + name, os.path.join(path, name)))
        parts = []
        for h, p in items:
            folder = os.path.isdir(p)
            h = h + '/' if folder and not h.endswith('/') else h
            prop = '<d:resourcetype><d:collection/></d:resourcetype>' if folder else \
                f'<d:resourcetype/><d:getcontentlength>{os.path.getsize(p)}</d:getcontentlength>'
            parts.append(f'<d:response><d:href>{escape(quote(h))}</d:href><d:propstat><d:prop>'
                         f'{prop}<d:getlastmodified>{formatdate(os.path.getmtime(p), usegmt=True)}'
                         '</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status>'
                         '</d:propstat></d:response>')
        body = ('<?xml version="1.0" encoding="utf-8"?><d:multistatus xmlns:d="DAV:">'
                + ''.join(parts) + '</d:multistatus>').encode()
        self.send_response(207)
        self.send_header('Content-Type', 'application/xml; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == '__main__':
    cert, key, fingerprint = certificate()
    print('FINGERPRINT ' + fingerprint, flush=True)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server = ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f'READY https://localhost:{PORT}/', flush=True)
    server.serve_forever()
