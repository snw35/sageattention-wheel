#!/bin/bash

# Build SageAttention wheels using a Python-version matrix managed by uv.

set -euo pipefail

SAGE_DIR="/home/ubuntu/${SAGE_FILENAME}"
WHEEL_DIR="${WHEEL_PATH:-/home/ubuntu/wheelhouse}"
VENV_ROOT="/home/ubuntu/venvs"
TORCH_INDEX_URL="${TORCH_INDEX_URL:?TORCH_INDEX_URL must be set}"
UV_PYTHON_VERSIONS="${UV_PYTHON_VERSIONS:-}"

declare -a requested_versions=()
declare -a prepared_versions=()
declare -a successful_versions=()
declare -a failed_versions=()

# Populated in the parent shell by the preparation pass. torch is deliberately
# unpinned, so different Python versions can resolve to different torch builds.
declare -A torch_for=()
declare -A probe_result=()

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

# Create the venv and install the build dependencies. Kept separate from the
# wheel build so the canary below can reject a bad torch before any of the
# expensive CUDA compilation starts.
prepare_venv() {
  local py_minor="$1"
  (
    set -euo pipefail

    local venv_dir="${VENV_ROOT}/venv-${py_minor}"

    echo "=== Preparing environment for Python ${py_minor} ==="

    # Every failure below is checked explicitly. bash suppresses errexit inside
    # a subshell whose function is invoked from a condition ("if ! prepare_venv"),
    # and the "set -e" above does not re-arm it, so an unchecked command would
    # let a broken environment through as a success. Do not remove the "|| exit".
    uv python install "${py_minor}" || exit 1

    rm -rf "${venv_dir}"
    uv venv "${venv_dir}" --seed --python "${py_minor}" || exit 1

    uv pip install --python "${venv_dir}/bin/python" \
      auditwheel \
      patchelf \
      ninja \
      torch torchvision --extra-index-url "${TORCH_INDEX_URL}" \
      wheel \
      setuptools \
      packaging || exit 1

    # Clean here rather than after the build: every download happens in this
    # pass, so leaving it until later would let the cache grow across the whole
    # matrix. uv's links into the venv survive the cache being cleared.
    uv cache clean || true

    # Final guard: torch is the one dependency the build cannot proceed without.
    "${venv_dir}/bin/python" -c 'import torch' >/dev/null 2>&1 || exit 1
  )
}

resolved_torch_version() {
  local py_minor="$1"
  "${VENV_ROOT}/venv-${py_minor}/bin/python" -c 'import torch; print(torch.__version__)'
}

