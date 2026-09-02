#!/usr/bin/env bash
# Запуск проєкту. За замовчуванням — на ДИСКРЕТНІЙ NVIDIA.
#
#   ./run.sh          редактор
#   ./run.sh --run    одразу гру (клієнт до 127.0.0.1)
#   ./run.sh --демо   гру в режимі показу: сама бере ціль, б'є і знімає екран
#   ./run.sh --демо-вікна  те саме, але ще й відкриває «Речі» й «Стати»
#   ./run.sh --демо-крамар те саме, але йде до крамаря й торгує
#   ./run.sh --парад  парад істот: усі види в ряд, знімок у user://
#   ./run.sh --вітрина  вікна «Речі», «Стати», «Скіли» з речами в кожному слоті
#
# Сервер піднімається окремо: ./run-server.sh
#
# Чому тут узагалі є вибір карти: LM Studio тримає модель на NVIDIA і
# займає майже всю її пам'ять (04.09.2025 було 15778 з 16311 МіБ). Godot
# тоді не може створити пристрій Vulkan і падає з "VkResult error -3".
# Тож скрипт дивиться, скільки на ній вільно, і сам вирішує:
#
#   вільно ≥ 2000 МіБ  -> дискретна NVIDIA (швидша, потрібна для світу з туманом)
#   вільно менше       -> вбудована AMD, із попередженням
#   AMD=1 ./run.sh  -> силувано вбудована
#
# Перевірити, куди воно справді пішло, можна за першим рядком журналу:
# Godot друкує "Using Device #N: ...".

set -euo pipefail
proj="$(cd "$(dirname "$0")" && pwd)/game"
amd_icd=/usr/share/vulkan/icd.d/radeon_icd.json

if [ "${AMD:-0}" = "1" ]; then
    export VK_ICD_FILENAMES="$amd_icd"
    echo "→ вбудована AMD (силувано)"
else
    free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null || echo 0)
    if [ "$free" -ge 2000 ]; then
        echo "→ дискретна NVIDIA, вільно ${free} МіБ"
    else
        echo "‼ на NVIDIA вільно лише ${free} МіБ — беру вбудовану AMD." >&2
        echo "  щоб звільнити:  lms unload --all" >&2
        export VK_ICD_FILENAMES="$amd_icd"
    fi
fi

case "${1:-}" in
    --run)  exec godot --path "$proj" ;;
    --демо) exec godot --path "$proj" -- --демо ;;
    --демо-вікна) exec godot --path "$proj" -- --демо --вікна ;;
    --демо-крамар) exec godot --path "$proj" -- --демо --крамар ;;
    --демо-персонаж) exec godot --path "$proj" -- --демо --персонаж Вовкодав ;;
    --парад) exec godot --path "$proj" --script res://probes/parade.gd ;;
    --вітрина) exec godot --path "$proj" --script res://probes/showcase.gd ;;
    --демо-акаунт)   exec godot --path "$proj" -- --демо --акаунт конан --пароль таємниця --персонаж Вовкодав-2 ;;
    *)      exec godot --path "$proj" -e ;;
esac
