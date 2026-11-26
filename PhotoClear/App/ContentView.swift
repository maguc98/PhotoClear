import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var originalImage: UIImage?
    @State private var enhancedImage: UIImage?
    @State private var isProcessing = false
    @State private var showEnhanced = false
    @State private var strength: Double = 0.65
    @State private var selectedPreset: EnhancementPreset = .natural

    private let processor = ImageEnhancementEngine()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.96, green: 0.97, blue: 0.99).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header

                        if let originalImage {
                            imageComparison(originalImage)
                            controls
                        } else {
                            importCard
                        }

                        if isProcessing {
                            ProgressView("正在本地增强…")
                                .tint(.blue)
                                .padding(.vertical, 8)
                        }

                        privacyNote
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: selectedItem) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PHOTOCLEAR")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.blue)
                Text("让照片重新清晰")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 18)
    }

    private var importCard: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
            VStack(spacing: 16) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue)
                Text("选择一张照片")
                    .font(.title3.weight(.semibold))
                Text("导入后将在设备本地进行增强")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("选择照片")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(.blue, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .background(.white, in: RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
    }

    private func imageComparison(_ image: UIImage) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                Image(uiImage: showEnhanced ? (enhancedImage ?? image) : image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(8)
            }
            .frame(maxHeight: 440)

            HStack {
                Label("原图", systemImage: "photo")
                Spacer()
                Button {
                    showEnhanced.toggle()
                } label: {
                    Label(showEnhanced ? "查看原图" : "查看增强", systemImage: "arrow.left.arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(enhancedImage == nil)
                Spacer()
                Label("增强", systemImage: "sparkles")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("增强模式")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(EnhancementPreset.allCases) { preset in
                    Button {
                        selectedPreset = preset
                        runEnhancement()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 20))
                            Text(preset.title)
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(selectedPreset == preset ? .blue : .primary)
                        .background(selectedPreset == preset ? Color.blue.opacity(0.09) : Color.white,
                                   in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(selectedPreset == preset ? Color.blue.opacity(0.35) : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("增强强度")
                    Spacer()
                    Text("\(Int(strength * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $strength, in: 0.1...1, onEditingChanged: { editing in
                    if !editing { runEnhancement() }
                })
            }

            Button(action: runEnhancement) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("开始增强")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(.blue, in: Capsule())
            }
            .disabled(isProcessing)

            if enhancedImage != nil {
                Button(action: saveEnhanced) {
                    Label("保存增强照片", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.blue)
                        .background(Color.blue.opacity(0.08), in: Capsule())
                }
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("更换照片", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.green)
            Text("照片仅在本机处理，不会上传")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            originalImage = image
            enhancedImage = nil
            showEnhanced = false
        } catch {
            print("Photo import failed: \(error)")
        }
    }

    private func runEnhancement() {
        guard let originalImage else { return }
        isProcessing = true
        Task {
            let result = await processor.enhance(originalImage, preset: selectedPreset, strength: strength)
            await MainActor.run {
                enhancedImage = result
                showEnhanced = true
                isProcessing = false
            }
        }
    }

    private func saveEnhanced() {
        guard let enhancedImage else { return }
        UIImageWriteToSavedPhotosAlbum(enhancedImage, nil, nil, nil)
    }
}

enum EnhancementPreset: String, CaseIterable, Identifiable {
    case natural, clear, portrait
    var id: String { rawValue }
    var title: String {
        switch self {
        case .natural: "自然"
        case .clear: "清晰"
        case .portrait: "人像"
        }
    }
    var symbol: String {
        switch self {
        case .natural: "leaf"
        case .clear: "sparkles"
        case .portrait: "person.crop.square"
        }
    }
}
