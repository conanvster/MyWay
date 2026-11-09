#!/usr/bin/env bash
# Орк-чоловік v1–v3 → основи (09.11.2026): Redux від обличчя, 3 сіди, далі
# очищення ork_lysyi.py — темне (борода, коси, хутро), тоді за положенням.
set -e
cd "$(dirname "$0")/.."
PY=~/Програми/cv-venv/bin/python
V=art/орк-чоловік-основи-2026-11-09/redux-обличчя
$PY -u tools/comfyui/ork_rasy_osnovy.py --обличчя 4201 4202 4203
K=$(ls $V/v[123]-s42*.png | grep -v lysyi)
$PY -u tools/comfyui/ork_lysyi.py $V $K --сіди 3201
K2=$(ls $V/v[123]-s42??-lysyi-s3201.png)
$PY -u tools/comfyui/ork_lysyi.py $V $K2 --геометрія --сіди 3301
echo ГОТОВО
