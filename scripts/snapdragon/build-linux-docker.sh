#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/snapdragon-toolchain/arm64-linux:v0.1"
PRESET="arm64-linux-snapdragon-release"
BUILD_DIR="build-snapdragon"
PKG_DIR="pkg-snapdragon"
PLATFORM="linux/amd64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

JOBS="${JOBS:-$(nproc)}"
KEEP_CONTAINER="${KEEP_CONTAINER:-0}"

log() { echo "[build-snapdragon] $*"; }

log "repo     : $REPO_ROOT"
log "image    : $IMAGE"
log "preset   : $PRESET"
log "build dir: $BUILD_DIR"
log "pkg dir  : $PKG_DIR"
log "jobs     : $JOBS"

if [ "$KEEP_CONTAINER" = "1" ]; then
    RM_FLAG=""
else
    RM_FLAG="--rm"
fi

log "pulling toolchain image (first run may take a while)..."
docker pull "$IMAGE"

log "starting build inside container..."
docker run $RM_FLAG \
    --platform "$PLATFORM" \
    -u "$(id -u):$(id -g)" \
    --volume "$REPO_ROOT:/workspace" \
    --workdir /workspace \
    "$IMAGE" bash -lc "
        set -euo pipefail
        echo '--- cp CMakeUserPresets.json ---'
        cp -f docs/backend/snapdragon/CMakeUserPresets.json ./
        echo '--- cmake configure ---'
        cmake --preset $PRESET -B $BUILD_DIR
        echo '--- cmake build ---'
        cmake --build $BUILD_DIR -j $JOBS
        echo '--- cmake install ---'
        cmake --install $BUILD_DIR --prefix $PKG_DIR
        echo '--- artifacts ---'
        ls -la $PKG_DIR/bin $PKG_DIR/lib 2>/dev/null | head -60
        echo '--- htp skels (DSP side) ---'
        ls -la $PKG_DIR/lib/libggml-htp-*.so 2>/dev/null || true
    "

log "build finished"
log "artifacts at: $REPO_ROOT/$PKG_DIR"
log "to run on SA8650P: scp -r $PKG_DIR to board, then:"
log "  export LD_LIBRARY_PATH=./lib ADSP_LIBRARY_PATH=./lib"
log "  ./bin/llama-cli -m <model.gguf> --device HTP0 -ngl 99"
