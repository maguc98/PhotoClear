import Foundation

enum EnhancementMode: String, CaseIterable, Identifiable, Sendable {
    case natural
    case portrait
    case night
    case landscape
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "自然"
        case .portrait: "人物"
        case .night: "夜景"
        case .landscape: "景色"
        case .custom: "自定义"
        }
    }

    var symbol: String {
        switch self {
        case .natural: "leaf"
        case .portrait: "person.crop.square"
        case .night: "moon.stars"
        case .landscape: "mountain.2"
        case .custom: "slider.horizontal.3"
        }
    }

    var defaultSettings: EnhancementSettings {
        switch self {
        case .natural:
            EnhancementSettings(mode: self, detailRecovery: 0.52, sharpening: 0.18, noiseReduction: 0.16, texture: 0.26, naturalness: 0.94, colorPreservation: 0.98)
        case .portrait:
            EnhancementSettings(mode: self, detailRecovery: 0.48, sharpening: 0.13, noiseReduction: 0.20, texture: 0.52, naturalness: 0.97, colorPreservation: 0.99)
        case .night:
            EnhancementSettings(mode: self, detailRecovery: 0.44, sharpening: 0.12, noiseReduction: 0.78, texture: 0.24, naturalness: 0.92, colorPreservation: 0.98)
        case .landscape:
            EnhancementSettings(mode: self, detailRecovery: 0.68, sharpening: 0.28, noiseReduction: 0.18, texture: 0.70, naturalness: 0.82, colorPreservation: 0.96)
        case .custom:
            EnhancementSettings(mode: self, detailRecovery: 0.52, sharpening: 0.18, noiseReduction: 0.18, texture: 0.30, naturalness: 0.92, colorPreservation: 0.96)
        }
    }
}

struct EnhancementSettings: Sendable {
    let mode: EnhancementMode
    let detailRecovery: Float
    let sharpening: Float
    let noiseReduction: Float
    let texture: Float
    let naturalness: Float
    let colorPreservation: Float
}
