#!/bin/bash

# Build a wheel for sageattentionin the current directory

if [ -f /home/ubuntu/venv/bin/activate ]; then

  cd /home/ubuntu/${SAGE_FILENAME}
  source /home/ubuntu/venv/bin/activate
  pip wheel -w /home/ubuntu/wheelhouse --no-deps --no-build-isolation .
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/home/ubuntu/venv/lib/python3.12/site-packages/torch/lib"
  auditwheel show /home/ubuntu/wheelhouse/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl
  auditwheel repair -w /home/ubuntu/wheelhouse /home/ubuntu/wheelhouse/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl

fi
