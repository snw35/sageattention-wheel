# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker-based **wheel builder** for [thu-ml/SageAttention](https://github.com/thu-ml/SageAttention) — it is not a Python package itself. There is no manifest, no test suite, and no importable source. `cu12/` and `cu13/` are two build contexts (CUDA 12 and CUDA 13) that produce Linux x86_64 wheels into `./wheelhouse`.

## Mirror cu12/ and cu13/

The two directories are deliberately near-identical — they differ only in the base image tag, `TORCH_INDEX_URL`, `SAGE_CUDA_SUFFIX`, and the nvchecker `include_regex`. **Any edit to a file in one directory must be applied to its counterpart in the other.** Verify with `diff -r cu12 cu13` after editing.

## Building

```
docker compose up -d && docker compose logs -f   # wheels land in ./wheelhouse
```

Requires an NVIDIA GPU host with nvidia-container-toolkit; images are ~13 GB. There is no make or test target. Lint shell scripts with `shellcheck --severity=warning cu12/*.sh cu13/*.sh` (same invocation CI runs via `.github/workflows/shellcheck.yml`); run it after editing any `.sh` file. Info-level `SC1091` on sourced venv activate paths is expected and excluded by the severity threshold.

## Do not hand-edit

`cu*/old_ver.json` and `cu*/new_ver.json` are nvchecker state written by the external [dfupdate](https://github.com/snw35/dfupdate) bot, which also rewrites the marked `ENV` lines in the Dockerfiles. Most commit history is these automated bumps.

## Gotchas

- **SHA256 pins**: bumping `SAGE_VERSION` or `UV_VERSION` by hand requires updating the matching `SAGE_SHA256` / `UV_SHA256` in the same Dockerfile.
- **2 GiB release cap**: `.github/workflows/selfhosted.yaml` filters `wheelhouse/` to files under 2 GiB before uploading. Confirmed on release `cu12-2.2.0-cu13-2.2.0`: cu13 manylinux wheels are ~1.71 GiB and survive, while cu12 manylinux wheels exceed the cap and are absent entirely — only the ~10 MiB raw `linux_x86_64` ones ship for cu12. That omission is expected, not a bug to "fix" by removing the filter (GitHub rejects the upload above 2 GiB).
- **`patch_version.py`** regex-replaces the first `version='...'` in upstream's `setup.py` to append the `+cu12`/`+cu13` PEP 440 local segment. It raises if no match — an upstream `setup.py` refactor breaks the build here.
- **Python matrix is auto-discovered** in `build.sh`, not pinned; per-version failures are tolerated and only logged. A green run can still be missing Python versions — read the "Failed Python versions" summary lines. Override with `UV_PYTHON_VERSIONS="3.11,3.12"`.
- **`TORCH_INDEX_URL` is required** (`${VAR:?}`); the build hard-fails without it.
- **Known bug**: `entrypoint.sh` sources `/home/ubuntu/venv/bin/activate`, a path that no longer exists (venvs are now `/home/ubuntu/venvs/venv-3.X`). The branch only fires when `$1` starts with `-`, so it is latent — fix it rather than working around it.
- **Do not reintroduce** the `nvidia-smi`-based host CUDA version check removed in commit 74b255f; it was deliberately dropped as brittle.

## CI

`.github/workflows/update.yml` delegates image build/publish and version bumping to reusable workflows in the separate **`snw35/cicd`** repo — that logic is not in this tree, so don't look for it here. `selfhosted.yaml` is `workflow_dispatch`-only, runs on a self-hosted GPU runner, and replaces assets on the latest release.
