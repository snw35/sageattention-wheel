# sageattention-wheel

Python wheel builder for the [Sageattention](https://github.com/thu-ml/SageAttention) package. Currently builds wheels for:

 * Linux, cp312 (Python 3.12), CUDA 13.0.

 ## How to Use

 You will need to ensure Sageattention's dependencies are installed, e.g Pytorch and Torchvision for CUDA 13:

 ```
 pip install torch torchvision --extra-index-url https://download.pytorch.org/whl/cu130
 ```

 Then simply download the pre-compiled wheel from the releases page and install it using pip:

 ```
 pip install <filename>
 ```

## Why?

The excellent Sageattention package can be used to decrease A.I image and video generation times essentially for free. This makes it very valuable to install in e.g AUTOMATIC1111 clone WebUIs, or ComfyUI, etc.

It is however difficult to install and especially hard to containerise, because there are no official pre-built wheels for it, and you need a compatible GPU (Nvidia RTX 20+), runtime (CUDA), compiler (nvcc), CUDA libs (a full cuda-devel image, 8GB), and all of its dependencies (Pytorch etc, about 5GB) present to compile it.

Because most build environments don't have high-end Nvidia GPUs, without pre-compiled wheels to install, you need to bring your entire development environment with you at runtime in order to compile it on-demand. E.g, all of the above packaged in a 13-20GB image that your users need to download every time, just to compile a single 15MB package once on first startup.

Instead, this container can be used to build pre-compiled wheels for sageattention to get around this problem.

## Compiling Yourself

You can run the included Docker compose file to pull the container and build the wheel yourself. Note that:

 * **Important: you need a container runtime (Docker/Podman) with GPU pass-through (Nvidia container toolkit), and CUDA 13 installed on the host.**
 * You need a compatible GPU for Sageattention 2++ to build this, e.g RTX 20 series or newer.

**Warning: this is a large image, around 13GB, due to the number of dependencies needed.**

```
git clone
docker compose up -d && docker compose logs -f
```

The container will start and, assuming GPU pass-through is working, immediately begin building the wheel. Watch the log output and when finished look in `./wheelhouse` for your pre-compiled wheel of sageattention.

## Releases

Because free Github Actions runners do not have access to a GPU, I will build and release wheels compiled on my own hardware for now.
