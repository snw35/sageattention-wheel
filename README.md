# sageattention-wheel

* ![Build Status](https://github.com/snw35/sageattention-wheel/actions/workflows/update.yml/badge.svg)
* [Dockerhub: snw35/sageattention-wheel](https://hub.docker.com/r/snw35/sageattention-wheel)

Python wheel builder for the [Sageattention](https://github.com/thu-ml/SageAttention) package. Currently builds wheels for:

 * Linux x86_64, GlibC 2.34, cp311 (Python 3.11), CUDA 13
 * Linux_x86_64, GlibC 2.34, cp311 (Python 3.11), CUDA 12

Python 3.11 is chosen as it is used by e.g [Reforge Neo](https://github.com/snw35/reforge).

 ## How to Install Built Wheels

 There are two kinds of wheels built for each platform:

  * Basic wheel (with filename `*-linux_x86_64.whl`) - no libraries bundled, requires installing all external deps (pytorch, CUDA, etc), small filesize.
  * [PEP-600](https://peps.python.org/pep-0600/) compliant wheel (with filename `*-manylinux_2_34_x86_64.whl`) - full libraries included, large filesize.

Built wheels can be downloaded from the releases page. Select the one appropriate for your needs, Python version, and CUDA version. CUDA variants are encoded using a PEP 440 local version segment, so filenames include `+cu12` or `+cu13` (e.g. `sageattention-2.2.0+cu13-...whl`). Note that the 'PEP 600' wheel is **several gigabytes in size**.

To install the basic wheel, you will need to ensure Sageattention's dependencies are installed, for example Pytorch and Torchvision for CUDA 13, in an environment (OS or container) where the CUDA runtime is installed:

```
pip install torch torchvision --extra-index-url https://download.pytorch.org/whl/cu130
```

Then simply download the wheel from the releases page and install it using pip:

```
pip install <filename>
```

## Why?

The excellent Sageattention package can be used to decrease A.I image and video generation times essentially for free. This makes it very valuable to install in e.g AUTOMATIC1111 clone WebUIs, or ComfyUI, etc.

It is however difficult to install and especially hard to containerise, because there are no official pre-built wheels for it, and you need a compatible GPU (Nvidia RTX 20+), runtime (CUDA), compiler (nvcc), CUDA libs (a full cuda-devel image, 8GB), and all of its dependencies (Pytorch etc, about 5GB) present to compile it.

Because most build environments don't have high-end Nvidia GPUs, without pre-compiled wheels to install, you need to bring your entire development environment with you at runtime in order to compile it on-demand. E.g, all of the above packaged in a 13-20GB image that your users need to download every time, just to compile a single 15MB package once on first startup.

Instead, this container can be used to build pre-compiled wheels for sageattention to get around this problem.

## Compiling Yourself

You can run the included Docker compose file to pull the containers and build the wheels yourself. Note that:

 * **Important: you need a container runtime (Docker/Podman) with GPU pass-through (Nvidia container toolkit), and CUDA 13 installed on the host.**
 * You need a compatible GPU for Sageattention 2++ to build this, e.g RTX 20 series or newer.

**Warning: these are large images, around 13GB, due to the number of dependencies needed.**

```
git clone
docker compose up -d && docker compose logs -f
```

The containers will start and, assuming GPU pass-through is working, immediately begin building the wheels. Watch the log output and when finished look in `./wheelhouse` for your pre-compiled wheels of sageattention.

## Self-hosted Runner Requirements

The `Self-hosted wheelhouse` GitHub Actions workflow runs on a self-hosted runner and uses Docker Compose to build wheels, then uploads the resulting files in `./wheelhouse` to the latest GitHub release. The runner must meet these requirements:

 * Labeled `self-hosted` and `gpu` in GitHub Actions.
 * NVIDIA GPU supported by Sageattention (RTX 20 series or newer).
 * CUDA 13 or newer installed on the host and visible to `nvidia-smi`.
 * `nvidia-smi` available on PATH.
 * Docker installed with NVIDIA container toolkit (or equivalent GPU passthrough).
 * Docker Compose available (`docker compose` or `docker-compose`).
 * Network access to pull container images and upload release assets.

## Releases

Because free Github Actions runners do not have access to a GPU, I will build and release wheels compiled on my own hardware for now.
