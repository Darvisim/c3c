ARG ARCH
FROM termux/termux-docker:${ARCH}

ENV ANDROID_ROOT=/system \
    ANDROID_DATA=/data \
    PREFIX=/data/data/com.termux/files/usr \
    HOME=/data/data/com.termux/files/home \
    PATH=/data/data/com.termux/files/usr/bin \
    TMPDIR=/data/data/com.termux/files/usr/tmp \
    LANG=en_US.UTF-8 \
    TZ=UTC

RUN chmod -R 755 ${PREFIX}/bin || true && \
    /entrypoint.sh pkg update -y && \
    /entrypoint.sh pkg install -y nodejs-lts tar git

RUN mkdir -p /__e/node20/bin /__e/node24/bin && \
    ln -sf ${PREFIX}/bin/node /__e/node20/bin/node && \
    ln -sf ${PREFIX}/bin/node /__e/node24/bin/node

RUN mkdir -p /usr/bin /bin || true && \
    ln -sf ${PREFIX}/bin/env /usr/bin/env || true && \
    ln -sf ${PREFIX}/bin/bash /usr/bin/bash || true && \
    ln -sf ${PREFIX}/bin/sh /bin/sh || true
