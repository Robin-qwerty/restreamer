#!/bin/sh

# Build the Restreamer image on this machine from the two repositories:
#   - this bundle repository (Robin-qwerty/restreamer)
#   - the UI fork (Robin-qwerty/restreamer-ui), checked out next to it by default
#
# Usage: scripts/build-local.sh [cuda|cuda-ffmpeg8|default] [path to restreamer-ui]
#
#   cuda          FFmpeg 6.1 with NVIDIA NVENC, needs NVIDIA driver >= 515 (recommended)
#   cuda-ffmpeg8  FFmpeg 8.1 with NVIDIA NVENC and the core dev build, needs NVIDIA driver >= 570
#   default       CPU only (x264)
#
# The core and FFmpeg images are the same as in .github/workflows/build_custom.yaml.

set -e

VARIANT=${1:-cuda}
BUNDLE_DIR=$(cd "$(dirname "$0")/.." && pwd)
UI_DIR=${2:-$BUNDLE_DIR/../restreamer-ui}

case "$VARIANT" in
	cuda)
		CORE_IMAGE=datarhei/base:core16.16.0-ubuntu22.04
		FFMPEG_IMAGE=datarhei/base:ffmpeg6.1.1-cuda-ubuntu22.04-cuda11.7.1
		;;
	cuda-ffmpeg8)
		CORE_IMAGE=datarhei/base:core-dev-ubuntu24.04
		FFMPEG_IMAGE=datarhei/base:ffmpeg8.1.2-cuda-ubuntu24.04-cuda12.9.1
		;;
	default)
		CORE_IMAGE=datarhei/base:core16.16.0-alpine3.20
		FFMPEG_IMAGE=datarhei/base:ffmpeg6.1.1-alpine3.20
		;;
	*)
		echo "Unknown variant '$VARIANT', use cuda, cuda-ffmpeg8 or default" >&2
		exit 1
		;;
esac

if [ ! -f "$UI_DIR/Dockerfile" ] || [ ! -f "$UI_DIR/package.json" ]; then
	echo "restreamer-ui not found in '$UI_DIR'" >&2
	echo "Clone it next to this repository or pass its path as the second argument." >&2
	exit 1
fi

UI_DIR=$(cd "$UI_DIR" && pwd)
UI_REV=$(git -C "$UI_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
BUNDLE_REV=$(git -C "$BUNDLE_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
UI_IMAGE=restreamer-ui:local
IMAGE=restreamer:$VARIANT-local

echo "==> Building the UI from $UI_DIR ($UI_REV)"
docker build -t "$UI_IMAGE" "$UI_DIR"

echo "==> Building $IMAGE (bundle $BUNDLE_REV, $CORE_IMAGE, $FFMPEG_IMAGE)"
docker build \
	--build-arg RESTREAMER_UI_IMAGE="$UI_IMAGE" \
	--build-arg CORE_IMAGE="$CORE_IMAGE" \
	--build-arg FFMPEG_IMAGE="$FFMPEG_IMAGE" \
	--label "restreamer.ui.revision=$UI_REV" \
	--label "restreamer.bundle.revision=$BUNDLE_REV" \
	-t "$IMAGE" \
	"$BUNDLE_DIR"

echo
echo "Done. Use this image in the .env file next to docker-compose.yml:"
echo
echo "    RESTREAMER_IMAGE=$IMAGE"
echo
echo "Then (re)start with: docker compose up -d"
