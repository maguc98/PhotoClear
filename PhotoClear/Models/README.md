# Bundled AI model

PhotoClear bundles the **Real-ESRGAN x4plus** Core ML model, a higher-quality RRDBNet model designed for general photographic images. Model package is pinned to the upstream Hugging Face revision and checksum-verified during CI.

- Original model: xinntao/Real-ESRGAN x4plus (BSD-3-Clause)
- Core ML conversion: VincentGOURBIN/RealESRGAN-CoreML
- Model archive: RealESRGAN-x4plus.mlpackage.zip (FP16)
- Input: 256 × 256 RGB Float16
- Output: 1024 × 1024 RGB Float16 (4×)
- Archive SHA-256: 61d44a58bb8549a0c0485c95d2b384c598b48a648231206b3e7c2ac221e64599

The app uses 224px source tiles with 32px overlap and reflected edge padding. 2× export is derived from the 4× model output with local averaging. Photos remain on-device; no runtime model download or upload is performed.
