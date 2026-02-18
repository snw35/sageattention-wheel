FROM nvidia/cuda:13.1.1-cudnn-devel-ubuntu24.04

# The nvcc compiler and full CUDA libs are needed to compile sageattention

# Install curl to fetch remote files
RUN apt-get update \
  && apt-get install -y \
    curl

# Copy and set permissions on scripts
COPY entrypoint.sh /home/ubuntu/entrypoint.sh
COPY build.sh /home/ubuntu/build.sh
COPY patch_version.py /home/ubuntu/patch_version.py
RUN mkdir /home/ubuntu/wheelhouse \
  && chown -R ubuntu:ubuntu /home/ubuntu \
  && chmod +x /home/ubuntu/*.sh

# Switch to ubuntu user for main setup
USER ubuntu
WORKDIR /home/ubuntu
ENV WHEEL_PATH=/home/ubuntu/wheelhouse
ENV UV_CACHE_DIR=/home/ubuntu/.cache/uv

# Optional comma-separated override, e.g. "3.11,3.12,3.13".
# If unset/empty, build.sh auto-discovers installable CPython versions with uv.
ENV UV_PYTHON_VERSIONS=
ENV TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130

# Version variables controlled by https://github.com/snw35/dfupdate
ENV UV_VERSION=0.10.3
ENV UV_URL=https://github.com/astral-sh/uv/releases/download/${UV_VERSION}
ENV UV_FILENAME=uv-x86_64-unknown-linux-gnu.tar.gz
ENV UV_SHA256=c60b9956a0e6727f0ddd881c303a706c6408b2047f3a8fa4d1454a826338ccdc

# Install UV
RUN curl -L -O ${UV_URL}/${UV_FILENAME} \
  && echo "${UV_SHA256}  ./${UV_FILENAME}" | sha256sum -c - \
  && tar -xzf ./${UV_FILENAME} \
  && mkdir -p ./.local/bin \
  && mv ./uv-x86_64-unknown-linux-gnu/* ./.local/bin/ \
  && rm -rf ./uv-x86_64-unknown-linux-gnu ./${UV_FILENAME}

# Add home and uv to path
ENV PATH="$PATH:/home/ubuntu:/home/ubuntu/.local/bin/"

# Version variables controlled by https://github.com/snw35/dfupdate
ENV SAGE_VERSION=2.2.0
ENV SAGE_CUDA_SUFFIX=cu13
ENV SAGE_URL=https://github.com/thu-ml/SageAttention/archive/refs/tags
ENV SAGE_FILENAME=SageAttention-${SAGE_VERSION}
ENV SAGE_SHA256=ddddf0ad4387ab3e45f14c6e2ae3b5898a158444fed21633b27586ca29ccdb49

# Download sageattention
RUN curl -L -O https://github.com/thu-ml/SageAttention/archive/refs/tags/v${SAGE_VERSION}.tar.gz \
  && echo "${SAGE_SHA256}  ./v${SAGE_VERSION}.tar.gz" | sha256sum -c - \
  && tar -xzf ./v${SAGE_VERSION}.tar.gz \
  && rm -f ./v${SAGE_VERSION}.tar.gz

# Prepare directories used by matrix builds at runtime
RUN mkdir -p "${WHEEL_PATH}" "${UV_CACHE_DIR}" /home/ubuntu/venvs

WORKDIR /home/ubuntu/${SAGE_FILENAME}

ENTRYPOINT ["entrypoint.sh"]

CMD ["build.sh"]
