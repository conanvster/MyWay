#!/usr/bin/env bash
# Запуск проєкту на ВБУДОВАНІЙ відеокарті AMD.
#
# Навіщо: LM Studio тримає модель на NVIDIA і займає майже всю її пам'ять
# (перевірено 02.09.2026: 15778 з 16311 МіБ). Godot тоді не може створити
# пристрій Vulkan і падає з "VkResult error -3". Вбудована AMD вільна, і
# для капсул її вистачає з головою.
#
#   ./запуск.sh          редактор
#   ./запуск.sh --run    одразу гру
#   NVIDIA=1 ./запуск.sh  силувано на NVIDIA (спершу вивантаж модель: lms unload --all)

set -euo pipefail
proj="$(cd "$(dirname "$0")" && pwd)/game"

if [ "${NVIDIA:-0}" = "1" ]; then
    free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null || echo 0)
    if [ "$free" -lt 2000 ]; then
        echo "‼ на NVIDIA вільно ${free} МіБ — Vulkan не підніметься." >&2
        echo "  вивантаж модель:  lms unload --all" >&2
        exit 1
    fi
else
    export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
fi

if [ "${1:-}" = "--run" ]; then
    exec godot --path "$proj"
else
    exec godot --path "$proj" -e
fi
