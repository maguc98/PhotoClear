import Foundation
import UIKit
import CoreML
import CoreImage
import CoreGraphics

struct RealESRGANResult {
    let image: UIImage
    let inputWasDownscaled: Bool
    let inputPixelSize: CGSize
    let outputPixelSize: CGSize
}

enum RealESRGANError: LocalizedError {
    case modelMissing
    case invalidImage
    case invalidModel
    case unsupportedOutput
    case allocationFailed
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "没有找到随 App 安装的 Real-ESRGAN 模型。请从包含模型的 GitHub Actions 构建版本安装。"
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

    private let modelName = "RealESRGAN_general_522_fp16"
    private let modelInputSize = 522
    private let modelScale = 4
    private let tileSize = 512
    private let tileOverlap = 32
    private let maxOutputPixels = 36_000_000

    private let modelLock = NSLock()
    private var cachedModel: MLModel?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    private init() {}

    func upscale(_ image: UIImage, outputScale: Int) async throws -> RealESRGANResult {
        guard outputScale == 2 || outputScale == 4 else {
            throw RealESRGANError.processingFailed("仅支持 2× 或 4× 输出。")
        }

        return try await Task.detached(priority: .userInitiated) {
            try self.upscaleSynchronously(image, outputScale: outputScale)
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

    private func upscaleSynchronously(_ image: UIImage, outputScale: Int) throws -> RealESRGANResult {
        let model = try loadModel()

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

        let sourceCGImage: CGImage
        let width: Int
        let height: Int

        if wasDownscaled {
            let factor = sqrt(Double(maxInputPixels) / Double(originalPixels))
            width = max(1, Int(Double(originalWidth) * factor))
            height = max(1, Int(Double(originalHeight) * factor))
            let resized = normalizedImage.transformed(
                by: CGAffineTransform(scaleX: CGFloat(width) / CGFloat(originalWidth),
                                      y: CGFloat(height) / CGFloat(originalHeight))
            )
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            guard let cgImage = ciContext.createCGImage(resized, from: bounds) else {
                throw RealESRGANError.invalidImage
            }
            sourceCGImage = cgImage
        } else {
            width = originalWidth
            height = originalHeight
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            guard let cgImage = ciContext.createCGImage(normalizedImage, from: bounds) else {
                throw RealESRGANError.invalidImage
            }
            sourceCGImage = cgImage
        }

        let outputWidth = width * outputScale
        let outputHeight = height * outputScale
        let sourceByteCount = width * height * 4
        let outputByteCount = outputWidth * outputHeight * 4

        guard sourceByteCount > 0, outputByteCount > 0,
              outputWidth * outputHeight <= maxOutputPixels else {
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

        let outputBuffer = UnsafeMutableRawPointer.allocate(byteCount: outputByteCount, alignment: 64)
        outputBuffer.initializeMemory(as: UInt8.self, repeating: 0, count: outputByteCount)
        var outputBufferOwned = true
        defer {
            if outputBufferOwned {
                outputBuffer.deallocate()
            }
        }
        let outputPixels = outputBuffer.assumingMemoryBound(to: UInt8.self)

        let xStarts = tileStarts(for: width)
        let yStarts = tileStarts(for: height)
        let inputShape: [NSNumber] = [
            NSNumber(value: 1), NSNumber(value: 3),
            NSNumber(value: modelInputSize), NSNumber(value: modelInputSize)
        ]

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
                    inputArray = try MLMultiArray(shape: inputShape, dataType: .float32)
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
                      outputArray.dataType == .float32,
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
                    destinationScale: outputScale,
                    tileX: x0,
                    tileY: y0,
                    tileWidth: tileWidth,
                    tileHeight: tileHeight,
                    cropLeft: cropLeft,
                    cropTop: cropTop,
                    cropRight: cropRight,
                    cropBottom: cropBottom
                )
            }
        }

        let outputData = Data(
            bytesNoCopy: outputBuffer,
            count: outputByteCount,
            deallocator: .custom { pointer, _ in pointer.deallocate() }
        )
        outputBufferOwned = false

        guard let provider = CGDataProvider(data: outputData as CFData),
              let outputCGImage = CGImage(
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outputWidth * 4,
                space: rgbSpace,
                bitmapInfo: rgbaBitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw RealESRGANError.processingFailed("无法生成增强后的照片。")
        }

        return RealESRGANResult(
            image: UIImage(cgImage: outputCGImage, scale: 1, orientation: .up),
            inputWasDownscaled: wasDownscaled,
            inputPixelSize: CGSize(width: width, height: height),
            outputPixelSize: CGSize(width: outputWidth, height: outputHeight)
        )
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
        let batchStride = strides[0]
        let channelStride = strides[1]
        let rowStride = strides[2]
        let columnStride = strides[3]
        let pointer = input.dataPointer.assumingMemoryBound(to: Float.self)

        for y in 0..<modelInputSize {
            let sourceY = min(imageHeight - 1, tileY + reflectedCoordinate(y, length: tileHeight))
            for x in 0..<modelInputSize {
                let sourceX = min(imageWidth - 1, tileX + reflectedCoordinate(x, length: tileWidth))
                let sourceOffset = (sourceY * imageWidth + sourceX) * 4
                let targetOffset = batchStride + y * rowStride + x * columnStride

                pointer[targetOffset] = Float(sourcePixels[sourceOffset]) / 255
                pointer[targetOffset + channelStride] = Float(sourcePixels[sourceOffset + 1]) / 255
                pointer[targetOffset + channelStride * 2] = Float(sourcePixels[sourceOffset + 2]) / 255
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
        let outputValues = output.dataPointer.assumingMemoryBound(to: Float.self)

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
                    outputY = (cropTop + y / 2) * modelScale
                    outputX = (cropLeft + x / 2) * modelScale
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
                        red += outputValues[base]
                        green += outputValues[channelStride + base]
                        blue += outputValues[channelStride * 2 + base]
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
