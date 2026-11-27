import Foundation
import UIKit
import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Vision
import CoreVideo
import Darwin

struct RealESRGANResult {
    let image: UIImage
    let inputWasDownscaled: Bool
    let inputPixelSize: CGSize
    let outputPixelSize: CGSize
}

enum RealESRGANError: LocalizedError {
    case modelMissing
    case detailModelMissing
    case invalidImage
    case invalidModel
    case unsupportedOutput
    case allocationFailed
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "没有找到随 App 安装的 Real-ESRGAN 模型。请从包含模型的 GitHub Actions 构建版本安装。"
        case .detailModelMissing:
            return "没有找到随 App 安装的 DAT2 细节重构模型。请安装包含内嵌模型的新版本。"
        case .invalidImage:
            return "无法读取这张照片。"
        case .invalidModel:
            return "AI 模型的输入或输出结构不符合预期。"
        case .unsupportedOutput:
            return "当前 AI 模型返回了不支持的数据格式。"
        case .allocationFailed:
            return "照片尺寸过大，设备暂时无法分配足够内存。请尝试较小的照片或选择 2×。"
        case .processingFailed(let detail):
            return "AI 增强失败：\(detail)"
        }
    }
}

/// Runs the bundled Real-ESRGAN General 4× Core ML model entirely on-device.
///
/// The model is compiled into the app by Xcode. There is no model download or
/// network request at runtime. Large images are processed in overlapping tiles
/// to avoid holding a full-resolution model tensor in memory.
final class RealESRGANUpscaler: @unchecked Sendable {
    static let shared = RealESRGANUpscaler()

    private let modelName = "RealESRGAN_x4plus_fp16"
    private let modelInputSize = 256
    private let modelScale = 4
    private let tileSize = 224
    private let tileOverlap = 32
    private let maxOutputPixels = 36_000_000

    private let modelLock = NSLock()
    private var cachedModel: MLModel?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    private init() {}

