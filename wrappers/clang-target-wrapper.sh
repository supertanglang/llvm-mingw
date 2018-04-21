#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$(basename $0 | sed 's/-[^-]*$//')"
EXE=$(basename $0 | sed 's/.*-\([^-]*\)/\1/')
case $EXE in
clang++|g++)
    DRIVER_MODE=--driver-mode=g++
    ;;
esac
# Allow setting e.g. CCACHE=1 to wrap all building in ccache.
if [ -n "$CCACHE" ]; then
    CCACHE=ccache
fi
$CCACHE $DIR/clang $DRIVER_MODE --config $TARGET.cfg "$@"
