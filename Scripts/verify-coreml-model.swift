import Foundation
import CoreML

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift verify-coreml-model.swift /path/to/model.mlmodelc")
}

let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
let configuration = MLModelConfiguration()
configuration.computeUnits = .all

let model = try MLModel(contentsOf: modelURL, configuration: configuration)
guard let inputName = model.modelDescription.inputDescriptionsByName.keys.sorted().first,
      let outputName = model.modelDescription.outputDescriptionsByName.keys.sorted().first,
      let inputConstraint = model.modelDescription.inputDescriptionsByName[inputName]?.multiArrayConstraint else {
    fatalError("Model does not expose a multi-array input.")
}

let input = try MLMultiArray(shape: inputConstraint.shape, dataType: .float16)
let inputValues = input.dataPointer.assumingMemoryBound(to: Float16.self)
for index in 0..<input.count {
    inputValues[index] = Float16(0.5)
}

let provider = try MLDictionaryFeatureProvider(dictionary: [
    inputName: MLFeatureValue(multiArray: input)
])
let prediction = try model.prediction(from: provider)

guard let output = prediction.featureValue(for: outputName)?.multiArrayValue else {
    fatalError("Model did not return a multi-array output.")
}
guard output.dataType == .float16 else {
    fatalError("Expected Float16 output, received \(output.dataType.rawValue).")
}
let outputShape = output.shape.map(\.intValue)
guard outputShape == [1, 3, 2088, 2088] else {
    fatalError("Unexpected output shape: \(outputShape)")
}

let outputValues = output.dataPointer.assumingMemoryBound(to: Float16.self)
let sample = Float(outputValues[output.count / 2])
guard sample.isFinite else {
    fatalError("Model output contains a non-finite sample.")
}

print("Core ML smoke test passed")
print("Input: \(input.shape.map(\.intValue)) Float16")
print("Output: \(outputShape) Float16")
print("Sample output: \(sample)")
