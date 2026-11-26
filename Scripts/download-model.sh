#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="RealESRGAN_general_522_fp16"
ARCHIVE_NAME="${MODEL_NAME}.zip"
MODEL_URL="https://github.com/hanxiao/real-esrgan-coreml/releases/download/v1.0.0/${ARCHIVE_NAME}"
MODEL_SHA256="41368af9dcbcc300c0fe0442202acbf98d30dc07c28d49bf656883f7fef3656a"
MODEL_DIR="PhotoClear/Models"
TEMP_DIR="${RUNNER_TEMP:-/tmp}/photoclear-model"

mkdir -p "$MODEL_DIR" "$TEMP_DIR"
rm -rf "$TEMP_DIR"/*
curl --fail --location --retry 3 --retry-delay 2 "$MODEL_URL" --output "$TEMP_DIR/$ARCHIVE_NAME"
echo "$MODEL_SHA256  $TEMP_DIR/$ARCHIVE_NAME" | shasum -a 256 --check
unzip -q "$TEMP_DIR/$ARCHIVE_NAME" -d "$TEMP_DIR/extracted"

MODEL_PATH="$(find "$TEMP_DIR/extracted" -type d -name "${MODEL_NAME}.mlpackage" -print -quit)"
if [[ -z "$MODEL_PATH" ]]; then
  echo "Expected ${MODEL_NAME}.mlpackage was not found in the upstream model archive." >&2
  find "$TEMP_DIR/extracted" -maxdepth 4 -print >&2
  exit 1
fi

rm -rf "$MODEL_DIR/${MODEL_NAME}.mlpackage"
ditto "$MODEL_PATH" "$MODEL_DIR/${MODEL_NAME}.mlpackage"
echo "Installed model package at $MODEL_DIR/${MODEL_NAME}.mlpackage"
