#!/usr/bin/env bash
# Build llama.cpp with ggml-hexagon backend for SA8650P (glibc 2.35, DSP v73).
#
# Toolchain (reuses the byuns-rust-toolchain image + hexagon-sdk-6.6):
#   - Host-side ARM64: aarch64-oe-linux-gcc 11.4.0 from the
#     byuns_g300_8650p_linux-v73_2.35 base image. Its OE sysroot is glibc 2.35
#     (matches the SA8650P board), and it ships a complete GCC toolchain
#     (crt, libgcc, libstdc++ headers) -> no clang/sysroot stitching needed.
#   - DSP-side htp skels (libggml-htp-v73.so etc.): hexagon-clang from
#     hexagon-sdk-6.6/tools/HEXAGON_Tools/19.0.07. SDK 6.6 is required by the
#     current ggml-hexagon source (5.5 lacks qaic/bin/qaic layout and the
#     MAX_DOMAIN_NAMELEN define).
#   - Hexagon SDK 6.6 + Tools are mounted from the host; the image only
#     supplies the OE GCC toolchain, cmake/ninja/ccache, and python.

set -euo pipefail

IMAGE="byuns-rust-toolchain:local"
PLATFORM="linux/amd64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QUAL_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

HEXAGON_SDK_ROOT_HOST="${HEXAGON_SDK_ROOT_HOST:-${QUAL_DIR}/hexagon-sdk-6.6}"
HEXAGON_TOOLS_ROOT_HOST="${HEXAGON_TOOLS_ROOT_HOST:-${HEXAGON_SDK_ROOT_HOST}/tools/HEXAGON_Tools/19.0.07}"

TOOLCHAIN_FILE="cmake/arm64-linux-oe-sysroot.cmake"
BUILD_DIR="${BUILD_DIR:-build-snapdragon-oe}"
PKG_DIR="${PKG_DIR:-pkg-snapdragon-oe}"
JOBS="${JOBS:-$(nproc)}"

log() { echo "[build-llama-oe] $*"; }

log "repo             : $REPO_ROOT"
log "image            : $IMAGE  (OE GCC 11.4, glibc 2.35 sysroot)"
log "hexagon sdk      : $HEXAGON_SDK_ROOT_HOST  (mounted at /opt/hexagon-sdk)"
log "hexagon tools    : $HEXAGON_TOOLS_ROOT_HOST  (mounted at /opt/hexagon-tools)"
log "toolchain file   : $TOOLCHAIN_FILE"
log "build dir        : $BUILD_DIR"
log "pkg dir          : $PKG_DIR"
log "jobs             : $JOBS"

[ -f "$REPO_ROOT/$TOOLCHAIN_FILE" ] || { echo "FATAL: toolchain file missing: $TOOLCHAIN_FILE"; exit 1; }
[ -d "$HEXAGON_SDK_ROOT_HOST" ]   || { echo "FATAL: hexagon sdk not found: $HEXAGON_SDK_ROOT_HOST"; exit 1; }
[ -d "$HEXAGON_TOOLS_ROOT_HOST" ] || { echo "FATAL: hexagon tools not found: $HEXAGON_TOOLS_ROOT_HOST"; exit 1; }

mkdir -p "$REPO_ROOT/.ccache"

log "starting build inside container..."
docker run --rm \
    --platform "$PLATFORM" \
    -u "$(id -u):$(id -g)" \
    --volume "$REPO_ROOT":/workspace \
    --volume "$HEXAGON_SDK_ROOT_HOST":/opt/hexagon-sdk:ro \
    --volume "$HEXAGON_TOOLS_ROOT_HOST":/opt/hexagon-tools:ro \
    -e CCACHE_DIR=/workspace/.ccache \
    --workdir /workspace \
    "$IMAGE" bash -lc '
        set -euo pipefail
        echo "--- toolchain check ---"
        aarch64-oe-linux-gcc --version | head -1
        strings /usr/local/oecore-x86_64/sysroots/cortexa78c-oe-linux/lib/libc.so.6 | grep -E "GNU C Library|GNU libc" | head -1
        echo "--- cmake configure ---"
        cmake -S . -B '"$BUILD_DIR"' -G Ninja \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_TOOLCHAIN_FILE='"$TOOLCHAIN_FILE"' \
            -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
            -DCMAKE_INSTALL_RPATH='\''$ORIGIN;$ORIGIN/..'\'' \
            -DCMAKE_C_COMPILER_LAUNCHER=ccache \
            -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
            -DGGML_HEXAGON=ON \
            -DGGML_OPENCL=OFF \
            -DGGML_OPENMP=OFF \
            -DGGML_LLAMAFILE=OFF \
            -DLLAMA_OPENSSL=OFF \
            -DHEXAGON_SDK_ROOT=/opt/hexagon-sdk \
            -DHEXAGON_TOOLS_ROOT=/opt/hexagon-tools \
            -DPREBUILT_LIB_DIR=linux_aarch64
        echo "--- cmake build ---"
        cmake --build '"$BUILD_DIR"' -j '"$JOBS"'
        echo "--- cmake install ---"
        rm -rf '"$PKG_DIR"'
        cmake --install '"$BUILD_DIR"' --prefix '"$PKG_DIR"'
        echo "--- artifacts ---"
        ls -la '"$PKG_DIR"'/bin/llama-cli '"$PKG_DIR"'/bin/llama-bench '"$PKG_DIR"'/bin/test-backend-ops 2>/dev/null
        echo "--- htp skels (DSP side, v73 = SA8650P) ---"
        ls -la '"$PKG_DIR"'/lib/libggml-htp-*.so 2>/dev/null
        echo "--- glibc symbol check (max must be <= 2.35) ---"
        for so in '"$PKG_DIR"'/lib/libggml-hexagon.so '"$PKG_DIR"'/lib/libllama.so.0 '"$PKG_DIR"'/lib/libggml-common.so '"$PKG_DIR"'/bin/llama-cli; do
            [ -e "$so" ] && echo "  $so : max $(readelf -d "$so" 2>/dev/null | grep -oE '\''GLIBC_2\.[0-9]+'\'' | sort -V | tail -1)"
        done
    '

log "build finished"
log "artifacts at: $REPO_ROOT/$PKG_DIR"
log "deploy to board: tar czf ${PKG_DIR}.tar.gz $PKG_DIR  &&  scp to SA8650P"
log "on board: export LD_LIBRARY_PATH=./lib ADSP_LIBRARY_PATH=./lib"
log "          ./bin/llama-cli -m <model.gguf> --device HTP0 -ngl 99"
