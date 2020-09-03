# Copyright (c) 2020 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation

ARG NEXE_VERSION=v4.0.0-beta.14
ARG NODE_VERSION=12.18.3
# around 5 hours delay
ARG TIMEOUT_DELAY=20000
FROM alpine:3.12.0 as precompiler
ARG NODE_VERSION
ARG NEXE_VERSION
ARG TIMEOUT_DELAY
ENV NODE_VERSION=${NODE_VERSION}
ENV NEXE_VERSION=${NEXE_VERSION}
ENV TIMEOUT_DELAY=${TIMEOUT_DELAY}
RUN apk add --no-cache curl make gcc g++ binutils-gold python2 linux-headers libgcc libstdc++ git vim tar gzip wget coreutils
RUN mkdir /${NODE_VERSION} && \
    curl -sSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.tar.gz | tar -zx --strip-components=1 -C /${NODE_VERSION}

WORKDIR /${NODE_VERSION}

# patch source to work on z until https://github.com/nodejs/node/pull/30199 is merged
RUN if [[ "$(uname -m)" == "s390x" ]] ; then sed -E -i "s|o\['libraries'\] \+= \['-static'\]|o\['libraries'\] \+= \['-static', '-no-pie'\]|g" configure.py ; fi

# Add the .cc and .js for deasync
COPY etc/ /${NODE_VERSION}

#change timestamp
RUN find /${NODE_VERSION} -print0 | xargs -0 touch -a -m -t 202001010000.00

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
    timeout -s SIGINT ${TIMEOUT_DELAY} make -j $(getconf _NPROCESSORS_ONLN) || echo "build aborted"

FROM alpine:3.12.0 as compiler
ARG NODE_VERSION
ARG NEXE_VERSION
ENV NODE_VERSION=${NODE_VERSION}
ENV NEXE_VERSION=${NEXE_VERSION}
RUN apk add --no-cache make gcc g++ binutils-gold python2 linux-headers libgcc libstdc++ git vim tar gzip wget
COPY --from=precompiler /${NODE_VERSION} /${NODE_VERSION}
RUN find /${NODE_VERSION} -print0 | xargs -0 touch -a -m -t 202001010000.00
WORKDIR /${NODE_VERSION}

# resume compilation
RUN make -j 8 -&& make install

# install nexe
RUN npm install -g nexe@${NEXE_VERSION}

# remove node binary
RUN rm out/Release/node

# Change back to root folder
WORKDIR /

## Add dummy sample to create the all-in-one ready-to-use package
RUN echo "console.log('hello world')" >> index.js

# Build pre-asssembly of nodejs by using nexe and reusing our patched nodejs folder
RUN nexe --build --no-mangle --temp / -c="--fully-static" -m="-j$(getconf _NPROCESSORS_ONLN)" --target ${NODE_VERSION} -o pre-assembly-nodejs-static

# ok now make the image smaller with only the binary
FROM alpine:3.12.0 as runtime
COPY --from=compiler /pre-assembly-nodejs-static /pre-assembly-nodejs-static

