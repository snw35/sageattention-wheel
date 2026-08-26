#!/bin/bash

# Build SageAttention wheels using a Python-version matrix managed by uv.

set -euo pipefail

SAGE_DIR="/home/ubuntu/${SAGE_FILENAME}"
WHEEL_DIR="${WHEEL_PATH:-/home/ubuntu/wheelhouse}"
VENV_ROOT="/home/ubuntu/venvs"
TORCH_INDEX_URL="${TORCH_INDEX_URL:?TORCH_INDEX_URL must be set}"
UV_PYTHON_VERSIONS="${UV_PYTHON_VERSIONS:-}"

declare -a requested_versions=()
declare -a successful_versions=()
declare -a failed_versions=()

mkdir -p "${WHEEL_DIR}" "${VENV_ROOT}"
cd "${SAGE_DIR}"

cleanup_raw_dirs() {
  shopt -s nullglob
  local raw_dirs=("${WHEEL_DIR}"/raw-py*)
  shopt -u nullglob
  if [ ${#raw_dirs[@]} -gt 0 ]; then
    rm -rf "${raw_dirs[@]}"
  fi
}

trap cleanup_raw_dirs EXIT
cleanup_raw_dirs

discover_versions() {
  local versions=()

  if [ -n "${UV_PYTHON_VERSIONS}" ]; then
    local normalized="${UV_PYTHON_VERSIONS//,/ }"
    # shellcheck disable=SC2206
    versions=(${normalized})
    printf '%s\n' "${versions[@]}"
    return 0
  fi

  local list_output=""
  if list_output="$(uv python list 2>/dev/null)"; then
    mapfile -t versions < <(
      printf '%s\n' "${list_output}" \
        | grep -Eo '3\.[0-9]+' \
        | sort -Vu
    )
  fi

  if [ ${#versions[@]} -eq 0 ]; then
    local minor
    for minor in $(seq 8 20); do
      local candidate="3.${minor}"
      if uv python install "${candidate}" >/dev/null 2>&1; then
        versions+=("${candidate}")
      fi
    done
  fi

  if [ ${#versions[@]} -eq 0 ]; then
    echo "No installable CPython versions found via uv."
    return 1
  fi

  printf '%s\n' "${versions[@]}"
}

# torch is unpinned, so a matrix entry can resolve to a torch that this image's
# nvcc cannot compile against: torch >= 2.12 ships an ATen/core/List_inl.h that
# some nvcc/host-compiler pairs refuse to parse. Compiling one translation unit
# that instantiates it settles that in seconds instead of after a full build.
# Runs inside build_for_python, so it uses that venv's python and errexit: a
# failed probe aborts this Python version before any real compilation starts.
canary_torch() {
  local src="${VENV_ROOT}/canary.cu"

  # A bare #include does not instantiate the offending template; operator[] does.
  cat > "${src}" <<'CU'
#include <torch/extension.h>

void sageattention_canary() {
  c10::List<int64_t> values({1, 2, 3});
  (void)values[0];
}
CU

  # include_paths("cuda") suits both the modern device_type= signature and the
  # pre-2.8 cuda= boolean one. It omits the CPython headers that setuptools
  # supplies during the real build, and torch/extension.h includes Python.h, so
  # add them here or the probe fails on every torch, working ones included.
  local flags=()
  mapfile -t flags < <(python - <<'PY'
import os
import sysconfig

import torch
from torch.utils.cpp_extension import include_paths

print("-D_GLIBCXX_USE_CXX11_ABI=%d" % torch._C._GLIBCXX_USE_CXX11_ABI)

dirs = list(include_paths("cuda"))
dirs += [sysconfig.get_paths()["include"], sysconfig.get_config_var("INCLUDEPY")]
dirs = [d for d in dict.fromkeys(dirs) if d and os.path.isdir(d)]
print(*("-I" + d for d in dirs), sep="\n")
PY
  )

  timeout 300 nvcc -std=c++17 --expt-relaxed-constexpr "${flags[@]}" \
    -c "${src}" -o /dev/null
}

build_for_python() {
  local py_minor="$1"
  (
    set -euo pipefail

    local py_nodot="${py_minor/./}"
    local venv_dir="${VENV_ROOT}/venv-${py_minor}"
    local raw_out_dir="${WHEEL_DIR}/raw-py${py_nodot}"
    trap 'rm -rf "${raw_out_dir}"' EXIT

    echo "=== Building SageAttention wheel for Python ${py_minor} ==="

    uv python install "${py_minor}"

    rm -rf "${venv_dir}"
    uv venv "${venv_dir}" --seed --python "${py_minor}"

    # shellcheck disable=SC1090
    source "${venv_dir}/bin/activate"

    uv pip install \
      auditwheel \
      patchelf \
      ninja \
      torch torchvision --extra-index-url "${TORCH_INDEX_URL}" \
      wheel \
      setuptools \
      packaging

    echo "=== Canary: probing torch $(python -c 'import torch; print(torch.__version__)') ==="
    canary_torch

    if [ -n "${SAGE_VERSION:-}" ]; then
      python /home/ubuntu/patch_version.py
    fi

    rm -rf build dist
    find . -maxdepth 1 -name "*.egg-info" -exec rm -rf {} +

    rm -rf "${raw_out_dir}"
    mkdir -p "${raw_out_dir}"
    python -m pip wheel -w "${raw_out_dir}" --no-deps --no-build-isolation .

    shopt -s nullglob
    local wheel_candidates=("${raw_out_dir}"/sageattention-*+"${SAGE_CUDA_SUFFIX}"-*linux_x86_64.whl)
    shopt -u nullglob
    if [ ${#wheel_candidates[@]} -eq 0 ]; then
      echo "No linux_x86_64 wheel found in ${raw_out_dir}"
      exit 1
    fi

    local wheel="${wheel_candidates[0]}"
    cp -f "${wheel}" "${WHEEL_DIR}/"

    local torch_lib_path
    torch_lib_path="$(python -c 'import pathlib, torch; print(pathlib.Path(torch.__file__).resolve().parent / "lib")')"
    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:${torch_lib_path}"

    auditwheel show "${wheel}"
    auditwheel repair --strip -w "${WHEEL_DIR}" "${wheel}"

    deactivate
    uv cache clean
  )
}

mapfile -t requested_versions < <(discover_versions)

echo "Python versions selected: ${requested_versions[*]}"

for py_minor in "${requested_versions[@]}"; do
  # Not "if build_for_python ...": bash ignores errexit for the whole dynamic
  # extent of a condition, subshell included, so a mid-build failure there would
  # be masked by whatever ran last. Toggling it off around the call keeps the
  # "set -e" inside build_for_python armed.
  set +e
  build_for_python "${py_minor}"
  status=$?
  set -e

  if [ "${status}" -eq 0 ]; then
    successful_versions+=("${py_minor}")
  else
    failed_versions+=("${py_minor}")
    echo "Build failed for Python ${py_minor}; continuing."
  fi
done

if [ ${#successful_versions[@]} -gt 0 ]; then
  echo "Successful Python versions: ${successful_versions[*]}"
else
  echo "Successful Python versions: (none)"
fi

if [ ${#failed_versions[@]} -gt 0 ]; then
  echo "Failed Python versions: ${failed_versions[*]}"
fi

if [ ${#successful_versions[@]} -eq 0 ]; then
  echo "No wheels were built successfully."
  exit 1
fi
