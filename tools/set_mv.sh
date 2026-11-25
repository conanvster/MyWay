#!/bin/bash
# Увесь важкий сет моделі способом Б (25.11.2026, П-288): зони по черзі через tools/zona_mv.sh.
#   SET_D=… MOD_R=… MOD_N=… [MOD_S/MOD_V/MOD_T/MOD_K] MOD_G=… tools/set_mv.sh <еталон.png> [зона …]
cd "$(dirname "$0")/.."
ET=$1; shift
ZONY=("$@"); [ ${#ZONY[@]} -eq 0 ] && ZONY=(чоботи наручі наплічники пояс)
for ZN in "${ZONY[@]}"; do
  echo "=== $ZN"
  tools/zona_mv.sh $ZN $ET 2>&1 | grep -E "дотягнуто|РАМКА|без кольору|^\[зона\] (рамка|річ|Одяг|  підгонка|тіло під)|Error|Traceback|SystemExit" | cut -c1-170
done
echo "СЕТ ГОТОВИЙ"
