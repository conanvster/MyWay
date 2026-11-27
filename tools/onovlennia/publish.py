#!/usr/bin/env python3
"""Публікація збірки клієнта в каталог сервісу оновлень.

    python3 -I tools/onovlennia/publish.py --build build/myway-… --root ~/MyWay-сервер/updates \\
        [--name «MyWay»] [--game-port 24565] [--min-release N] [linux macos windows]

Що робить:
  1. Для кожної платформи, що є в збірці, копіює її теку в
     <updates>/files/.new-<платформа>, рахує SHA-256 кожного файла й
     міняє стару теку на нову перейменуванням (сервіс віддає або стару
     публікацію, або нову, а не суміш).
  2. Пише <updates>/manifest/<платформа>.json.
  3. Пише <updates>/config.json.

Номер випуску. Версія збірки — «коміт · дата», її не впорядкуєш, тож
публікація дає кожній новій версії номер: на 1 більший за попередній.
Та сама версія вдруге (наприклад, Mac допубліковано пізніше) — той самий
номер. Мінімальний випуск типово = поточному: виклики між клієнтом і
сервером не мають номера версії, і різні збірки ламаються мовчки
(spec/клієнт-macos.md), тож старий клієнт грати не пускаємо.

Окремо: `--manifest-only <платформа>` перераховує маніфест для вже
опублікованих файлів (якщо файл у публікації замінили руками).
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import sys

PLATFORMS = ("linux", "macos", "windows")
CHUNK = 1 << 20


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(CHUNK)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def write_json(path, data):
    """Атомарно: у тимчасовий файл, потім перейменування."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temp = path + ".tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=1)
        handle.write("\n")
    os.replace(temp, path)


def read_json(path):
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def list_files(top):
    """Усі файли під `top`: шлях через «/», розмір, хеш, біт виконання."""
    entries = []
    for folder, dirs, names in os.walk(top):
        dirs.sort()
        for name in sorted(names):
            full = os.path.join(folder, name)
            relative = os.path.relpath(full, top).replace(os.sep, "/")
            if os.path.islink(full):
                target = os.readlink(full)
                resolved = os.path.realpath(full)
                if os.path.isabs(target) or os.path.commonpath(
                        [os.path.realpath(top), resolved]) != os.path.realpath(top):
                    sys.exit("‼ посилання %s веде за межі збірки: %s"
                             % (relative, target))
                entries.append({"path": relative, "link": target})
                continue
            entries.append({
                "path": relative,
                "size": os.path.getsize(full),
                "sha256": sha256_of(full),
                "exec": bool(os.stat(full).st_mode & 0o111),
            })
    return entries


def launch_of(platform, top):
    """Що запускати і (для Mac) який бандл."""
    if platform == "linux":
        return {"launch": "MyWay.x86_64"}
    if platform == "windows":
        return {"launch": "MyWay.exe"}
    apps = [n for n in sorted(os.listdir(top)) if n.endswith(".app")]
    if not apps:
        sys.exit("‼ у збірці macos немає .app")
    app = apps[0]
    plist = open(os.path.join(top, app, "Contents", "Info.plist"),
                 encoding="utf-8").read()
    found = re.search(r"<key>CFBundleExecutable</key>\s*<string>([^<]+)</string>",
                      plist)
    if not found:
        sys.exit("‼ у Info.plist немає CFBundleExecutable")
    return {"launch": "%s/Contents/MacOS/%s" % (app, found.group(1)), "app": app}


def build_version(build):
    info = read_json(os.path.join(build, "versiia.json"))
    if not info:
        sys.exit("‼ у %s немає versiia.json — це точно тека з tools/zibraty.sh?"
                 % build)
    commit, date = info.get("коміт", "?"), info.get("дата", "?")
    return {"commit": commit, "date": date, "version": "%s · %s" % (commit, date)}


def updater_version(repo):
    project = os.path.join(repo, "updater", "project.godot")
    if os.path.isfile(project):
        found = re.search(r'^config/version="(\d+)"', open(
            project, encoding="utf-8").read(), re.M)
        if found:
            return int(found.group(1))
    return 0


def make_manifest(platform, top, release, version):
    files = list_files(top)
    manifest = {
        "platform": platform,
        "release": release,
        "version": version["version"],
        "commit": version["commit"],
        "date": version["date"],
        "total": sum(f.get("size", 0) for f in files),
        "files": files,
    }
    manifest.update(launch_of(platform, top))
    return manifest


