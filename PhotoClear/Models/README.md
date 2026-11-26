# Bundled AI model

The build workflow downloads the pinned `RealESRGAN_general_522_fp16.mlpackage` model into this directory before generating the Xcode project.

The model is bundled into the application at build time. PhotoClear does not download models or upload photos at runtime, so AI enhancement works offline after installation.

- Upstream Core ML conversion project: https://github.com/hanxiao/real-esrgan-coreml
- Upstream release: https://github.com/hanxiao/real-esrgan-coreml/releases/tag/v1.0.0
- Model variant: `general`, 4× super-resolution, fixed 522×522 input
- Archive SHA-256: `41368af9dcbcc300c0fe0442202acbf98d30dc07c28d49bf656883f7fef3656a`

The app uses overlapping 512px tiles and stitches tile centers to limit peak memory use. 2× output is produced by downsampling the 4× model output per tile.
