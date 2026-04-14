#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-${ROOT_DIR}/build-java}"

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is not available in PATH." >&2
  echo "Install CMake or run from an environment where cmake is configured." >&2
  exit 1
fi

cmake -S "${ROOT_DIR}" -B "${BUILD_DIR}" -DMSAL4J_BUILD_SAMPLES=OFF
cmake --build "${BUILD_DIR}" --target JavaBridgeArtifacts

echo
echo "Java bridge artifacts:"
echo "  ${BUILD_DIR}"