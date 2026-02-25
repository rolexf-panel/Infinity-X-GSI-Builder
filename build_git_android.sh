#!/bin/bash

# --- KONFIGURASI ---
NDK_VERSION="r26b"
GIT_VERSION="2.43.0"
ARCH="aarch64"
API_LEVEL="29" # Android 10+
WORKING_DIR=$(pwd)/git_android_build
INSTALL_DIR=$WORKING_DIR/output

# Warna
GREEN='\033[0;32m'
NC='\033[0m'

set -e # Berhenti jika ada error

mkdir -p $WORKING_DIR
cd $WORKING_DIR

# 1. Download NDK jika belum ada
if [ ! -d "android-ndk-$NDK_VERSION" ]; then
    echo -e "${GREEN}Downloading Android NDK $NDK_VERSION...${NC}"
    wget -q https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip
    unzip -q android-ndk-$NDK_VERSION-linux.zip
fi

NDK_PATH=$WORKING_DIR/android-ndk-$NDK_VERSION
TOOLCHAIN=$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64

# 2. Setup Environment Variables untuk Cross-Compile
export AR=$TOOLCHAIN/bin/llvm-ar
export AS=$TOOLCHAIN/bin/llvm-as
export CC=$TOOLCHAIN/bin/$ARCH-linux-android$API_LEVEL-clang
export CXX=$TOOLCHAIN/bin/$ARCH-linux-android$API_LEVEL-clang++
export LD=$TOOLCHAIN/bin/ld.lld
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip

# 3. Download Source Code Git
if [ ! -d "git-$GIT_VERSION" ]; then
    echo -e "${GREEN}Downloading Git Source $GIT_VERSION...${NC}"
    wget -q https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VERSION.tar.gz
    tar -xf git-$GIT_VERSION.tar.gz
fi

cd git-$GIT_VERSION

# 4. Konfigurasi Build
# Kita mematikan beberapa fitur (TCL/TK, Gettext) agar binary lebih ringan dan portable
echo -e "${GREEN}Configuring Git for Android...${NC}"
make configure
./configure \
    --host=$ARCH-linux-android \
    --prefix=/data/local/tmp/git \
    --with-shell=/system/bin/sh \
    --without-tcltk \
    --without-python \
    ac_cv_fread_reads_directories=yes \
    ac_cv_snprintf_returns_bogus=no

# 5. Compile
echo -e "${GREEN}Compiling... (This may take a while)${NC}"
make -j$(nproc) NO_GETTEXT=YesPlease NO_SVN_TESTS=YesPlease

# 6. Install/Strip Binary
echo -e "${GREEN}Stripping binary to reduce size...${NC}"
$STRIP git

echo -e "${GREEN}BUILD SELESAI! Binary 'git' tersedia di folder:$(pwd)/git${NC}"
