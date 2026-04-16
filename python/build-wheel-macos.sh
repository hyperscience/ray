#!/bin/bash

# Cause the script to exit if a single command fails.
set -e

# Show explicitly which commands are currently running.
set -x

function is_arm_mac() {
  if [[ $(sysctl -n machdep.cpu.brand_string) =~ "Apple" ]]; then
    echo true
  else
    echo false
  fi
}

DOWNLOAD_DIR=python_downloads

NODE_VERSION="14"

if [ ${#PY_MMS[@]} -eq 0 ]; then
  PY_MMS=("3.11" "3.12" "3.13")
fi

VENV_ROOT="$HOME/.ray_venvs"

# Download and install Bazel
if [[ $(is_arm_mac) == "true" ]]; then
  curl -f -s -L -R -o $HOME/bin/bazel https://github.com/bazelbuild/bazelisk/releases/download/v1.16.0/bazelisk-darwin-arm64
else
  curl -f -s -L -R -o $HOME/bin/bazel https://github.com/bazelbuild/bazelisk/releases/download/v1.16.0/bazelisk-darwin-amd64
fi

chmod +x $HOME/bin/bazel
export PATH=$PATH:$HOME/bin

# Provide the build with the correct paths for bazel
echo "export PATH=$PATH" >> ~/.bash_profile

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
  if ! pyenv versions --bare | grep -qE "^${PY_MM}\.[0-9]+$"; then
    pyenv install -f "$PY_MM"
  fi

  # Use the exact pyenv-installed Python for the venv
  PYTHON_EXE="$(pyenv prefix "$PY_MM")/bin/python"

  # Remove old venv and create new one with the correct Python
  rm -rf "$VENV_PATH"
  $PYTHON_EXE -m venv "$VENV_PATH"
  source "$VENV_PATH/bin/activate"

  # NOTE: venv activates the correct PATH instead.
  PIP_CMD=pip

  $PIP_CMD install --upgrade pip

  if [ -z "${TRAVIS_COMMIT}" ]; then
    TRAVIS_COMMIT=${BUILDKITE_COMMIT}
  fi

  pushd python
    $PIP_CMD install -q setuptools==80.9.0 cython==3.0.12 wheel
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
    $PIP_CMD wheel -v -w dist . --no-deps
    # Disabled because we don't use this.
    # build ray-cpp wheel
    # RAY_INSTALL_CPP=1 $PIP_CMD wheel -q -w dist . --no-deps
    mv dist/*.whl ../.whl/
  popd

  # cleanup
  deactivate
  rm -rf "$VENV_PATH"
done

pyenv local --unset
