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

MODEL_PATH="$(find "$TEMP_DIR/extracted" -type d -name "RealESRGAN-x4plus.mlpackage" -print -quit)"
if [[ -z "$MODEL_PATH" ]]; then
  echo "Expected RealESRGAN-x4plus.mlpackage was not found in the upstream model archive." >&2
  find "$TEMP_DIR/extracted" -maxdepth 4 -print >&2
  exit 1
fi

rm -rf "$MODEL_DIR/${MODEL_NAME}.mlpackage"
ditto "$MODEL_PATH" "$MODEL_DIR/${MODEL_NAME}.mlpackage"
echo "Installed model package at $MODEL_DIR/${MODEL_NAME}.mlpackage"

# DAT2 realistic photo-detail restoration model (precompiled Core ML).
DAT2_NAME="DAT2_Detail"
DAT2_ARCHIVE="4xBHI_dat2_real_512_coreml_compiled.zip"
DAT2_URL="https://huggingface.co/333i/4xBHI_dat2_real-coreml-ios/resolve/42faaf00b48369a9a97a4378e3044a899264c20e/4xBHI_dat2_real_512_coreml_compiled.zip"
DAT2_SHA256="931a1be9a581af6c2b2f125a0b4ddf6a8ee46553e2b3d467765ac64e587c50f2"
DAT2_TEMP="$TEMP_DIR/dat2"

mkdir -p "$DAT2_TEMP"
curl --fail --location --retry 3 --retry-delay 2 "$DAT2_URL" --output "$DAT2_TEMP/$DAT2_ARCHIVE"
echo "$DAT2_SHA256  $DAT2_TEMP/$DAT2_ARCHIVE" | shasum -a 256 --check
unzip -q "$DAT2_TEMP/$DAT2_ARCHIVE" -d "$DAT2_TEMP/extracted"

DAT2_MODEL_PATH="$(find "$DAT2_TEMP/extracted" -type d -name '*.mlmodelc' -print -quit)"
if [[ -z "$DAT2_MODEL_PATH" ]]; then
  echo "Compiled DAT2 .mlmodelc model was not found in the upstream archive." >&2
  find "$DAT2_TEMP/extracted" -maxdepth 5 -print >&2
  exit 1
fi

rm -rf "$MODEL_DIR/$DAT2_NAME.mlmodelc"
ditto "$DAT2_MODEL_PATH" "$MODEL_DIR/$DAT2_NAME.mlmodelc"
echo "Installed bundled DAT2 model at $MODEL_DIR/$DAT2_NAME.mlmodelc"
