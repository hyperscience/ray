FROM ubuntu:18.04

ARG BAZEL_VERSION=1.2.1
ARG BAZEL_FILENAME=bazel-${BAZEL_VERSION}-installer-linux-x86_64.sh

# Install bazel 1.2.1
RUN apt-get update && apt-get install -y openjdk-11-jdk g++ unzip zip curl
RUN curl -L -o ${BAZEL_FILENAME} https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/${BAZEL_FILENAME}
RUN chmod +x ${BAZEL_FILENAME}
RUN ./${BAZEL_FILENAME}

# Install pyenv and python 3.7
RUN apt-get update && DEBIAN_FRONTEND="noninteractive" apt-get install -y make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev \
    libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev python-openssl git

RUN git clone https://github.com/pyenv/pyenv.git ~/.pyenv
ENV HOME /root
ENV PYENV_ROOT $HOME/.pyenv
ENV PATH $PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH

RUN bash -c 'pyenv install 3.7.7 && pyenv global 3.7.7'

ADD ./ /root/ray
WORKDIR /root/ray/python
RUN pip install wheel

RUN mkdir /tmp/hs_dist