    func upscale(
        _ image: UIImage,
        outputScale: Int,
        settings: EnhancementSettings,
        stackedUpscalingEnabled: Bool,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> RealESRGANResult {
        guard [2, 4, 8, 12].contains(outputScale),
              outputScale <= 4 || stackedUpscalingEnabled else {
            throw RealESRGANError.processingFailed("请开启多阶段堆叠放大后再选择 8× 或 12×。")
        }

        return try await Task.detached(priority: .userInitiated) {
            try self.upscaleSynchronously(
                image,
                outputScale: outputScale,
                settings: settings,
                progress: progress
            )
        }.value
    }

    private func loadModel() throws -> MLModel {
        modelLock.lock()
        defer { modelLock.unlock() }

        if let cachedModel {
            return cachedModel
        }

        let compiledURL =
            Bundle.main.url(forResource: modelName, withExtension: "mlmodelc", subdirectory: "Models")
            ?? Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")

        guard let compiledURL else {
            throw RealESRGANError.modelMissing
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        do {
            let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
            cachedModel = model
            return model
        } catch {
            throw RealESRGANError.processingFailed("模型加载失败：\(error.localizedDescription)")
        }
    }

    private func upscaleSynchronously(
        _ image: UIImage,
        outputScale: Int,
        settings: EnhancementSettings,
        progress: @Sendable (Double, String) -> Void
    ) throws -> RealESRGANResult {
        progress(0.03, "正在加载 AI 模型…")
        let model = try loadModel()
        progress(0.08, "正在分析照片尺寸…")

        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.sorted().first,
              let outputName = model.modelDescription.outputDescriptionsByName.keys.sorted().first,
              model.modelDescription.inputDescriptionsByName[inputName]?.type == .multiArray else {
            throw RealESRGANError.invalidModel
        }

        guard let inputCIImage = CIImage(image: image, options: [.applyOrientationProperty: true]) else {
            throw RealESRGANError.invalidImage
        }

        let orientedImage = inputCIImage.oriented(.up)
        let originalExtent = orientedImage.extent.integral
        let originalWidth = max(1, Int(originalExtent.width))
        let originalHeight = max(1, Int(originalExtent.height))
        let maxInputPixels = maxOutputPixels / (outputScale * outputScale)
        let originalPixels = originalWidth * originalHeight
        let wasDownscaled = originalPixels > maxInputPixels

        let normalizedImage = orientedImage.transformed(
            by: CGAffineTransform(translationX: -originalExtent.origin.x, y: -originalExtent.origin.y)
        )
        let preparedImage = prepareInputImage(normalizedImage, settings: settings)

        let sourceCGImage: CGImage
        let width: Int
        let height: Int

        if wasDownscaled {
            let factor = sqrt(Double(maxInputPixels) / Double(originalPixels))
            width = max(1, Int(Double(originalWidth) * factor))
            height = max(1, Int(Double(originalHeight) * factor))
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            guard let cgImage = ciContext.createCGImage(preparedImage.transformed(
                by: CGAffineTransform(scaleX: CGFloat(width) / CGFloat(originalWidth),
                                      y: CGFloat(height) / CGFloat(originalHeight))
            ), from: bounds) else {
                throw RealESRGANError.invalidImage
            }
            sourceCGImage = cgImage
        } else {
            width = originalWidth
            height = originalHeight
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            guard let cgImage = ciContext.createCGImage(preparedImage, from: bounds) else {
                throw RealESRGANError.invalidImage
            }
            sourceCGImage = cgImage
        }

        let stageScale = outputScale == 2 ? 2 : 4
        let outputWidth = width * stageScale
        let outputHeight = height * stageScale
        let finalOutputWidth = width * outputScale
        let finalOutputHeight = height * outputScale
        let sourceByteCount = width * height * 4
        let outputByteCount = outputWidth * outputHeight * 4
        let finalOutputPixels = finalOutputWidth * finalOutputHeight

        guard sourceByteCount > 0, outputByteCount > 0,
              finalOutputPixels <= maxOutputPixels else {
            throw RealESRGANError.allocationFailed
        }

        let sourceBuffer = UnsafeMutableRawPointer.allocate(byteCount: sourceByteCount, alignment: 64)
        defer { sourceBuffer.deallocate() }

        let rgbSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let rgbaBitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )

        guard let sourceContext = CGContext(
            data: sourceBuffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: rgbSpace,
            bitmapInfo: rgbaBitmapInfo.rawValue
        ) else {
            throw RealESRGANError.allocationFailed
        }
        sourceContext.interpolationQuality = .none
        sourceContext.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let sourcePixels = sourceBuffer.assumingMemoryBound(to: UInt8.self)

        let intermediateMapping = try allocateMappedBuffer(byteCount: outputByteCount)
        let outputBuffer = intermediateMapping.pointer
        var outputBufferOwned = true
        defer {
            if outputBufferOwned {
                _ = munmap(outputBuffer, outputByteCount)
                try? FileManager.default.removeItem(at: intermediateMapping.url)
            }
        }
        let outputPixels = outputBuffer.assumingMemoryBound(to: UInt8.self)

        let xStarts = tileStarts(for: width)
        let yStarts = tileStarts(for: height)
        let inputShape: [NSNumber] = [
            NSNumber(value: 1), NSNumber(value: 3),
            NSNumber(value: modelInputSize), NSNumber(value: modelInputSize)
        ]
        let totalTiles = max(1, xStarts.count * yStarts.count)
        var completedTiles = 0
        progress(0.12, "正在准备 AI 图像分块…")

        for yIndex in yStarts.indices {
            let y0 = yStarts[yIndex]
            let tileHeight = min(tileSize, height - y0)
            let topOverlap = yIndex > 0
                ? max(0, yStarts[yIndex - 1] + min(tileSize, height - yStarts[yIndex - 1]) - y0)
                : 0
            let bottomOverlap = yIndex + 1 < yStarts.count
                ? max(0, y0 + tileHeight - yStarts[yIndex + 1])
                : 0
            let cropTop = topOverlap / 2
            let cropBottom = bottomOverlap - bottomOverlap / 2

            for xIndex in xStarts.indices {
                let x0 = xStarts[xIndex]
                let tileWidth = min(tileSize, width - x0)
                let leftOverlap = xIndex > 0
                    ? max(0, xStarts[xIndex - 1] + min(tileSize, width - xStarts[xIndex - 1]) - x0)
                    : 0
                let rightOverlap = xIndex + 1 < xStarts.count
                    ? max(0, x0 + tileWidth - xStarts[xIndex + 1])
                    : 0
                let cropLeft = leftOverlap / 2
                let cropRight = rightOverlap - rightOverlap / 2

                let inputArray: MLMultiArray
                do {
                    inputArray = try MLMultiArray(shape: inputShape, dataType: .float16)
                } catch {
                    throw RealESRGANError.processingFailed("无法创建模型输入：\(error.localizedDescription)")
                }

                fillInput(
                    inputArray,
                    sourcePixels: sourcePixels,
                    imageWidth: width,
                    imageHeight: height,
                    tileX: x0,
                    tileY: y0,
                    tileWidth: tileWidth,
                    tileHeight: tileHeight
                )

                let provider: MLDictionaryFeatureProvider
                do {
                    provider = try MLDictionaryFeatureProvider(dictionary: [
                        inputName: MLFeatureValue(multiArray: inputArray)
                    ])
                } catch {
                    throw RealESRGANError.processingFailed("无法准备模型输入：\(error.localizedDescription)")
                }

                let prediction: MLFeatureProvider
                do {
                    prediction = try model.prediction(from: provider)
                } catch {
                    throw RealESRGANError.processingFailed("模型推理失败：\(error.localizedDescription)")
                }

                guard let outputArray = prediction.featureValue(for: outputName)?.multiArrayValue,
                      outputArray.dataType == .float16,
                      outputArray.shape.count == 4,
                      outputArray.shape[1].intValue == 3,
                      outputArray.shape[2].intValue >= modelInputSize * modelScale,
                      outputArray.shape[3].intValue >= modelInputSize * modelScale else {
                    throw RealESRGANError.unsupportedOutput
                }

                writeTileOutput(
                    outputArray,
                    destination: outputPixels,
                    destinationWidth: outputWidth,
                    destinationHeight: outputHeight,
                    destinationScale: stageScale,
                    tileX: x0,
                    tileY: y0,
                    tileWidth: tileWidth,
                    tileHeight: tileHeight,
                    cropLeft: cropLeft,
                    cropTop: cropTop,
                    cropRight: cropRight,
                    cropBottom: cropBottom
                )
                completedTiles += 1
                let tileProgress = Double(completedTiles) / Double(totalTiles)
                progress(0.12 + tileProgress * 0.78,
                         "AI 正在重建细节 · \(completedTiles)/\(totalTiles)")
            }
        }
        progress(0.93, outputScale > 4 ? "正在进行多阶段尺寸扩展…" : "正在优化高清画面…")

        let intermediateData = Data(
            bytesNoCopy: outputBuffer,
            count: outputByteCount,
            deallocator: .custom { pointer, _ in
                _ = munmap(pointer, outputByteCount)
                try? FileManager.default.removeItem(at: intermediateMapping.url)
            }
        )
        outputBufferOwned = false

        guard let intermediateProvider = CGDataProvider(data: intermediateData as CFData),
              let intermediateCGImage = CGImage(
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outputWidth * 4,
                space: rgbSpace,
                bitmapInfo: rgbaBitmapInfo,
                provider: intermediateProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw RealESRGANError.processingFailed("无法生成分块超分中间图像。")
        }

        var finalImage = CIImage(cgImage: intermediateCGImage)
        if outputScale != stageScale {
            let scaleFilter = CIFilter.lanczosScaleTransform()
            scaleFilter.inputImage = finalImage
            scaleFilter.scale = Float(outputScale) / Float(stageScale)
            scaleFilter.aspectRatio = 1
            guard let scaledImage = scaleFilter.outputImage else {
                throw RealESRGANError.processingFailed("多阶段尺寸扩展失败。")
            }
            finalImage = scaledImage
        }

        finalImage = applyPostProcessing(
            finalImage,
            sourceImage: CIImage(cgImage: sourceCGImage),
            outputScale: outputScale,
            settings: settings
        )

        let finalBounds = CGRect(x: 0, y: 0, width: finalOutputWidth, height: finalOutputHeight)
        finalImage = finalImage.cropped(to: finalBounds)
        let finalByteCount = finalOutputWidth * finalOutputHeight * 4
        let finalMapping = try allocateMappedBuffer(byteCount: finalByteCount)
        var finalBufferOwned = true
        defer {
            if finalBufferOwned {
                _ = munmap(finalMapping.pointer, finalByteCount)
                try? FileManager.default.removeItem(at: finalMapping.url)
            }
        }

        ciContext.render(
            finalImage,
            toBitmap: finalMapping.pointer,
            rowBytes: finalOutputWidth * 4,
            bounds: finalBounds,
            format: .RGBA8,
            colorSpace: rgbSpace
        )

        let finalData = Data(
            bytesNoCopy: finalMapping.pointer,
            count: finalByteCount,
            deallocator: .custom { pointer, _ in
                _ = munmap(pointer, finalByteCount)
                try? FileManager.default.removeItem(at: finalMapping.url)
            }
        )
        finalBufferOwned = false

        guard let finalProvider = CGDataProvider(data: finalData as CFData),
              let finalCGImage = CGImage(
                width: finalOutputWidth,
                height: finalOutputHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: finalOutputWidth * 4,
                space: rgbSpace,
                bitmapInfo: rgbaBitmapInfo,
                provider: finalProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw RealESRGANError.processingFailed("无法生成最终高清照片。")
        }

        progress(0.98, "正在生成高清结果…")
        return RealESRGANResult(
            image: UIImage(cgImage: finalCGImage, scale: 1, orientation: .up),
            inputWasDownscaled: wasDownscaled,
            inputPixelSize: CGSize(width: width, height: height),
            outputPixelSize: CGSize(width: finalOutputWidth, height: finalOutputHeight)
        )
    }


    private func allocateMappedBuffer(byteCount: Int) throws -> (pointer: UnsafeMutableRawPointer, url: URL) {
        guard byteCount > 0 else { throw RealESRGANError.allocationFailed }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoClear-\(UUID().uuidString).rgba")
        let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw RealESRGANError.allocationFailed
        }
        defer { close(descriptor) }
        guard ftruncate(descriptor, off_t(byteCount)) == 0 else {
            try? FileManager.default.removeItem(at: url)
            throw RealESRGANError.allocationFailed
        }
        guard let mappedPointer = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0),
              mappedPointer != MAP_FAILED else {
            try? FileManager.default.removeItem(at: url)
            throw RealESRGANError.allocationFailed
        }
        return (mappedPointer, url)
    }

    private func prepareInputImage(_ image: CIImage, settings: EnhancementSettings) -> CIImage {
        var prepared = image

        if settings.mode == .night {
            let denoise = CIFilter.noiseReduction()
            denoise.inputImage = prepared
            denoise.noiseLevel = min(max(settings.noiseReduction * 0.035, 0.008), 0.04)
            denoise.sharpness = 0.22
            prepared = denoise.outputImage ?? prepared
            prepared = prepared.applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: ["inputShadowAmount": 0.12, "inputHighlightAmount": 0.96]
            )
        } else if settings.mode == .portrait {
            prepared = personAwareInput(prepared, amount: settings.detailRecovery)
        } else if settings.mode == .landscape {
            prepared = prepared.applyingFilter(
                "CIColorControls",
                parameters: [kCIInputContrastKey: 1.015, kCIInputSaturationKey: 1.0]
            )
        } else if settings.mode == .custom && settings.noiseReduction > 0.55 {
            let denoise = CIFilter.noiseReduction()
            denoise.inputImage = prepared
            denoise.noiseLevel = min(max(settings.noiseReduction * 0.025, 0.01), 0.035)
            denoise.sharpness = 0.25
            prepared = denoise.outputImage ?? prepared
        }

        return prepared
    }

    private func personAwareInput(_ image: CIImage, amount: Float) -> CIImage {
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return image
        }
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            return image
        }
        guard let pixelBuffer = request.results?.first?.pixelBuffer else {
            return image
        }

        let rawMask = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = image.extent.width / max(rawMask.extent.width, 1)
        let sy = image.extent.height / max(rawMask.extent.height, 1)
        let mask = rawMask
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.2])
            .cropped(to: image.extent)

        let amount = min(max(Double(amount) * 0.20, 0.04), 0.20)
        let personDetails = image.applyingFilter(
            "CISharpenLuminance",
            parameters: [kCIInputSharpnessKey: amount]
        )
        return personDetails.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ]
        )
    }

    private func applyPostProcessing(
        _ image: CIImage,
        sourceImage: CIImage,
        outputScale: Int,
        settings: EnhancementSettings
    ) -> CIImage {
        var processed = image

        // Keep AI reconstruction detail. Denoising is deliberately restrained
        // outside Night mode to avoid smoothing fine source texture.
        if settings.noiseReduction > 0.01 {
            let denoise = CIFilter.noiseReduction()
            denoise.inputImage = processed
            let modeFactor: Float = settings.mode == .portrait ? 0.72 : (settings.mode == .night ? 1.12 : 0.82)
            denoise.noiseLevel = min(max(settings.noiseReduction * 0.022 * modeFactor, 0.0), 0.035)
            denoise.sharpness = settings.mode == .portrait ? 0.22 : 0.34
            processed = denoise.outputImage ?? processed
        }

        // Restore stronger detail recovery while keeping a mode-aware ceiling.
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = processed
        let radiusFactor: Float = settings.mode == .landscape ? 1.0 : 0.9
        // Favor tighter, more visible detail reconstruction over broad soft sharpening.
        sharpen.radius = 0.48 + settings.texture * 0.28 * radiusFactor
        let modeSharpness: Float = settings.mode == .portrait ? 0.78 : (settings.mode == .night ? 0.76 : (settings.mode == .landscape ? 1.08 : 1.0))
        let detailStrength: Float = settings.sharpening * 0.28
        let recoveryStrength: Float = settings.detailRecovery * 0.12
        let textureStrength: Float = settings.texture * 0.08
        let combinedStrength: Float = (detailStrength + recoveryStrength + textureStrength) * modeSharpness
        sharpen.sharpness = min(max(combinedStrength, 0), 0.42)
        processed = sharpen.outputImage ?? processed

        let color = CIFilter.colorControls()
        color.inputImage = processed
        color.saturation = 1.0 - (1.0 - settings.colorPreservation) * 0.08
        processed = color.outputImage ?? processed

        // A small source-resize blend reduces AI artifacts without the former
        // edge-mask fallback that could suppress fine detail across the image.
        let sourceResize = CIFilter.lanczosScaleTransform()
        sourceResize.inputImage = sourceImage
        sourceResize.scale = Float(outputScale)
        sourceResize.aspectRatio = 1
        guard let naturalBase = sourceResize.outputImage else { return processed }

        if settings.naturalness > 0.01 {
            let blendAmount: Float = min(max(settings.naturalness * 0.045, 0.0), 0.06)
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = processed
            dissolve.targetImage = naturalBase
            dissolve.time = blendAmount
            processed = dissolve.outputImage ?? processed
        }

        return processed
    }

    private func tileStarts(for dimension: Int) -> [Int] {
        guard dimension > tileSize else { return [0] }
        let stride = tileSize - tileOverlap
        var starts: [Int] = []
        var position = 0
        while position < dimension {
            starts.append(position)
            if position + tileSize >= dimension { break }
            position += stride
        }
        return starts
    }

    private func reflectedCoordinate(_ coordinate: Int, length: Int) -> Int {
        guard length > 1 else { return 0 }
        let period = 2 * (length - 1)
        let value = coordinate % period
        return value < length ? value : period - value
    }

    private func fillInput(
        _ input: MLMultiArray,
        sourcePixels: UnsafePointer<UInt8>,
        imageWidth: Int,
        imageHeight: Int,
        tileX: Int,
        tileY: Int,
        tileWidth: Int,
        tileHeight: Int
    ) {
        let strides = input.strides.map(\.intValue)
        let channelStride = strides[1]
        let rowStride = strides[2]
        let columnStride = strides[3]
        let pointer = input.dataPointer.assumingMemoryBound(to: Float16.self)

        for y in 0..<modelInputSize {
            let sourceY = min(imageHeight - 1, tileY + reflectedCoordinate(y, length: tileHeight))
            for x in 0..<modelInputSize {
                let sourceX = min(imageWidth - 1, tileX + reflectedCoordinate(x, length: tileWidth))
                let sourceOffset = (sourceY * imageWidth + sourceX) * 4
                let targetOffset = y * rowStride + x * columnStride

                pointer[targetOffset] = Float16(Float(sourcePixels[sourceOffset]) / 255.0)
                pointer[targetOffset + channelStride] = Float16(Float(sourcePixels[sourceOffset + 1]) / 255.0)
                pointer[targetOffset + channelStride * 2] = Float16(Float(sourcePixels[sourceOffset + 2]) / 255.0)
            }
        }
    }

    private func writeTileOutput(
        _ output: MLMultiArray,
        destination: UnsafeMutablePointer<UInt8>,
        destinationWidth: Int,
        destinationHeight: Int,
        destinationScale: Int,
        tileX: Int,
        tileY: Int,
        tileWidth: Int,
        tileHeight: Int,
        cropLeft: Int,
        cropTop: Int,
        cropRight: Int,
        cropBottom: Int
    ) {
        let outputStrides = output.strides.map(\.intValue)
        let channelStride = outputStrides[1]
        let rowStride = outputStrides[2]
        let columnStride = outputStrides[3]
        let outputValues = output.dataPointer.assumingMemoryBound(to: Float16.self)

        let contentWidth = max(0, tileWidth - cropLeft - cropRight)
        let contentHeight = max(0, tileHeight - cropTop - cropBottom)
        let destinationX = (tileX + cropLeft) * destinationScale
        let destinationY = (tileY + cropTop) * destinationScale
        let targetWidth = contentWidth * destinationScale
        let targetHeight = contentHeight * destinationScale

        guard targetWidth > 0, targetHeight > 0,
              destinationX + targetWidth <= destinationWidth,
              destinationY + targetHeight <= destinationHeight else {
            return
        }

        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let outputY: Int
                let outputX: Int
                let sampleCount: Int

                if destinationScale == 4 {
                    outputY = cropTop * modelScale + y
                    outputX = cropLeft * modelScale + x
                    sampleCount = 1
                } else {
                    outputY = cropTop * modelScale + y * 2
                    outputX = cropLeft * modelScale + x * 2
                    sampleCount = 4
                }

                var red: Float = 0
                var green: Float = 0
                var blue: Float = 0

                for sampleY in 0..<(destinationScale == 2 ? 2 : 1) {
                    for sampleX in 0..<(destinationScale == 2 ? 2 : 1) {
                        let sourceY = outputY + sampleY
                        let sourceX = outputX + sampleX
                        let base = sourceY * rowStride + sourceX * columnStride
                        red += Float(outputValues[base])
                        green += Float(outputValues[channelStride + base])
                        blue += Float(outputValues[channelStride * 2 + base])
                    }
                }

                let divisor = Float(sampleCount)
                let destinationOffset = ((destinationY + y) * destinationWidth + destinationX + x) * 4
                destination[destinationOffset] = UInt8((min(max(red / divisor, 0), 1) * 255).rounded())
                destination[destinationOffset + 1] = UInt8((min(max(green / divisor, 0), 1) * 255).rounded())
                destination[destinationOffset + 2] = UInt8((min(max(blue / divisor, 0), 1) * 255).rounded())
                destination[destinationOffset + 3] = 255
            }
        }
    }
}
