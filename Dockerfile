# Copyright (c) 2020-2021 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation

ARG NEXE_SHA1=0ba696e976d9031110e995995e7e5ac33c03f91c
ARG NODE_VERSION=14.19.0
FROM alpine:3.13.7 as compiler
ARG NODE_VERSION
ARG TIMEOUT_DELAY
ENV NODE_VERSION=${NODE_VERSION}
ENV TIMEOUT_DELAY=${TIMEOUT_DELAY}
RUN apk add --no-cache curl make gcc g++ binutils-gold python2 linux-headers libgcc libstdc++ git vim tar gzip wget coreutils
RUN mkdir -p /${NODE_VERSION} && \
    curl -sSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.tar.gz | tar -zx --strip-components=1 -C /${NODE_VERSION} && \
    # patch source to work on z until https://github.com/nodejs/node/pull/30199 is merged
    sed -E -i "s|o\['libraries'\] \+= \['-static'\]|o\['libraries'\] \+= \['-static', '-no-pie'\]|g" /${NODE_VERSION}/configure.py

WORKDIR /${NODE_VERSION}

# Add the .cc and .js for deasync
COPY etc/ /${NODE_VERSION}

# configure
RUN ./configure --prefix=/usr --fully-static

# Include the node-gyp module converted to 'builtin' module
RUN \
   # Include .js in the libraries
   sed -i -e "s|    \\'library_files\\': \\[|    \\'library_files\\': \\[\n      \\'lib/deasync.js\\',|" node.gyp && \
   # Include the .cc in src list
   sed -i -e "s|        'src/uv.cc',|        'src/uv.cc',\n        'src/deasync.cc',|" node.gyp && \
   # Include the deasync module in modules list
   sed -i -e "s|  V(messaging)                                                                 \\\|  V(messaging)                                                                 \\\ \n  V(deasync)                                                                   \\\|" src/node_binding.cc

# Compile with a given timeframe
RUN echo "CPU(s): $(getconf _NPROCESSORS_ONLN)" && \
    make -j $(getconf _NPROCESSORS_ONLN) > /tmp/log && make install

# remove node binary
RUN rm out/Release/node

# install specific nexe
WORKDIR /
RUN git clone https://github.com/nexe/nexe
WORKDIR /nexe
RUN git checkout ${NEXE_SHA1} && npm install && npm run build
# Change back to root folder
WORKDIR /

## Add dummy sample to create the all-in-one ready-to-use package
RUN echo "console.log('hello world')" >> index.js

# Build pre-asssembly of nodejs by using nexe and reusing our patched nodejs folder
RUN /nexe/index.js --build --no-mangle --enableNodeCli --temp / -c="--fully-static" -m="-j$(getconf _NPROCESSORS_ONLN)" --target ${NODE_VERSION} -o alpine-x64-14


# ok now make the image smaller with only the binary
FROM scratch as runtime
ARG NEXE_SHA1
ARG NODE_VERSION
ENV NODE_VERSION=${NODE_VERSION}
ENV NEXE_SHA1=${NEXE_SHA1}
COPY --from=compiler /alpine-x64-14 /alpine-x64-14