# Compile a single translation unit against the installed torch headers. torch
# >= 2.12 shipped an ATen/core/List_inl.h that some nvcc/host-compiler pairs
# refuse to parse, which previously surfaced only after a full build had run.
probe_torch() {
  local py_minor="$1"
  local torch_ver="$2"
  (
    set -euo pipefail

    local py="${VENV_ROOT}/venv-${py_minor}/bin/python"
    local probe_dir
    probe_dir="$(mktemp -d)"
    trap 'rm -rf "${probe_dir}"' EXIT

    echo "=== Canary: probing torch ${torch_ver} (Python ${py_minor}) ==="

    local nvcc="${CUDA_HOME:-/usr/local/cuda}/bin/nvcc"
    if [ ! -x "${nvcc}" ]; then
      nvcc="$(command -v nvcc || true)"
    fi
    if [ -z "${nvcc}" ] || [ ! -x "${nvcc}" ]; then
      echo "Canary: nvcc not found; skipping the probe for torch ${torch_ver}."
      exit 0
    fi

    cat > "${probe_dir}/include_paths.py" <<'PY'
from torch.utils.cpp_extension import include_paths

try:
    paths = include_paths(device_type="cuda")
except TypeError:  # torch < 2.8 spells the argument differently
    paths = include_paths(cuda=True)

for path in paths:
    print("-I" + path)
PY

    local includes=()
    mapfile -t includes < <("${py}" "${probe_dir}/include_paths.py")
    if [ ${#includes[@]} -eq 0 ]; then
      echo "Canary: could not determine torch include paths; skipping the probe."
      exit 0
    fi

    local abi
    abi="$("${py}" -c 'import torch; print(1 if torch._C._GLIBCXX_USE_CXX11_ABI else 0)')"

    # A bare #include does not instantiate the offending template, so call
    # operator[] explicitly to reproduce what the real build triggers.
    cat > "${probe_dir}/canary.cu" <<'CU'
#include <torch/extension.h>

void sageattention_canary() {
  c10::List<int64_t> values({1, 2, 3});
  (void)values[0];
}
CU

    if timeout 300 "${nvcc}" \
      -std=c++17 \
      --expt-relaxed-constexpr \
      -D_GLIBCXX_USE_CXX11_ABI="${abi}" \
      "${includes[@]}" \
      -c "${probe_dir}/canary.cu" \
      -o "${probe_dir}/canary.o"; then
      echo "Canary: torch ${torch_ver} compiles."
      exit 0
    fi

    echo "Canary: torch ${torch_ver} failed to compile against the CUDA toolkit in this image."
    exit 1
  )
}

build_wheel() {
  local py_minor="$1"
  (
    set -euo pipefail

    local py_nodot="${py_minor/./}"
    local venv_dir="${VENV_ROOT}/venv-${py_minor}"
    local raw_out_dir="${WHEEL_DIR}/raw-py${py_nodot}"
    trap 'rm -rf "${raw_out_dir}"' EXIT

    echo "=== Building SageAttention wheel for Python ${py_minor} (torch ${torch_for[${py_minor}]}) ==="

    # As in prepare_venv, errexit is suppressed here, so check explicitly.
    # shellcheck disable=SC1090
    source "${venv_dir}/bin/activate" || exit 1

    if [ -n "${SAGE_VERSION:-}" ]; then
      python /home/ubuntu/patch_version.py || exit 1
    fi

    rm -rf build dist
    find . -maxdepth 1 -name "*.egg-info" -exec rm -rf {} +

    rm -rf "${raw_out_dir}"
    mkdir -p "${raw_out_dir}"
    python -m pip wheel -w "${raw_out_dir}" --no-deps --no-build-isolation . || exit 1

    shopt -s nullglob
    local wheel_candidates=("${raw_out_dir}"/sageattention-*+"${SAGE_CUDA_SUFFIX}"-*linux_x86_64.whl)
    shopt -u nullglob
    if [ ${#wheel_candidates[@]} -eq 0 ]; then
      echo "No linux_x86_64 wheel found in ${raw_out_dir}"
      exit 1
    fi

    local wheel="${wheel_candidates[0]}"
    cp -f "${wheel}" "${WHEEL_DIR}/" || exit 1

    local torch_lib_path
    torch_lib_path="$(python -c 'import pathlib, torch; print(pathlib.Path(torch.__file__).resolve().parent / "lib")')" || exit 1
    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:${torch_lib_path}"

    auditwheel show "${wheel}" || exit 1
    auditwheel repair --strip -w "${WHEEL_DIR}" "${wheel}" || exit 1

    deactivate
  )
}

mapfile -t requested_versions < <(discover_versions)

echo "Python versions selected: ${requested_versions[*]}"

# Pass 1: install torch, then canary-check each distinct torch version once.
for py_minor in "${requested_versions[@]}"; do
  if ! prepare_venv "${py_minor}"; then
    echo "Environment preparation failed for Python ${py_minor}; continuing."
    failed_versions+=("${py_minor}")
    continue
  fi

  torch_ver="$(resolved_torch_version "${py_minor}" || true)"
  if [ -z "${torch_ver}" ]; then
    echo "Could not determine the torch version for Python ${py_minor}; continuing."
    failed_versions+=("${py_minor}")
    continue
  fi

  torch_for["${py_minor}"]="${torch_ver}"
  echo "Python ${py_minor} resolved torch ${torch_ver}"

  if [ -n "${probe_result[${torch_ver}]:-}" ]; then
    echo "Canary: reusing the ${probe_result[${torch_ver}]} verdict for torch ${torch_ver}"
  elif probe_torch "${py_minor}" "${torch_ver}"; then
    probe_result["${torch_ver}"]="ok"
  else
    probe_result["${torch_ver}"]="fail"
  fi

  if [ "${probe_result[${torch_ver}]}" != "ok" ]; then
    echo "Skipping Python ${py_minor}: torch ${torch_ver} did not pass the canary."
    failed_versions+=("${py_minor}")
    continue
  fi

  prepared_versions+=("${py_minor}")
done

if [ ${#prepared_versions[@]} -eq 0 ]; then
  echo "No Python version has a usable torch build; nothing to compile."
  echo "Failed Python versions: ${failed_versions[*]}"
  echo "No wheels were built successfully."
  exit 1
fi

echo "Python versions cleared for building: ${prepared_versions[*]}"

# Pass 2: build against the environments prepared above.
for py_minor in "${prepared_versions[@]}"; do
  if build_wheel "${py_minor}"; then
    successful_versions+=("${py_minor}")
  else
    failed_versions+=("${py_minor}")
    echo "Build failed for Python ${py_minor}; continuing."
  fi
done

if [ ${#successful_versions[@]} -gt 0 ]; then
  echo "Successful Python versions: ${successful_versions[*]}"
  for py_minor in "${successful_versions[@]}"; do
    echo "  Python ${py_minor} built against torch ${torch_for[${py_minor}]}"
  done
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
