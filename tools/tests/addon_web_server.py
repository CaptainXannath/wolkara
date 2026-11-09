"""Loopback-only WebKit download fixture; no provider credentials or game files."""
import http.server
import io
import pathlib
import sys
import time
import zipfile

buffer = io.BytesIO()
with zipfile.ZipFile(buffer, 'w') as archive:
    archive.writestr('Fixture/Fixture.toc', '## Interface: 16001\n## Title: Web fixture\n')
ZIP = buffer.getvalue()

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        assert not self.headers.get('x-api-key'), 'API credentials reached the website flow'
        if self.path == '/':
            content = b'''<!doctype html><meta name="viewport" content="width=device-width"><title>Addon download fixture</title>
                <h1>Addon download fixture</h1><a id="plain" href="/addon.zip">Download</a>
                <a id="attribute" href="/addon.zip" download="addon.zip">Download attribute</a>
                <a id="popup" href="/addon.zip" target="_blank">New window download</a>
                <a id="redirect" href="/redirect.zip" download="addon.zip">Redirected download</a>'''
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
        elif self.path == '/redirect.zip':
            self.send_response(302)
            self.send_header('Location', '/addon.zip')
            self.end_headers()
            return
        elif self.path == '/html.zip':
            content = b'<html><title>Not an archive</title><body>Sign in first</body></html>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
        else:
            content = ZIP
            self.send_response(403 if self.path == '/error.zip' else 200)
            self.send_header('Content-Type', 'application/zip')
            self.send_header('Content-Disposition', 'attachment; filename="../../addon.zip"')
        length = 129*1024*1024 if self.path == '/large.zip' else 10*1024*1024 if self.path == '/slow.zip' else len(content)
        self.send_header('Content-Length', str(length))
        self.end_headers()
        try:
            if self.path == '/slow.zip':
                for _ in range(160):
                    self.wfile.write(b'x' * 65536)
                    self.wfile.flush()
                    time.sleep(0.1)
            else:
                self.wfile.write(content)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
