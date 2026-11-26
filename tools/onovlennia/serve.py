#!/usr/bin/env python3
"""Сервіс оновлень MyWay: лише читання, лише три шляхи.

    GET /config.json                      параметри сервера гри
    GET /manifest/<платформа>.json        перелік файлів збірки (шлях, розмір, SHA-256)
    GET /files/<платформа>/<шлях>         самі файли, з підтримкою Range (докачування)

Усе інше — 404. Методи — лише GET і HEAD (решта 405).

Корінь — каталог, який наповнює `tools/opublikuvaty.sh`:

    <корінь>/config.json
    <корінь>/manifest/linux.json …
    <корінь>/files/linux/MyWay.x86_64 …

Чому Python, а не Godot: у стандартній бібліотеці вже є багатопотоковий
HTTP-сервер; Range, потокова віддача 1,6 ГБ і перевірка шляхів — сотня
рядків без залежностей. У Godot HTTP-сервера немає зовсім: довелось би
писати розбір HTTP на голому TCP, а сам Godot головою займає сотні МБ.

Запуск: ./run-updates.sh (там же — порт і корінь).
"""

import argparse
import http.server
import os
import re
import sys
import time
import urllib.parse

PLATFORMS = ("linux", "macos", "windows")
CHUNK = 1 << 20
MANIFEST_RE = re.compile(r"^/manifest/(linux|macos|windows)\.json$")
FILES_RE = re.compile(r"^/files/(linux|macos|windows)/(.+)$")
RANGE_RE = re.compile(r"^bytes=(\d*)-(\d*)$")


def safe_path(base, relative):
    """Файл усередині `base` або None.

    Спершу відкидаємо очевидне (`..`, абсолютні шляхи, NUL, зворотні
    косі), потім нормалізуємо через realpath — він розкриває й символьні
    посилання — і перевіряємо, що результат лежить у корені. Друга
    перевірка ловить те, що проскочило повз першу.
    """
    if "\x00" in relative or "\\" in relative or relative.startswith("/"):
        return None
    parts = relative.split("/")
    if any(part in ("", ".", "..") for part in parts):
        return None
    root = os.path.realpath(base)
    target = os.path.realpath(os.path.join(root, *parts))
    if os.path.commonpath([root, target]) != root or target == root:
        return None
    if not os.path.isfile(target):
        return None
    return target


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "MyWayUpdates/1"
    protocol_version = "HTTP/1.1"
    root = "."

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s %s\n" % (
            time.strftime("%H:%M:%S"), self.address_string(), fmt % args))

    def fail(self, code, why):
        """Відмова з поясненням у тілі (UTF-8). `send_error` не годиться:
        він кладе текст у рядок статусу, а той лише latin-1."""
        body = (why + "\n").encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        self.answer(True)

    def do_HEAD(self):
        self.answer(False)

    def refuse_method(self):
        self.fail(405, "лише читання: GET або HEAD")

    do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = refuse_method

    def answer(self, with_body):
        raw = urllib.parse.urlsplit(self.path).path
        # Розкодовуємо %2e%2e тощо ДО перевірки: інакше «..» пройде закритим.
        try:
            path = urllib.parse.unquote(raw, errors="strict") if raw else "/"
        except UnicodeDecodeError:
            self.fail(400, "шлях не в UTF-8")
            return
        target = None
        kind = "application/octet-stream"
        if path == "/config.json":
            target = os.path.join(self.root, "config.json")
            kind = "application/json; charset=utf-8"
        elif MANIFEST_RE.match(path):
            name = MANIFEST_RE.match(path).group(1)
            target = os.path.join(self.root, "manifest", name + ".json")
            kind = "application/json; charset=utf-8"
        elif FILES_RE.match(path):
            found = FILES_RE.match(path)
            target = safe_path(os.path.join(self.root, "files", found.group(1)),
                               found.group(2))
            if target is None:
                self.fail(404, "немає такого файла")
                return
        if target is None or not os.path.isfile(target):
            self.fail(404, "немає такого шляху")
            return
        self.send_file(target, kind, with_body)

    def send_file(self, target, kind, with_body):
        try:
            handle = open(target, "rb")
        except OSError as err:
            self.fail(500, "не відкрився файл: %s" % err.strerror)
            return
        with handle:
            size = os.fstat(handle.fileno()).st_size
            start, end = 0, size - 1
            status = 200
            asked = self.headers.get("Range")
            if asked:
                found = RANGE_RE.match(asked.strip())
                # Кілька діапазонів через кому не підтримуємо — тоді
                # віддаємо весь файл (так дозволяє RFC 9110).
                if found and (found.group(1) or found.group(2)):
                    first, last = found.group(1), found.group(2)
                    if first:
                        start = int(first)
                        end = min(int(last), size - 1) if last else size - 1
                    else:
                        start = max(size - int(last), 0)
                    if start >= size or start > end:
                        self.send_response(416)
                        self.send_header("Content-Range", "bytes */%d" % size)
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                    status = 206
            length = end - start + 1 if size else 0
            self.send_response(status)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(length))
            self.send_header("Accept-Ranges", "bytes")
            if status == 206:
                self.send_header("Content-Range",
                                 "bytes %d-%d/%d" % (start, end, size))
            if kind.startswith("application/json"):
                self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            if not with_body:
                return
            handle.seek(start)
            left = length
            try:
                while left > 0:
                    block = handle.read(min(CHUNK, left))
                    if not block:
                        break
                    self.wfile.write(block)
                    left -= len(block)
            except (BrokenPipeError, ConnectionResetError):
                # Клієнт обірвав завантаження — докачає з Range.
                self.close_connection = True


def main():
    parser = argparse.ArgumentParser(description="Сервіс оновлень MyWay")
    parser.add_argument("--root", required=True, help="каталог публікації")
    parser.add_argument("--port", type=int, default=24600)
    parser.add_argument("--bind", default="0.0.0.0")
    args = parser.parse_args()
    root = os.path.realpath(args.root)
    if not os.path.isfile(os.path.join(root, "config.json")):
        sys.exit("‼ у %s немає config.json — спершу tools/opublikuvaty.sh"
                 % root)
    Handler.root = root
    server = http.server.ThreadingHTTPServer((args.bind, args.port), Handler)
    server.daemon_threads = True
    print("→ слухаю http://%s:%d/ · роздаю збірки з %s"
          % (args.bind, args.port, root), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
