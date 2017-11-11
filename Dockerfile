FROM ubuntu:16.04

RUN apt-get update -qq && apt-get install -qqy \
    git wget bzip2 file unzip libtool pkg-config cmake build-essential \
    automake yasm gettext autopoint vim python git-svn ninja-build


RUN git config --global user.name "LLVM MinGW" && \
    git config --global user.email root@localhost

WORKDIR /build/llvm-mingw

ARG CORES=4

ENV TOOLCHAIN_PREFIX=/build/prefix

# Build LLVM
COPY build-llvm.sh .
RUN ./build-llvm.sh $TOOLCHAIN_PREFIX

ENV TOOLCHAIN_ARCHS="i686 x86_64 armv7 aarch64"

# Install the usual $TUPLE-clang binaries
COPY wrappers/*.sh ./wrappers/
COPY install-wrappers.sh .
RUN ./install-wrappers.sh $TOOLCHAIN_PREFIX

# Cheating: Pull windres from the normal binutils package.
# llvm-rc isn't fully usable as a replacement for windres yet.
RUN apt-get update -qq && \
    apt-get install -qqy binutils-mingw-w64-x86-64 && \
    cp /usr/bin/x86_64-w64-mingw32-windres $TOOLCHAIN_PREFIX/bin/x86_64-w64-mingw32-windresreal && \
    apt-get remove -qqy binutils-mingw-w64-x86-64 && \
    cd $TOOLCHAIN_PREFIX/bin

# Build MinGW-w64
COPY build-mingw-w64.sh .
RUN ./build-mingw-w64.sh $TOOLCHAIN_PREFIX

# Build compiler-rt
COPY build-compiler-rt.sh .
RUN ./build-compiler-rt.sh $TOOLCHAIN_PREFIX 6.0.0

# Build C test applications
WORKDIR /build
ENV PATH=$TOOLCHAIN_PREFIX/bin:$PATH

COPY hello/*.c ./hello/
RUN cd hello && \
    for arch in $TOOLCHAIN_ARCHS; do \
        $arch-w64-mingw32-clang hello.c -o hello-$arch.exe || exit 1; \
    done
RUN cd hello && \
    for arch in $TOOLCHAIN_ARCHS; do \
        $arch-w64-mingw32-clang hello-tls.c -o hello-tls-$arch.exe || exit 1; \
    done

WORKDIR /build/llvm-mingw

# Build libunwind/libcxxabi/libcxx
COPY build-libcxx.sh merge-archives.sh ./
RUN ./build-libcxx.sh $TOOLCHAIN_PREFIX

WORKDIR /build

# Build C++ test applications
COPY hello/*.cpp ./hello/
RUN cd hello && \
    for arch in $TOOLCHAIN_ARCHS; do \
        $arch-w64-mingw32-clang++ hello.cpp -o hello-cpp-$arch.exe -fno-exceptions || exit 1; \
    done
RUN cd hello && \
    for arch in $TOOLCHAIN_ARCHS; do \
        $arch-w64-mingw32-clang++ hello-exception.cpp -o hello-exception-$arch.exe || exit 1; \
    done

RUN wget http://www.nasm.us/pub/nasm/releasebuilds/2.13.01/nasm-2.13.01.tar.xz && \
    tar -Jxvf nasm-2.13.01.tar.xz && \
    cd nasm-2.13.01 && \
    ./configure --prefix=/build/prefix && \
    make -j$CORES && \
    make install

COPY winemine/ ./winemine/
# We must build winemine with ucrtbase regardless of what the default is,
# since the arm msvcrt.dll (or the def file in mingw-w64 at least) doesn't
# include _winitenv.
RUN mkdir -p /build/demo/bin && \
    cd winemine && \
    for arch in $TOOLCHAIN_ARCHS; do \
        mkdir build-$arch && \
        cd build-$arch && \
        make -f ../Makefile CROSS=$arch-w64-mingw32- && \
        cp winemine.exe /build/demo/bin/winemine-$arch.exe && \
        cd .. || exit 1; \
    done

ENV TEST_ARCH=armv7
ENV TEST_TRIPLET=$TEST_ARCH-w64-mingw32
ENV TEST_ROOT=/build/demo
ENV PKG_CONFIG_LIBDIR=/build/demo/lib/pkgconfig

RUN git clone http://git.xiph.org/speex.git/ && \
    cd speex && \
    git checkout 243470fb39e8a5712b5d01c3bf5631081a640a0d && \
    ./autogen.sh

RUN cd speex && \
    ./configure --prefix=$TEST_ROOT --host=$TEST_TRIPLET --enable-shared && \
    make -j4 && \
    make install

RUN git clone git://git.videolan.org/x264.git && \
    cd x264 && \
    git checkout b00bcafe53a166b63a179a2f41470cd13b59f927

RUN cd x264 && \
    case $TEST_ARCH in \
    armv7) \
        export AS="./tools/gas-preprocessor.pl -arch arm -as-type clang -force-thumb -- armv7-w64-mingw32-clang -mimplicit-it=always" \
        ;; \
    aarch64) \
        export AS="aarch64-w64-mingw32-clang" \
        ;; \
    esac && \
    CC="$TEST_TRIPLET-gcc" STRIP="" AR="llvm-ar" RANLIB="llvm-ranlib" ./configure --host=$TEST_TRIPLET --enable-shared --prefix=$TEST_ROOT && \
    make -j4 && \
    make install

RUN git clone git://git.libav.org/libav.git && \
    cd libav && \
    git checkout c6558e8840fbb2386bf8742e4d68dd6e067d262e

RUN cd libav && \
    mkdir build && cd build && \
    ../configure --prefix=$TEST_ROOT --arch=$TEST_ARCH --target-os=mingw32 --cross-prefix=$TEST_TRIPLET- --enable-cross-compile --enable-gpl --enable-shared --enable-libspeex --enable-libx264 --pkg-config=pkg-config --extra-cflags="-DX264_API_IMPORTS" && \
    make -j4 && \
    make install

RUN wget http://zlib.net/zlib-1.2.11.tar.gz && \
    tar -zxvf zlib-1.2.11.tar.gz

RUN cd zlib-1.2.11 && \
    make -f win32/Makefile.gcc PREFIX=$TEST_TRIPLET- SHARED_MODE=1 -j4 && \
    make -f win32/Makefile.gcc install SHARED_MODE=1 INCLUDE_PATH=$TEST_ROOT/include LIBRARY_PATH=$TEST_ROOT/lib BINARY_PATH=$TEST_ROOT/bin

RUN wget https://curl.haxx.se/download/curl-7.56.1.tar.xz && \
    tar -Jxvf curl-7.56.1.tar.xz

RUN cd curl-7.56.1 && \
    ./configure --prefix=$TEST_ROOT --host=$TEST_TRIPLET --enable-shared --with-winssl --with-zlib=$TEST_ROOT && \
    make -j4 && \
    make install

RUN wget http://download.qt.io/official_releases/qt/5.7/5.7.1/submodules/qtbase-opensource-src-5.7.1.tar.xz && \
    tar -Jxvf qtbase-opensource-src-5.7.1.tar.xz

COPY patches/qt-*.patch /build/patches/
RUN cd qtbase-opensource-src-5.7.1 && \
    for i in /build/patches/qt-*.patch; do \
        patch -p1 < $i || exit 1; \
    done && \
    ./configure -xplatform win32-g++ -device-option CROSS_COMPILE=$TEST_TRIPLET- -release -opensource -confirm-license -no-opengl -nomake examples -silent -prefix $TEST_ROOT && \
    make -j4 && \
    make install

RUN for exec in moc qmake rcc uic; do \
        cp /build/demo/bin/$exec /build/prefix/bin; \
    done

RUN mkdir -p /build/demo/bin/platforms && \
    cp /build/demo/plugins/platforms/qwindows.dll /build/demo/bin/platforms

RUN cd qtbase-opensource-src-5.7.1/examples/widgets/widgets/analogclock && \
    qmake && \
    make -j4 && \
    cp release/analogclock.exe /build/demo/bin
