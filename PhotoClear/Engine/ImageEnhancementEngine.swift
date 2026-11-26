import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

final class ImageEnhancementEngine {
    private let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    func enhance(_ image: UIImage, preset: EnhancementPreset, strength: Double) async -> UIImage? {
        guard let source = CIImage(image: image) else { return image }
        let intensity = min(max(strength, 0.15), 1.0)

        return await Task.detached(priority: .userInitiated) { [context] in
            var output = source

            // Gentle denoise first: keep texture while reducing compression noise.
            let denoise = CIFilter.noiseReduction()
            denoise.inputImage = output
            denoise.noiseLevel = Float(0.008 + (1.0 - intensity) * 0.018)
            denoise.sharpness = Float(0.18 + intensity * 0.24)
            if let result = denoise.outputImage { output = result }

            // Luminance-only sharpening avoids excessive color halos.
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = output
            switch preset {
            case .natural:
                sharpen.sharpness = Float(0.24 + intensity * 0.42)
                sharpen.radius = Float(0.65 + intensity * 0.85)
            case .clear:
                sharpen.sharpness = Float(0.38 + intensity * 0.62)
                sharpen.radius = Float(0.85 + intensity * 1.15)
            case .portrait:
                sharpen.sharpness = Float(0.16 + intensity * 0.30)
                sharpen.radius = Float(0.55 + intensity * 0.65)
            }
            if let result = sharpen.outputImage { output = result }

            // Add restrained local contrast with a small, preset-dependent amount.
            let contrast = CIFilter.colorControls()
            contrast.inputImage = output
            switch preset {
            case .natural:
                contrast.saturation = 1.015
                contrast.contrast = 1.025
                contrast.brightness = 0.002
            case .clear:
                contrast.saturation = 1.025
                contrast.contrast = Float(1.035 + intensity * 0.035)
                contrast.brightness = 0.003
            case .portrait:
                contrast.saturation = 1.005
                contrast.contrast = 1.015
                contrast.brightness = 0.002
            }
            if let result = contrast.outputImage { output = result }

            // Vibrance is subtle and helps faded colors without forcing saturation.
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = output
            vibrance.amount = preset == .portrait ? 0.08 : 0.12
            if let result = vibrance.outputImage { output = result }

            // Recover a little shadow detail; keep highlight changes conservative.
            let tone = CIFilter.highlightShadowAdjust()
            tone.inputImage = output
            tone.shadowAmount = preset == .portrait ? 0.12 : 0.18
            tone.highlightAmount = 0.04
            if let result = tone.outputImage { output = result }

            // Final mild unsharp mask, especially restrained for portrait preset.
            let unsharp = CIFilter.unsharpMask()
            unsharp.inputImage = output
            unsharp.radius = preset == .clear ? 1.1 : 0.7
            unsharp.intensity = preset == .clear ? Float(0.22 + intensity * 0.22) : Float(0.10 + intensity * 0.12)
            if let result = unsharp.outputImage { output = result }

            guard let cgImage = context.createCGImage(output, from: source.extent) else { return nil }
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }.value
    }
}
