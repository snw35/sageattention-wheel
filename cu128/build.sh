#!/bin/bash

# Build a wheel for sageattentionin the current directory

if [ -f /home/ubuntu/venv/bin/activate ]; then

  source /home/ubuntu/venv/bin/activate
  pip wheel -w /home/ubuntu/wheelhouse --no-deps --no-build-isolation /home/ubuntu/sageattention-1
  pip wheel -w /home/ubuntu/wheelhouse --no-deps --no-build-isolation /home/ubuntu/${SAGE_FILENAME}
  pip wheel -w /home/ubuntu/wheelhouse --no-deps --no-build-isolation /home/ubuntu/${SAGE_FILENAME}/sageattention3_blackwell
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/home/ubuntu/venv/lib/python3.11/site-packages/torch/lib"
  auditwheel show /home/ubuntu/wheelhouse/*
  auditwheel repair -w /home/ubuntu/wheelhouse /home/ubuntu/wheelhouse/* --strip
  auditwheel show /home/ubuntu/wheelhouse/*

fi
