#!/bin/bash

# Build a wheel for sageattention in the current directory

set -euo pipefail

VENV_ACTIVATE="/home/ubuntu/venv/bin/activate"
if [ ! -f "${VENV_ACTIVATE}" ]; then
  exit 0
fi

cd "/home/ubuntu/${SAGE_FILENAME}"
source "${VENV_ACTIVATE}"

if [ -n "${SAGE_VERSION:-}" ]; then
  python /home/ubuntu/patch_version.py
fi

pip wheel -w /home/ubuntu/wheelhouse --no-deps --no-build-isolation .

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:/home/ubuntu/venv/lib/python3.11/site-packages/torch/lib"

shopt -s nullglob
wheel_candidates=(/home/ubuntu/wheelhouse/sageattention-*+${SAGE_CUDA_SUFFIX}-*linux_x86_64.whl)
if [ ${#wheel_candidates[@]} -eq 0 ]; then
  echo "No linux_x86_64 wheel found in /home/ubuntu/wheelhouse"
  exit 1
fi
wheel="${wheel_candidates[0]}"

auditwheel show "${wheel}"
auditwheel repair --strip -w /home/ubuntu/wheelhouse "${wheel}"
