#!/bin/bash

# Build a wheel for sageattentionin the current directory

if [ -f /home/ubuntu/venv/bin/activate ]; then

  source /home/ubuntu/venv/bin/activate
  pip wheel -w /home/ubuntu/wheelhouse --no-deps --no-build-isolation /home/ubuntu/sageattention-1
  pip wheel -w /home/ubuntu/wheelhouse --no-deps --no-build-isolation /home/ubuntu/${SAGE_FILENAME}
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/home/ubuntu/venv/lib/python3.12/site-packages/torch/lib"
  find /home/ubuntu/wheelhouse -name '*.whl' -exec auditwheel repair -w /home/ubuntu/wheelhouse {} --strip \;
  find /home/ubuntu/wheelhouse -name '*.whl' -exec auditwheel show {} \;

fi
