import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


APP_DIR = Path(__file__).resolve().parent
WEB_DIR = APP_DIR / 'build' / 'web'
API_ROUTES = {
    '/api/search': 'https://geocoding-api.open-meteo.com/v1/search',
    '/api/forecast': 'https://api.open-meteo.com/v1/forecast',
}


class PreviewHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        upstream = API_ROUTES.get(path)
        if upstream is None:
            return super().do_GET()

        query = urllib.parse.urlsplit(self.path).query
        request = urllib.request.Request(
            f'{upstream}?{query}',
            headers={
                'Accept': 'application/json',
                'User-Agent': 'weather-codespaces-preview/1.0',
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=35) as response:
                body = response.read()
                self.send_response(response.status)
                self.send_header(
                    'Content-Type',
                    response.headers.get('Content-Type', 'application/json'),
                )
                self.send_header('Content-Length', str(len(body)))
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as error:
            body = error.read()
            self.send_response(error.code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            self.log_error('Open-Meteo request failed: %s', error)
            body = json.dumps({
                'error': 'Weather service is unavailable. Check the connection and try again.',
            }).encode()
            self.send_response(502)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)


def main():
    flutter = os.environ.get('FLUTTER', 'flutter')
    subprocess.run(
        [flutter, 'build', 'web', '--release'],
        cwd=APP_DIR,
        check=True,
    )
    server = ThreadingHTTPServer(
        (os.environ.get('HOST', '0.0.0.0'), int(os.environ.get('PORT', '3000'))),
        PreviewHandler,
    )
    print('Weather preview is ready on port 3000. Press Ctrl+C to stop.')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nStopping weather preview.')
    finally:
        server.server_close()


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
