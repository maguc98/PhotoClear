import Foundation
import UIKit
import CoreML
import CoreImage
import CoreVideo
import CoreGraphics
import ImageIO
import Darwin

/// Bundled 4xBHI DAT2 photo-restoration model.
/// Works on-device and processes large images as overlapping 512px tiles.
final class DAT2DetailReconstructor: @unchecked Sendable {
    static let shared = DAT2DetailReconstructor()

    private let modelName = "DAT2_Detail"
    private let tileSize = 512
    private let tileOverlap = 64
    private let modelScale = 4
    private let maxOutputPixels = 36_000_000

    private let modelLock = NSLock()
    private var cachedModel: MLModel?
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])

    private init() {}

    func upscale(
        _ image: UIImage,
        outputScale: Int,
        settings: EnhancementSettings,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> RealESRGANResult {
        guard [2, 4, 8, 12].contains(outputScale) else {
            throw RealESRGANError.processingFailed("DAT2 细节重构仅支持 2×、4×、8× 和 12× 输出。")
        }

        return try await Task.detached(priority: .userInitiated) {
            try await self.upscaleSynchronously(
                image,
                outputScale: outputScale,
                settings: settings,
                progress: progress
            )
        }.value
    }

    private func cachedModelValue() -> MLModel? {
        modelLock.lock()
        defer { modelLock.unlock() }
        return cachedModel
    }

    private func storeModelValue(_ model: MLModel) -> MLModel {
        modelLock.lock()
        defer { modelLock.unlock() }
        if let cachedModel { return cachedModel }
        cachedModel = model
        return model
    }

    private func loadModel() async throws -> MLModel {
        if let existing = cachedModelValue() { return existing }

        guard let modelURL =
            Bundle.main.url(forResource: modelName, withExtension: "mlmodelc", subdirectory: "Models")
            ?? Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw RealESRGANError.detailModelMissing
        }

        // Asynchronous Core ML loading prevents synchronous model initialization
        // from blocking the processing task. Use CPU-only initially to avoid a device-side ANE model compilation stall; profile before enabling ANE.
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly

        do {
            let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
            return storeModelValue(model)
        } catch {
            throw RealESRGANError.processingFailed("DAT2 模型加载失败：\\(error.localizedDescription)")
        }
    }

    private func upscaleSynchronously(
        _ image: UIImage,
        outputScale: Int,
        settings: EnhancementSettings,
        progress: @Sendable (Double, String) -> Void
    ) async throws -> RealESRGANResult {
        progress(0.02, "正在初始化 DAT2 AI 模型…")
        let model = try await loadModel()
        progress(0.06, "DAT2 模型已就绪，正在准备照片…")

        guard model.modelDescription.inputDescriptionsByName["image"]?.type == .image,
              model.modelDescription.outputDescriptionsByName["upscaled"]?.type == .image else {
            throw RealESRGANError.invalidModel
        }

        progress(0.06, "正在分析照片尺寸…")
        guard let rawImage = CIImage(image: image, options: [.applyOrientationProperty: true]) else {
            throw RealESRGANError.invalidImage
        }

        let orientedImage = rawImage.oriented(.up)
        let sourceExtent = orientedImage.extent.integral
        let originalWidth = max(1, Int(sourceExtent.width))
        let originalHeight = max(1, Int(sourceExtent.height))
        let normalizedImage = orientedImage.transformed(
            by: CGAffineTransform(translationX: -sourceExtent.minX, y: -sourceExtent.minY)
        )

        // Keep the model's 4x working image within the same 36 MP safety budget,
        // even when the user chooses 2x, 8x, or 12x output.
        let safeScale = max(outputScale, modelScale)
        let maxInputPixels = maxOutputPixels / (safeScale * safeScale)
        let originalPixels = originalWidth * originalHeight
        let wasDownscaled = originalPixels > maxInputPixels
        let resizeFactor = wasDownscaled
            ? sqrt(Double(maxInputPixels) / Double(originalPixels))
            : 1.0
        let width = max(1, Int((Double(originalWidth) * resizeFactor).rounded()))
        let height = max(1, Int((Double(originalHeight) * resizeFactor).rounded()))
        let workingImage = normalizedImage
            .transformed(by: CGAffineTransform(scaleX: CGFloat(resizeFactor), y: CGFloat(resizeFactor)))
            .cropped(to: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        let stageWidth = width * modelScale
        let stageHeight = height * modelScale
        let finalWidth = width * outputScale
        let finalHeight = height * outputScale
        let stageBytes = stageWidth * stageHeight * 4
        let finalBytes = finalWidth * finalHeight * 4

        guard stageBytes > 0, finalBytes > 0,
              finalWidth * finalHeight <= maxOutputPixels else {
            throw RealESRGANError.allocationFailed
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )

        let stageMapping = try allocateMappedBuffer(byteCount: stageBytes)
        var stageBufferOwned = true
        defer {
            if stageBufferOwned {
                _ = munmap(stageMapping.pointer, stageBytes)
                try? FileManager.default.removeItem(at: stageMapping.url)
            }
        }

        guard let stageContext = CGContext(
            data: stageMapping.pointer,
            width: stageWidth,
            height: stageHeight,
            bitsPerComponent: 8,
            bytesPerRow: stageWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw RealESRGANError.allocationFailed
        }
        stageContext.interpolationQuality = .high

        let xStarts = tileStarts(for: width)
        let yStarts = tileStarts(for: height)
        let totalTiles = max(1, xStarts.count * yStarts.count)
        var completedTiles = 0
        progress(0.09, "正在准备照片分块…")

        for yIndex in yStarts.indices {
            let y0 = yStarts[yIndex]
            let validHeight = min(tileSize, height - y0)
            let topOverlap = yIndex > 0
                ? max(0, yStarts[yIndex - 1] + tileSize - y0)
                : 0
            let bottomOverlap = yIndex + 1 < yStarts.count
                ? max(0, y0 + tileSize - yStarts[yIndex + 1])
                : 0
            let cropTop = topOverlap / 2
            let cropBottom = bottomOverlap - bottomOverlap / 2

            for xIndex in xStarts.indices {
                let x0 = xStarts[xIndex]
                let validWidth = min(tileSize, width - x0)
                let leftOverlap = xIndex > 0
                    ? max(0, xStarts[xIndex - 1] + tileSize - x0)
                    : 0
                let rightOverlap = xIndex + 1 < xStarts.count
                    ? max(0, x0 + tileSize - xStarts[xIndex + 1])
                    : 0
                let cropLeft = leftOverlap / 2
                let cropRight = rightOverlap - rightOverlap / 2

                try autoreleasepool {
                    let tileRect = CGRect(x: CGFloat(x0), y: CGFloat(y0), width: CGFloat(tileSize), height: CGFloat(tileSize))
                    let tileImage = workingImage.clampedToExtent().cropped(to: tileRect)
                    guard let inputBuffer = makeInputPixelBuffer(
                        from: tileImage,
                        colorSpace: colorSpace
                    ) else {
                        throw RealESRGANError.allocationFailed
                    }

                    let inputProvider = try MLDictionaryFeatureProvider(dictionary: [
                        "image": MLFeatureValue(pixelBuffer: inputBuffer)
                    ])
                    let prediction: MLFeatureProvider
                    do {
                        prediction = try model.prediction(from: inputProvider)
                    } catch {
                        throw RealESRGANError.processingFailed("DAT2 推理失败：\(error.localizedDescription)")
                    }

                    guard let outputBuffer = prediction.featureValue(for: "upscaled")?.imageBufferValue,
                          CVPixelBufferGetWidth(outputBuffer) == tileSize * modelScale,
                          CVPixelBufferGetHeight(outputBuffer) == tileSize * modelScale else {
                        throw RealESRGANError.unsupportedOutput
                    }

                    let outputImage = CIImage(cvPixelBuffer: outputBuffer)
                    guard let outputCGImage = ciContext.createCGImage(
                        outputImage,
                        from: CGRect(x: 0, y: 0, width: CGFloat(tileSize * modelScale), height: CGFloat(tileSize * modelScale))
                    ) else {
                        throw RealESRGANError.processingFailed("无法读取 DAT2 输出图像。")
                    }

                    let contentWidth = max(0, validWidth - cropLeft - cropRight)
                    let contentHeight = max(0, validHeight - cropTop - cropBottom)
                    guard contentWidth > 0, contentHeight > 0,
                          let croppedOutput = outputCGImage.cropping(to: CGRect(
                            x: CGFloat(cropLeft * modelScale),
                            y: CGFloat(cropTop * modelScale),
                            width: CGFloat(contentWidth * modelScale),
                            height: CGFloat(contentHeight * modelScale)
                          )) else {
                        throw RealESRGANError.processingFailed("DAT2 分块裁剪失败。")
                    }

                    // CGContext bitmap contexts use a bottom-left origin, while tile
                    // coordinates and CGImage crop rectangles are top-left based.
                    // Flip destination Y to keep tiles in the same image-space row.
                    let destinationY = stageHeight - ((y0 + cropTop + contentHeight) * modelScale)
                    let destination = CGRect(
                        x: CGFloat((x0 + cropLeft) * modelScale),
                        y: CGFloat(destinationY),
                        width: CGFloat(contentWidth * modelScale),
                        height: CGFloat(contentHeight * modelScale)
                    )
                    stageContext.draw(croppedOutput, in: destination)
                }

                completedTiles += 1
                let fraction = Double(completedTiles) / Double(totalTiles)
                progress(
                    0.09 + fraction * 0.82,
                    "DAT2 正在重建照片纹理 · \(completedTiles)/\(totalTiles)"
                )
            }
        }

        let stageData = Data(
            bytesNoCopy: stageMapping.pointer,
            count: stageBytes,
            deallocator: .custom { pointer, _ in
                _ = munmap(pointer, stageBytes)
                try? FileManager.default.removeItem(at: stageMapping.url)
            }
        )
        stageBufferOwned = false

        guard let stageProvider = CGDataProvider(data: stageData as CFData),
              let stageCGImage = CGImage(
                width: stageWidth,
                height: stageHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: stageWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: stageProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw RealESRGANError.processingFailed("无法合成 DAT2 高清图像。")
        }

        var finalImage = CIImage(cgImage: stageCGImage)
        if outputScale != modelScale {
            let resize = CIFilter.lanczosScaleTransform()
            resize.inputImage = finalImage
            resize.scale = Float(outputScale) / Float(modelScale)
            resize.aspectRatio = 1
            guard let scaled = resize.outputImage else {
                throw RealESRGANError.processingFailed("DAT2 输出尺寸调整失败。")
            }
            finalImage = scaled
        }

        // Retain a small amount of the source's color and structure to reduce
        // generative-looking shifts while preserving the restored texture.
        let sourceResize = CIFilter.lanczosScaleTransform()
        sourceResize.inputImage = workingImage
        sourceResize.scale = Float(outputScale)
        sourceResize.aspectRatio = 1
        if let naturalBase = sourceResize.outputImage {
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = finalImage
            dissolve.targetImage = naturalBase
            dissolve.time = Float(min(max(settings.naturalness * 0.06, 0.0), 0.06))
            finalImage = dissolve.outputImage ?? finalImage
        }

        let finalBounds = CGRect(x: 0, y: 0, width: CGFloat(finalWidth), height: CGFloat(finalHeight))
        finalImage = finalImage.cropped(to: finalBounds)

        let finalMapping = try allocateMappedBuffer(byteCount: finalBytes)
        var finalBufferOwned = true
        defer {
            if finalBufferOwned {
                _ = munmap(finalMapping.pointer, finalBytes)
                try? FileManager.default.removeItem(at: finalMapping.url)
            }
        }

        ciContext.render(
            finalImage,
            toBitmap: finalMapping.pointer,
            rowBytes: finalWidth * 4,
            bounds: finalBounds,
            format: .RGBA8,
            colorSpace: colorSpace
        )

        let finalData = Data(
            bytesNoCopy: finalMapping.pointer,
            count: finalBytes,
            deallocator: .custom { pointer, _ in
                _ = munmap(pointer, finalBytes)
                try? FileManager.default.removeItem(at: finalMapping.url)
            }
        )
        finalBufferOwned = false

        guard let finalProvider = CGDataProvider(data: finalData as CFData),
              let finalCGImage = CGImage(
                width: finalWidth,
                height: finalHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: finalWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: finalProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw RealESRGANError.processingFailed("无法生成最终重构照片。")
        }

        progress(0.98, "正在生成重构结果…")
        return RealESRGANResult(
            image: UIImage(cgImage: finalCGImage, scale: 1, orientation: .up),
            inputWasDownscaled: wasDownscaled,
            inputPixelSize: CGSize(width: CGFloat(width), height: CGFloat(height)),
            outputPixelSize: CGSize(width: CGFloat(finalWidth), height: CGFloat(finalHeight))
        )
    }

    private func makeInputPixelBuffer(
        from image: CIImage,
        colorSpace: CGColorSpace
    ) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            tileSize,
            tileSize,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        ciContext.render(
            image,
            to: pixelBuffer,
            bounds: CGRect(x: 0, y: 0, width: CGFloat(tileSize), height: CGFloat(tileSize)),
            colorSpace: colorSpace
        )
        return pixelBuffer
    }

    private func tileStarts(for dimension: Int) -> [Int] {
        guard dimension > tileSize else { return [0] }
        let stride = tileSize - tileOverlap
        var starts = [0]
        while let last = starts.last, last + tileSize < dimension {
            starts.append(last + stride)
        }
        return starts
    }

    private func allocateMappedBuffer(byteCount: Int) throws -> (pointer: UnsafeMutableRawPointer, url: URL) {
        guard byteCount > 0 else { throw RealESRGANError.allocationFailed }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoClear-DAT2-\(UUID().uuidString).rgba")
        let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw RealESRGANError.allocationFailed }
        defer { close(descriptor) }

        guard ftruncate(descriptor, off_t(byteCount)) == 0 else {
            try? FileManager.default.removeItem(at: url)
            throw RealESRGANError.allocationFailed
        }
        guard let pointer = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0),
              pointer != MAP_FAILED else {
            try? FileManager.default.removeItem(at: url)
            throw RealESRGANError.allocationFailed
        }
        return (pointer, url)
    }
}
