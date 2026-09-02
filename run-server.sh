#!/usr/bin/env bash
# Ігровий сервер: той самий Godot без вікна.
#   ./run-server.sh
set -euo pipefail
exec godot --headless --path "$(cd "$(dirname "$0")" && pwd)/game" -- --server
