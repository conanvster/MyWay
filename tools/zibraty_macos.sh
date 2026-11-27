#!/usr/bin/env bash
# Клієнт MyWay лише для macOS (Universal: arm64 + x86_64). Усе робить
# tools/zibraty.sh — там і опис, і змінні OUT_DIR / TEMPLATES_DIR.
exec "$(dirname "$0")/zibraty.sh" macos "$@"
