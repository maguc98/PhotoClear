# Bundled AI model

PhotoClear bundles the **Real-ESRGAN x4plus** Core ML model, a higher-quality RRDBNet model designed for general photographic images. Model package is pinned to the upstream Hugging Face revision and checksum-verified during CI.

- Original model: xinntao/Real-ESRGAN x4plus (BSD-3-Clause)
- Core ML conversion: VincentGOURBIN/RealESRGAN-CoreML
- Model archive: RealESRGAN-x4plus.mlpackage.zip (FP16)
- Input: 256 × 256 RGB Float16
- Output: 1024 × 1024 RGB Float16 (4×)
- Archive SHA-256: 61d44a58bb8549a0c0485c95d2b384c598b48a648231206b3e7c2ac221e64599

The app uses 224px source tiles with 32px overlap and reflected edge padding. 2× export is derived from the 4× model output with local averaging. Photos remain on-device; no runtime model download or upload is performed.

## DAT2 detail reconstruction model

PhotoClear also bundles the **4xBHI_dat2_real** Core ML model as an optional second photo-restoration engine.

- Original model and weights: Philip Hofmann, [Phips/4xBHI_dat2_real](https://huggingface.co/Phips/4xBHI_dat2_real)
- Core ML export: [333i/4xBHI_dat2_real-coreml-ios](https://huggingface.co/333i/4xBHI_dat2_real-coreml-ios)
- Pinned export revision: `42faaf00b48369a9a97a4378e3044a899264c20e`
- Runtime bundle name: `DAT2_Detail.mlmodelc`
- Input: 512 × 512 RGB image
- Output: 2048 × 2048 RGB image (4×)
- Precision: FP16; compute units: CPU, GPU, and Neural Engine
- Model archive SHA-256: `931a1be9a581af6c2b2f125a0b4ddf6a8ee46553e2b3d467765ac64e587c50f2`
- Weights license: CC BY 4.0; attribution is recorded in [LICENSES/DAT2.md](../../LICENSES/DAT2.md)

DAT2 is used as an alternative to Real-ESRGAN, not chained after it. The app processes the image in overlapping 512px tiles and uses a conservative source-image blend to reduce color and structure drift. 2× output is downsampled from the 4× result; 8× and 12× outputs use additional Lanczos resizing.

The CI workflow downloads and checksum-verifies the precompiled model during the build, then copies the compiled model into the app bundle before packaging the IPA. **There is no model download after installation**, and inference runs locally. The model targets photographic restoration (noise, mild blur, JPEG/WebP artifacts); it can improve plausible cloth, hair, and other textures, but it cannot guarantee recovery of details absent from the source image.
