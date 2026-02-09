#!/bin/bash

# Cause the script to exit if a single command fails.
set -e

# Show explicitly which commands are currently running.
set -x

DOWNLOAD_DIR=python_downloads

NODE_VERSION="14"

PY_MMS=("3.9" "3.10" "3.11" "3.12")

VENV_ROOT="$HOME/.ray_venvs"

if [[ -n "${SKIP_DEP_RES}" ]]; then
  ./ci/env/install-bazel.sh

  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

  # Use the latest version of Node.js in order to build the dashboard.
  source "$HOME"/.nvm/nvm.sh
  nvm install $NODE_VERSION
  nvm use $NODE_VERSION
fi

# Build the dashboard so its static assets can be included in the wheel.
pushd python/ray/dashboard/client
  source "$HOME"/.nvm/nvm.sh
  npm ci
  npm run build
popd

mkdir -p .whl
mkdir -p "$VENV_ROOT"

for ((i=0; i<${#PY_MMS[@]}; ++i)); do
  PY_MM=${PY_MMS[i]}
  VENV_NAME="p$PY_MM"
  VENV_PATH="$VENV_ROOT/$VENV_NAME"

  # The -f flag is passed twice to also run git clean in the arrow subdirectory.
  # The -d flag removes directories. The -x flag ignores the .gitignore file,
  # and the -e flag ensures that we don't remove the .whl directory.
  git clean -f -f -x -d -e .whl -e $DOWNLOAD_DIR -e python/ray/dashboard/client -e dashboard/client


  # Install the Python version if it doesn’t exist
  if ! pyenv versions --bare | grep -q "^$PY_MM$"; then
      pyenv install "$PY_MM"
  fi

  # Use the exact pyenv-installed Python for the venv
  PYTHON_EXE="$(pyenv prefix "$PY_MM")/bin/python"

  # Remove old venv and create new one with the correct Python
  rm -rf "$VENV_PATH"
  $PYTHON_EXE -m venv "$VENV_PATH"
  source "$VENV_PATH/bin/activate"

  # NOTE: venv activates the correct PATH instead.
  PIP_CMD=pip
  PYTHON_EXE=python

  $PIP_CMD install --upgrade pip

  if [ -z "${TRAVIS_COMMIT}" ]; then
    TRAVIS_COMMIT=${BUILDKITE_COMMIT}
  fi

  pushd python
    # Setuptools on CentOS is too old to install arrow 0.9.0, therefore we upgrade.
    # TODO: Unpin after https://github.com/pypa/setuptools/issues/2849 is fixed.
    $PIP_CMD install --upgrade setuptools==69.5.1
    $PIP_CMD install -q cython==0.29.37
    # Install wheel to avoid the error "invalid command 'bdist_wheel'".
    $PIP_CMD install -q wheel
    # Set the commit SHA in _version.py.
    if [ -n "$TRAVIS_COMMIT" ]; then
      echo "TRAVIS_COMMIT variable detected. ray.__commit__ will be set to $TRAVIS_COMMIT"
    else
      echo "TRAVIS_COMMIT variable is not set, getting the current commit from git."
      TRAVIS_COMMIT=$(git rev-parse HEAD)
    fi

    sed -i .bak "s/{{RAY_COMMIT_SHA}}/$TRAVIS_COMMIT/g" ray/_version.py && rm ray/_version.py.bak

    # Add the correct Python to the path and build the wheel. This is only
    # needed so that the installation finds the cython executable.
    # build ray wheel
    $PYTHON_EXE setup.py bdist_wheel
    # build ray-cpp wheel
    RAY_INSTALL_CPP=1 $PYTHON_EXE setup.py bdist_wheel
    mv dist/*.whl ../.whl/
  popd

  # cleanup
  deactivate
  rm -rf "$VENV_PATH"
done

pyenv local --unset