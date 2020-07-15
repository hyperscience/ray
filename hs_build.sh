#! /bin/bash

docker build -t ray-build-context .
docker run --mount type=bind,source=$(pwd)/hs_dist,target=/tmp/hs_dist ray-build-context:latest python setup.py bdist_wheel -d /tmp/hs_dist
