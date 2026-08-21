#!/bin/bash
set -exuo pipefail

PYTHON="$1"
TRAVIS_COMMIT="${TRAVIS_COMMIT:-${BUILDKITE_COMMIT:-$(git rev-parse HEAD)}}"

export RAY_BUILD_ENV="manylinux_py${PYTHON}"

mkdir -p .whl
cd python
# Cython 3.0.12 predates CPython 3.14 and cannot compile ray's .pyx under 3.14.
# Use a cp314-capable Cython (3.1.x) only for the py314 build so the existing
# py311-py313 wheels stay on the unchanged 3.0.12 toolchain.
if [[ "${PYTHON}" == "cp314-cp314" ]]; then
  CYTHON_VERSION="3.1.8"
else
  CYTHON_VERSION="3.0.12"
fi
/opt/python/"${PYTHON}"/bin/pip install -q "cython==${CYTHON_VERSION}" setuptools==80.9.0
# Set the commit SHA in _version.py.
if [[ -n "$TRAVIS_COMMIT" ]]; then
  sed -i.bak "s/{{RAY_COMMIT_SHA}}/$TRAVIS_COMMIT/g" ray/_version.py && rm ray/_version.py.bak
else
  echo "TRAVIS_COMMIT variable not set - required to populated ray.__commit__."
  exit 1
fi

# When building the wheel, we always set RAY_INSTALL_JAVA=0 because we
# have already built the Java code above.

export BAZEL_PATH="$HOME"/bin/bazel

# Pointing a default python3 symlink to the desired python version.
# This is required for building with bazel.
sudo ln -sf "/opt/python/${PYTHON}/bin/python3" /usr/local/bin/python3

# build ray wheel
PATH="/opt/python/${PYTHON}/bin:$PATH" RAY_INSTALL_JAVA=0 \
"/opt/python/${PYTHON}/bin/python" -m pip wheel -v -w dist . --no-deps

# Disabled because we don't use this.
# if [[ "${RAY_DISABLE_EXTRA_CPP:-}" != 1 ]]; then
#   # build ray-cpp wheel
#   PATH="/opt/python/${PYTHON}/bin:$PATH" RAY_INSTALL_JAVA=0 \
#   RAY_INSTALL_CPP=1 "/opt/python/${PYTHON}/bin/python" -m pip wheel -v -w dist . --no-deps
# fi

# Rename the wheels so that they can be uploaded to PyPI. TODO(rkn): This is a
# hack, we should use auditwheel instead.
for path in dist/*.whl; do
  if [[ -f "${path}" ]]; then
    out="${path//-linux/-manylinux2014}"
    if [[ "$out" != "$path" ]]; then
      mv "${path}" "${out}"
    fi
  fi
done
mv dist/*.whl ../.whl/