def main():
    repo = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", ".."))
    parser = argparse.ArgumentParser(description="Публікація збірки MyWay")
    parser.add_argument("--build", help="тека збірки (типово — найновіша в build/)")
    parser.add_argument("--updates", "--root", dest="updates",
                        default=os.path.expanduser("~/MyWay-сервер/updates"),
                        help="тека, з якої сервер роздає збірки")
    parser.add_argument("--name", help="назва сервера (типово — попередня або «MyWay»)")
    parser.add_argument("--game-port", type=int, help="ігровий порт UDP (типово 24565)")
    parser.add_argument("--min-release", type=int,
                        help="мінімальний випуск клієнта (типово = поточний)")
    parser.add_argument("--manifest-only", choices=PLATFORMS)
    parser.add_argument("--config-only", action="store_true",
                        help="лише оновити updater_version у config.json "
                             "(після нової збірки апдейтера), файли не чіпати")
    parser.add_argument("platforms", nargs="*", help="linux macos windows")
    args = parser.parse_args()
    for platform in args.platforms:
        if platform not in PLATFORMS:
            sys.exit("‼ невідома платформа «%s» (є: %s)"
                     % (platform, " ".join(PLATFORMS)))

    updates = os.path.realpath(args.updates)
    config_path = os.path.join(updates, "config.json")
    config = read_json(config_path) or {}

    if args.config_only:
        if not config:
            sys.exit("‼ %s ще немає — спершу повна публікація" % config_path)
        old = config.get("updater_version")
        config["updater_version"] = updater_version(repo)
        config["published"] = datetime.datetime.now().isoformat(timespec="seconds")
        write_json(config_path, config)
        print("✓ updater_version %s → %s (старі апдейтери покажуть «вийшла нова "
              "версія апдейтера»)" % (old, config["updater_version"]))
        return

    if args.manifest_only:
        platform = args.manifest_only
        old = read_json(os.path.join(updates, "manifest", platform + ".json"))
        if not old:
            sys.exit("‼ %s ще не опубліковано" % platform)
        top = os.path.join(updates, "files", platform)
        version = {k: old[k] for k in ("version", "commit", "date")}
        manifest = make_manifest(platform, top, old["release"], version)
        write_json(os.path.join(updates, "manifest", platform + ".json"), manifest)
        print("✓ маніфест %s перераховано: %d файлів" % (platform,
                                                         len(manifest["files"])))
        return

    build = args.build
    if not build:
        root = os.path.join(repo, "build")
        found = sorted((d for d in os.listdir(root) if d.startswith("myway-")),
                       key=lambda d: os.path.getmtime(os.path.join(root, d))) \
            if os.path.isdir(root) else []
        if not found:
            sys.exit("‼ у build/ немає збірок — спершу tools/zibraty.sh")
        build = os.path.join(root, found[-1])
    build = os.path.realpath(build)
    version = build_version(build)

    platforms = args.platforms or [p for p in PLATFORMS
                                   if os.path.isdir(os.path.join(build, p))]
    if not platforms:
        sys.exit("‼ у %s немає жодної платформи" % build)

    client = config.get("client") or {}
    release = int(client.get("release", 0))
    if client.get("version") != version["version"]:
        release += 1
    print("→ збірка %s · версія %s · випуск %d" % (build, version["version"],
                                                   release))

    published = dict(config.get("platforms") or {})
    for platform in platforms:
        source = os.path.join(build, platform)
        if not os.path.isdir(source):
            sys.exit("‼ у збірці немає %s" % platform)
        files_root = os.path.join(updates, "files")
        os.makedirs(files_root, exist_ok=True)
        fresh = os.path.join(files_root, ".new-" + platform)
        stale = os.path.join(files_root, ".old-" + platform)
        live = os.path.join(files_root, platform)
        for leftover in (fresh, stale):
            if os.path.lexists(leftover):
                shutil.rmtree(leftover)
        shutil.copytree(source, fresh, symlinks=True)
        shutil.copy2(os.path.join(build, "versiia.json"),
                     os.path.join(fresh, "versiia.json"))
        manifest = make_manifest(platform, fresh, release, version)
        if os.path.isdir(live):
            os.rename(live, stale)
        os.rename(fresh, live)
        write_json(os.path.join(updates, "manifest", platform + ".json"), manifest)
        if os.path.isdir(stale):
            shutil.rmtree(stale)
        published[platform] = {"release": release, "version": version["version"]}
        print("  ✓ %s: %d файлів, %.1f МБ" % (platform, len(manifest["files"]),
                                             manifest["total"] / 1e6))

    min_release = args.min_release if args.min_release is not None else release
    config = {
        "name": args.name or config.get("name") or "MyWay",
        "game_port": args.game_port or config.get("game_port") or 24565,
        # Окремого номера протоколу в грі немає: клієнт і сервер мають бути
        # з одного коміту, тож «протокол» — це коміт збірки.
        "protocol": version["commit"],
        "client": {"release": release, **version},
        "min_client_release": min_release,
        "updater_version": updater_version(repo),
        "platforms": published,
        "published": datetime.datetime.now().isoformat(timespec="seconds"),
    }
    write_json(config_path, config)
    print("✓ %s: «%s», гра на UDP %d, мінімальний випуск %d"
          % (config_path, config["name"], config["game_port"], min_release))


if __name__ == "__main__":
    main()
