#!/bin/sh

set -e

if [ $# -lt 1 ]; then
    echo $0 dest
    exit 1
fi
PREFIX="$1"
export PATH=$PREFIX/bin:$PATH

: ${CORES:=4}
: ${ARCHS:=${TOOLCHAIN_ARCHS-i686 x86_64 armv7 aarch64}}

if [ ! -d libunwind ]; then
    git clone -b master https://github.com/llvm-mirror/libunwind.git
    CHECKOUT_LIBUNWIND=1
fi
if [ ! -d libcxxabi ]; then
    git clone -b master https://github.com/llvm-mirror/libcxxabi.git
    CHECKOUT_LIBCXXABI=1
fi
if [ ! -d libcxx ]; then
    git clone -b master https://github.com/llvm-mirror/libcxx.git
    CHECKOUT_LIBCXX=1
fi
if [ -n "$SYNC" ] || [ -n "$CHECKOUT_LIBUNWIND" ]; then
    cd libunwind
    [ -z "$SYNC" ] || git fetch
    git checkout 86ab23972978242b6f9e27cebc239f3e8428b1af
    cd ..
fi
if [ -n "$SYNC" ] || [ -n "$CHECKOUT_LIBCXXABI" ]; then
    cd libcxxabi
    [ -z "$SYNC" ] || git fetch
    git checkout 05ba3281482304ae8de31123a594972a495da06d
    cd ..
fi
if [ -n "$SYNC" ] || [ -n "$CHECKOUT_LIBCXX" ]; then
    cd libcxx
    [ -z "$SYNC" ] || git fetch
    git checkout a351d793abce1ecaead0fd947fe17f75b0c41ae5
    cd ..
fi

LIBCXX=$(pwd)/libcxx
MERGE_ARCHIVES=$(pwd)/merge-archives.sh

cd libunwind
for arch in $ARCHS; do
    mkdir -p build-$arch
    cd build-$arch
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$PREFIX/$arch-w64-mingw32 \
        -DCMAKE_C_COMPILER=$arch-w64-mingw32-clang \
        -DCMAKE_CXX_COMPILER=$arch-w64-mingw32-clang++ \
        -DCMAKE_CROSSCOMPILING=TRUE \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_C_COMPILER_WORKS=TRUE \
        -DCMAKE_CXX_COMPILER_WORKS=TRUE \
        -DCMAKE_AR=$PREFIX/bin/llvm-ar \
        -DCMAKE_RANLIB=$PREFIX/bin/llvm-ranlib \
        -DLLVM_NO_OLD_LIBSTDCXX=TRUE \
        -DCXX_SUPPORTS_CXX11=TRUE \
        -DLIBUNWIND_USE_COMPILER_RT=TRUE \
        -DLIBUNWIND_ENABLE_THREADS=TRUE \
        -DLIBUNWIND_ENABLE_SHARED=TRUE \
        -DLIBUNWIND_ENABLE_STATIC=FALSE \
        -DLIBUNWIND_ENABLE_CROSS_UNWINDING=FALSE \
        -DCMAKE_CXX_FLAGS="-nostdinc++ -I$LIBCXX/include" \
        -DCMAKE_SHARED_LINKER_FLAGS="-lpsapi" \
        ..
    make -j$CORES
    make install
    cd ..
done
cd ..

cd libcxxabi
for arch in $ARCHS; do
    mkdir -p build-$arch
    cd build-$arch
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$PREFIX/$arch-w64-mingw32 \
        -DCMAKE_C_COMPILER=$arch-w64-mingw32-clang \
        -DCMAKE_CXX_COMPILER=$arch-w64-mingw32-clang++ \
        -DCMAKE_CROSSCOMPILING=TRUE \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_C_COMPILER_WORKS=TRUE \
        -DCMAKE_CXX_COMPILER_WORKS=TRUE \
        -DCMAKE_AR=$PREFIX/bin/llvm-ar \
        -DCMAKE_RANLIB=$PREFIX/bin/llvm-ranlib \
        -DLIBCXXABI_USE_COMPILER_RT=ON \
        -DLIBCXXABI_ENABLE_EXCEPTIONS=ON \
        -DLIBCXXABI_ENABLE_THREADS=ON \
        -DLIBCXXABI_TARGET_TRIPLE=$arch-w64-mingw32 \
        -DLIBCXXABI_ENABLE_SHARED=OFF \
        -DLIBCXXABI_LIBCXX_INCLUDES=../../libcxx/include \
        -DLLVM_NO_OLD_LIBSTDCXX=TRUE \
        -DCXX_SUPPORTS_CXX11=TRUE \
        -DCMAKE_CXX_FLAGS="-D_LIBCPP_BUILDING_LIBRARY -U_LIBCXXABI_DISABLE_VISIBILITY_ANNOTATIONS" \
        ..
    make -j$CORES
    # Delete stdlib_new_delete.cpp.obj from this archive; this conflicts
    # with new.cpp.obj from libcxx, and that object file has got the same
    # symbols and a few more.
    llvm-ar d lib/libc++abi.a stdlib_new_delete.cpp.obj
    cd ..
done
cd ..

cd libcxx
for arch in $ARCHS; do
    mkdir -p build-$arch
    cd build-$arch
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$PREFIX/$arch-w64-mingw32 \
        -DCMAKE_C_COMPILER=$arch-w64-mingw32-clang \
        -DCMAKE_CXX_COMPILER=$arch-w64-mingw32-clang++ \
        -DCMAKE_CROSSCOMPILING=TRUE \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_C_COMPILER_WORKS=TRUE \
        -DCMAKE_CXX_COMPILER_WORKS=TRUE \
        -DCMAKE_AR=$PREFIX/bin/llvm-ar \
        -DCMAKE_RANLIB=$PREFIX/bin/llvm-ranlib \
        -DLIBCXX_USE_COMPILER_RT=ON \
        -DLIBCXX_INSTALL_HEADERS=ON \
        -DLIBCXX_ENABLE_EXCEPTIONS=ON \
        -DLIBCXX_ENABLE_THREADS=ON \
        -DLIBCXX_HAS_WIN32_THREAD_API=ON \
        -DLIBCXX_ENABLE_MONOTONIC_CLOCK=ON \
        -DLIBCXX_ENABLE_SHARED=ON \
        -DLIBCXX_ENABLE_STATIC=OFF \
        -DLIBCXX_SUPPORTS_STD_EQ_CXX11_FLAG=TRUE \
        -DLIBCXX_HAVE_CXX_ATOMICS_WITHOUT_LIB=TRUE \
        -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
        -DLIBCXX_ENABLE_FILESYSTEM=OFF \
        -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=TRUE \
        -DLIBCXX_ABI_UNSTABLE=TRUE \
        -DLIBCXX_CXX_ABI=libcxxabi \
        -DLIBCXX_CXX_ABI_INCLUDE_PATHS=../../libcxxabi/include \
        -DLIBCXX_CXX_ABI_LIBRARY_PATH=../../libcxxabi/build-$arch/lib \
        -DCMAKE_CXX_FLAGS="-D_LIBCXXABI_BUILDING_LIBRARY" \
        -DCMAKE_SHARED_LINKER_FLAGS="-lunwind -Wl,--export-all-symbols" \
        -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=FALSE \
        ..
    make -j$CORES
    make install
    $MERGE_ARCHIVES \
        $PREFIX/$arch-w64-mingw32/lib/libc++.dll.a \
        $PREFIX/$arch-w64-mingw32/lib/libunwind.dll.a
    cd ..
done
cd ..

ln -sf ../generic-w64-mingw32/include/c++ $PREFIX/include/c++
