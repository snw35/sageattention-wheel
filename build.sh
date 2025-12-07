#!/bin/bash

# Build a wheel for sageattentionin the current directory

if [ -f /home/ubuntu/venv/bin/activate ]; then

  cd /home/ubuntu/${SAGE_FILENAME}
  source /home/ubuntu/venv/bin/activate
  pip wheel -w /home/ubuntu/wheelhouse --no-deps --no-build-isolation .

fi
