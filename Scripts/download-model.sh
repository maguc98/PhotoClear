#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="RealESRGAN_x4plus_fp16"
ARCHIVE_NAME="${MODEL_NAME}.zip"
MODEL_URL="https://huggingface.co/VincentGOURBIN/RealESRGAN-CoreML/resolve/78493a5ce26d2674d5ff705d250446f4884cd533/RealESRGAN-x4plus.mlpackage.zip"
MODEL_SHA256="61d44a58bb8549a0c0485c95d2b384c598b48a648231206b3e7c2ac221e64599"
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
