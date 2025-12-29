# ============================
# Build Stage
# ============================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Installiere Build-Abhängigkeiten
RUN apt-get update && apt-get install -y \
    git build-essential autoconf automake libtool pkg-config \
    python3 python3-polib wget curl zip unzip ccache \
    libssl-dev libpng-dev libzstd-dev libcap-dev libpam-dev \
    libcups2-dev libfontconfig1-dev libpoco-dev \
    libx11-dev libxext-dev libxrender-dev libxrandr-dev \
    libice-dev libsm-dev libxt-dev libxaw7-dev \
    libcairo2-dev libglu1-mesa-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    gperf default-jdk ant junit4 libgtk-3-dev \
    libdbus-glib-1-dev libxslt1-dev \
    libkrb5-dev libgssapi-krb5-2 libldap2-dev \
    libnss3-dev libnspr4-dev flex bison libcppunit-dev \
    libboost-dev libboost-date-time-dev libboost-filesystem-dev \
    libboost-iostreams-dev libboost-locale-dev \
    libboost-program-options-dev libclucene-dev \
    libxml2-utils xsltproc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

# Clone Repositories (mit Retry-Logik und besserem Error-Handling)
RUN git config --global http.postBuffer 524288000 && \
    git config --global http.maxRequestBuffer 100M && \
    git config --global core.compression 0 && \
    for i in 1 2 3; do \
        git clone --depth 1 --branch co-24.04 \
        https://github.com/CollaboraOnline/core.git libreoffice && break || \
        (echo "Retry $i..." && sleep 5); \
    done && \
    for i in 1 2 3; do \
        git clone --depth 1 --branch co-24.04 \
        https://github.com/CollaboraOnline/online.git collabora && break || \
        (echo "Retry $i..." && sleep 5); \
    done

# Baue LibreOffice Core
WORKDIR /opt/libreoffice
RUN ./autogen.sh && \
    ./configure \
    --with-distro=LibreOfficeOnline \
    --disable-epm \
    --disable-gtk3 \
    --disable-gtk4 \
    --disable-postgresql-sdbc \
    --disable-lotuswordpro \
    --disable-libcmis \
    --disable-coinmp \
    --disable-lpsolve \
    --disable-pdfimport \
    --disable-pdfium \
    --enable-orcus \
    --without-doxygen \
    --without-help \
    --without-helppack-integration \
    --without-myspell-dicts \
    --with-system-libxml \
    --with-system-openssl \
    --with-system-zlib \
    --with-system-libpng \
    --without-java \
    --disable-gstreamer-1-0 \
    && make -j$(nproc)

# Baue Collabora Online
WORKDIR /opt/collabora
RUN ./autogen.sh && \
    ./configure \
    --enable-silent-rules \
    --with-lo-path=/opt/libreoffice/instdir \
    --with-lo-builddir=/opt/libreoffice \
    --disable-setcap \
    && make -j$(nproc)

# ============================
# Runtime Stage
# ============================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Installiere nur Runtime-Abhängigkeiten
RUN apt-get update && apt-get install -y \
    libpoco-dev \
    libssl3 \
    libpng16-16 \
    libcap2 \
    libcups2 \
    libfontconfig1 \
    libcairo2 \
    adduser \
    cpio \
    findutils \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Kopiere kompilierte Binaries und Bibliotheken
COPY --from=builder /opt/libreoffice/instdir /opt/libreoffice/instdir
COPY --from=builder /opt/collabora /opt/collabora

# Erstelle Benutzer
RUN useradd -r -s /bin/bash cool && \
    mkdir -p /opt/cool /opt/collabora/systemplate /opt/collabora/jails && \
    chown -R cool:cool /opt/cool /opt/collabora

# Setze Umgebungsvariablen
ENV LC_CTYPE=C.UTF-8 \
    LD_LIBRARY_PATH=/opt/libreoffice/instdir/program

WORKDIR /opt/collabora

EXPOSE 9980

# Startbefehl
CMD ["./coolwsd", \
     "--o:sys_template_path=/opt/collabora/systemplate", \
     "--o:child_root_path=/opt/collabora/jails", \
     "--o:file_server_root_path=/opt/collabora/browser/dist", \
     "--o:ssl.enable=false", \
     "--o:ssl.termination=true"]