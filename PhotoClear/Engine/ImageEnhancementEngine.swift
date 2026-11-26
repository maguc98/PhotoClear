import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

final class ImageEnhancementEngine {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func enhance(_ image: UIImage, preset: EnhancementPreset, strength: Double) async -> UIImage? {
        guard let source = CIImage(image: image) else { return image }
        return await Task.detached(priority: .userInitiated) { [context] in
            var output = source

            let noise = CIFilter.noiseReduction()
            noise.inputImage = output
            noise.noiseLevel = Float(0.015 + (1.0 - strength) * 0.025)
            noise.sharpness = Float(0.25 + strength * 0.45)
            if let result = noise.outputImage { output = result }

            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = output
            sharpen.sharpness = Float(strength * (preset == .clear ? 0.9 : 0.45))
            sharpen.radius = Float(1.0 + strength * 1.5)
            if let result = sharpen.outputImage { output = result }

            if preset == .natural {
                let color = CIFilter.colorControls()
                color.inputImage = output
                color.saturation = 1.02
                color.contrast = 1.025
                if let result = color.outputImage { output = result }
            } else if preset == .clear {
                let color = CIFilter.colorControls()
                color.inputImage = output
                color.saturation = 1.04
                color.contrast = 1.06
                if let result = color.outputImage { output = result }
            } else {
                let color = CIFilter.colorControls()
                color.inputImage = output
                color.saturation = 1.015
                color.contrast = 1.03
                if let result = color.outputImage { output = result }
            }

            guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }.value
    }
}
