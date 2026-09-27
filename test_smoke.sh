#!/usr/bin/env bash
set -euo pipefail

# root is this plugin directory (moved out of containers/music-deconvolution);
# the build context ships the Dockerfile, music_runner.R, and .dockerignore.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

command -v podman >/dev/null || {
  echo "missing required command: podman" >&2
  exit 1
}

# Image references are self-contained: the deleted AUTONOMICS_IMAGE_PREFIX
# indirection is not honored here.
IMAGE_NAME=${IMAGE_NAME:-"ghcr.io/auto-nomics/autonomics/music-deconvolution:1.0.0"}
LOCAL_TAG=${LOCAL_TAG:-"localhost/atc/music-deconvolution:1.0.0"}
BUILD_FLAGS=${BUILD_FLAGS:---no-cache}
PUSH=${PUSH:-1}

echo ">>> podman build $LOCAL_TAG"
podman build $BUILD_FLAGS \
  -f "$root/Dockerfile" \
  -t "$LOCAL_TAG" \
  "$root"

echo ">>> verify pinned statistical runtime"
podman run --rm --network=none --entrypoint Rscript "$LOCAL_TAG" --vanilla -e '
  stopifnot(
    getRversion() == "4.5.3",
    packageVersion("MuSiC") == "1.0.0",
    packageVersion("TOAST") >= "1.24.0",
    packageVersion("SingleCellExperiment") >= "1.32.0"
  )
'

if [[ "$PUSH" == 0 ]]; then
  echo ">>> PUSH=0: skipping podman push $IMAGE_NAME"
  exit 0
fi

echo ">>> podman push $IMAGE_NAME"
podman tag "$LOCAL_TAG" "$IMAGE_NAME"
podman push "$IMAGE_NAME"
REMOTE_REF=$(podman image inspect --format '{{index .RepoDigests 0}}' "$IMAGE_NAME")
REMOTE_DIGEST=${REMOTE_REF#*@}
echo "published digest: $REMOTE_DIGEST"
