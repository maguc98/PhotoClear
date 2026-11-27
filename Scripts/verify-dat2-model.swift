import Foundation
import CoreML
import CoreVideo

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: verify-dat2-model.swift /path/to/DAT2_Detail.mlmodelc")
}

let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
let configuration = MLModelConfiguration()
configuration.computeUnits = .all
let model = try MLModel(contentsOf: modelURL, configuration: configuration)

guard model.modelDescription.inputDescriptionsByName["image"]?.type == .image,
      model.modelDescription.outputDescriptionsByName["upscaled"]?.type == .image else {
    fatalError("DAT2 model image input/output interface does not match the expected contract.")
}

let attributes: [String: Any] = [
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    kCVPixelBufferMetalCompatibilityKey as String: true,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
]
var pixelBuffer: CVPixelBuffer?
let status = CVPixelBufferCreate(
    kCFAllocatorDefault, 512, 512, kCVPixelFormatType_32BGRA,
    attributes as CFDictionary, &pixelBuffer
)
guard status == kCVReturnSuccess, let inputBuffer = pixelBuffer else {
    fatalError("Unable to create a 512x512 DAT2 test image.")
}

CVPixelBufferLockBaseAddress(inputBuffer, [])
defer { CVPixelBufferUnlockBaseAddress(inputBuffer, []) }
guard let base = CVPixelBufferGetBaseAddress(inputBuffer) else {
    fatalError("DAT2 test image has no writable base address.")
}
let rowBytes = CVPixelBufferGetBytesPerRow(inputBuffer)
for y in 0..<512 {
    let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
    for x in 0..<512 {
        let offset = x * 4
        let value = UInt8((Double(x + y) / 1022.0 * 180.0 + 32.0).rounded())
        row[offset] = value
        row[offset + 1] = value
        row[offset + 2] = value
        row[offset + 3] = 255
    }
}

let input = try MLDictionaryFeatureProvider(dictionary: [
    "image": MLFeatureValue(pixelBuffer: inputBuffer)
])
let prediction = try model.prediction(from: input)
guard let outputBuffer = prediction.featureValue(for: "upscaled")?.imageBufferValue else {
    fatalError("DAT2 did not return an image buffer.")
}
guard CVPixelBufferGetWidth(outputBuffer) == 2048,
      CVPixelBufferGetHeight(outputBuffer) == 2048 else {
    fatalError("Unexpected DAT2 output size: \(CVPixelBufferGetWidth(outputBuffer))x\(CVPixelBufferGetHeight(outputBuffer))")
}

print("DAT2 Core ML smoke test passed")
print("Input: 512x512 BGRA image")
print("Output: 2048x2048 image")
