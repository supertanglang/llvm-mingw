LLVM MinGW
==========

This is a recipe for reproducibly building a
[LLVM](https://llvm.org)/[Clang](https://clang.llvm.org/)/[LLD](https://lld.llvm.org/)
based mingw-w64 toolchain.

Benefits of a LLVM based MinGW toolchain are:
- Support for targeting ARM/ARM64 (while GCC obviously does support
  these architectures, it doesn't support Windows on ARM)
- A single toolchain targeting all four architectures (i686, x86_64,
  armv7 and arm64) instead of separate compiler binaries for each
  architecture
- Support for generating debug info in PDB format

Clang on its own can also be used as compiler in the normal GNU binutils
based environments though, so the main difference lies in replacing
binutils with LLVM based tools.

This is similar to https://github.com/martell/mingw-w64-clang, with
the exact same goal but with a slightly different mechanism for
building it, allowing a full from-scratch build of all components
in one command.

The toolchain can be reproducibly built into a Docker image, or be
built and installed in the host environment (currently only tested
on Linux and macOS).

To build and install all components, just do:

    ./build-all.sh <target-dir>

To reduce the size of the installation, removing some files that
aren't necessary after building, run:

    ./strip-llvm.sh <target-dir>

To build a Docker image with the toolchain, run:

    docker build .

Individual components of the toolchain can be (re)built by running
the standalone shellscripts listed within `build-all.sh`. However, if
the source already is checked out, no effort is made to check out a
different version (if the build scripts have been updated to prefer
a different version) - and likewise, if configure flags in the build-*.sh
scripts have changed, you might need to wipe the build directory under
each project for the new configure options to be taken into use.



Status
------

The toolchain currently does support both C and C++, including support
for exception handling.

It is in practice quite new and immature and haven't been proven with a
large number of projects yet though. You will probably run into issues
building non-trivial projects.


Known issues
------------

LLD, the LLVM linker, is what causes most of the major differences to the
normal GCC/binutils based MinGW.

- LLD doesn't support using import libraries created by GNU tools.
- LLD doesn't automatically fix up use of data symbols from DLLs without
  the dllimport attributes.
- The C++ libraries ([libcxxabi](http://libcxxabi.llvm.org/), [libcxx](http://libcxx.llvm.org/)) can only be linked statically
  at the moment.
- The windres replacement, llvm-rc, isn't very mature and doesn't support
  everything that GNU windres does.

Additionally, one may run into other minor differences between GCC and clang.

PDB support
-----------

LLVM does [support](http://blog.llvm.org/2017/08/llvm-on-windows-now-supports-pdb-debug.html)
generating debug info in the PDB format. Since GNU binutils based mingw
environments don't support this, there's no predecent for what command
line parameters to use for this, and llvm-mingw produces debug info in
DWARF format by default.

To produce debug info in PDB format, you currently need to do the following
changes:

- Add `-gcodeview` to the compilation commands (e.g. in
  `wrappers/clang-target-wrapper.sh`), together with using `-g` as usual to
  enable debug info in general.
- Add `-Wl,-pdb,module.pdb` to linking commands.

Even though LLVM supports this, there are a few caveats with using it when
building in MinGW mode:

- Call stack unwinding on x86_64 requires the binaries to be built with SEH.
  This toolchain currently uses DWARF for exception unwinding instead of SEH,
  since libcxxabi doesn't support unwinding using SEH. Thus currently, on
  x86_64, one can only inspect the actual crashed function, not callers further
  up. On i686, things seem to work fine though.
- Microsoft debuggers might have assumptions about the C++ ABI used, which
  doesn't hold up with the Itanium ABI used in MinGW.
- This is unimplemented for the armv7 target, and while implemented for aarch64,
  it doesn't seem to work properly there yet.
