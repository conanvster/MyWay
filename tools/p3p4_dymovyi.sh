#!/usr/bin/env bash
# П3 + П4 — димовий прогін (план §3д, кроки 1–2): 3 речі зброї й 3 речі броні.
#
#     tools/p3p4_dymovyi.sh            # перевірити й запустити
#     tools/p3p4_dymovyi.sh --perevir  # лише перевірки, без GPU
#
# Запускати лише зі «так» замовника на GPU. Сам НЕ зупиняє чужі процеси:
# якщо йде стенд кодингу (run-v4.sh) або на NVIDIA вільно менше 14 ГБ —
# виходить і каже, що зайнято. LM Studio вивантажує (`lms unload --all`) —
# це те, що завжди робилось перед генерацією (`monster3d.py`).
#
# Змінні лише латиницею (пам'ять: кирилиця в масивах bash ламається).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
py="$HOME/Програми/cv-venv/bin/python"
comfy="$HOME/ComfyUI"
log="$root/art/p3p4-$(date +%Y%m%d-%H%M).log"
mkdir -p "$root/art"

say() { echo "== $(date +%H:%M:%S) $*" | tee -a "$log"; }

# 1. Перевірки без GPU
"$py" -u "$root/tools/comfyui/bronia_2var.py" перевірити | tee -a "$log"
if ps -eo args | grep -q "[r]un-v4.sh"; then
  say "‼ іде стенд кодингу (run-v4.sh) — GPU зайнятий. Стоп."; exit 2
fi
if [ "${1:-}" = "--perevir" ]; then say "лише перевірки — гаразд"; exit 0; fi

# 2. Відеокарта
lms unload --all >/dev/null 2>&1 || true
free_mb=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
if [ "$free_mb" -lt 14000 ]; then
  say "‼ на NVIDIA вільно лише ${free_mb} МіБ (треба 14000). Хто тримає:"
  nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv | tee -a "$log"
  exit 3
fi
say "NVIDIA вільно ${free_mb} МіБ"

# 3. ComfyUI
if ! curl -sf http://127.0.0.1:8188/system_stats >/dev/null; then
  say "піднімаю ComfyUI"
  (cd "$comfy" && nohup venv/bin/python main.py --listen 127.0.0.1 --port 8188 \
      >"$root/art/comfyui-p3p4.log" 2>&1 &)
  for _ in $(seq 1 90); do
    curl -sf http://127.0.0.1:8188/system_stats >/dev/null && break
    sleep 2
  done
fi
curl -sf http://127.0.0.1:8188/system_stats >/dev/null || { say "‼ ComfyUI не піднявся"; exit 4; }

# 4. П3 — зброя: кадр → сітка → Blender → імпорт Godot → аркуш
t0=$(date +%s)
say "П3: кадри зброї"
"$py" -u "$root/tools/comfyui/zbroia_3d.py" кадр "сталевий меч" "залізна сокира" "сталевий щит" | tee -a "$log"
say "П3: сітки Pixal3D"
"$py" -u "$root/tools/comfyui/zbroia_3d.py" сітка "сталевий меч" "залізна сокира" "сталевий щит" | tee -a "$log"
say "П3: збірка в Blender"
blender -b -P "$root/tools/blender/zbroia_zbirka.py" -- "сталевий меч" "залізна сокира" "сталевий щит" 2>&1 | grep -v '^\[INFO' | tee -a "$log"
godot --headless --path "$root/game" --import >/dev/null 2>&1 || true
"$py" -u "$root/tools/comfyui/zbroia_3d.py" аркуш "сталевий меч" "залізна сокира" "сталевий щит" | tee -a "$log"
say "П3 за $(( ($(date +%s) - t0) / 60 )) хв; розміри:"
ls -l "$root/game/models/own/zbroia/" 2>/dev/null | tee -a "$log" || true

# 5. П4 — броня: А (Qwen-Edit) і Б (FLUX+Redux) на 3 речах, аркуш
t0=$(date +%s)
say "П4: броня А/Б"
"$py" -u "$root/tools/comfyui/bronia_2var.py" кадр "шолом з кори дуба" "вовча куртка" "сталеві рукавиці" | tee -a "$log"
"$py" -u "$root/tools/comfyui/bronia_2var.py" аркуш E D C | tee -a "$log"
say "П4 за $(( ($(date +%s) - t0) / 60 )) хв"
say "готово. Журнал: $log. LM Studio НЕ повертав — за словом замовника."
