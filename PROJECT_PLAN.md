# PhotoClear development plan

## MVP (v0.1)
- [x] Repository and product direction
- [ ] SwiftUI app shell and visual identity
- [ ] Import one image from Photos
- [ ] Preview original image
- [ ] Local enhancement presets: Natural, Clear, Portrait (initially filter-based)
- [ ] Before/after comparison
- [ ] Export to Photos
- [ ] Basic processing progress and error states

## Enhancement engine
### First iteration (no ML model required)
Core Image filters, all on device:
- Noise reduction
- Sharpening
- Exposure and shadow tuning
- Color balance / saturation restraint

### ML iteration
Evaluate lightweight Core ML image restoration / super-resolution models. Benchmark memory, latency, and quality on A14-class hardware before choosing a default model.

## Design principles
- Soft, light, polished interface
- Clear photo-first layout
- No cluttered professional controls
- Preserve original; never overwrite source
- Avoid artificial halos, over-sharpening, plastic skin, and oversaturated colors

## Compatibility
- Initial target: iOS 17+
- Hardware target for optimization: iPhone 12 mini / A14
- Processing should gracefully reduce memory use on older devices.
