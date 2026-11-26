# PhotoClear

Offline-first iOS photo enhancement and restoration app. Photo processing is designed to happen on-device—no photo uploads, cloud processing, or API keys.

## Goals
- Native SwiftUI interface
- Local image enhancement pipeline
- Before/after comparison
- Export enhanced images to Photos
- Core Image / Metal acceleration
- Core ML enhancement models (planned)
- Optimized for older devices, starting with iPhone 12 mini (A14)

## Development roadmap
1. App shell, photo picker, preview, compare, save
2. Local enhancement pipeline (denoise, sharpening, exposure/color)
3. Core ML model integration and 2x super-resolution
4. Portrait restoration, 4x upscale, batch and history

## Privacy
The app is intended to work offline. Imported photos stay on-device.

## Status
Initial project setup. No app build is available yet.
