import SwiftUI
import PhotosUI
import Photos

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var originalImage: UIImage?
    @State private var enhancedImage: UIImage?
    @State private var isProcessing = false
    @State private var comparisonPosition: CGFloat = 0.5
    @State private var strength: Double = 0.65
    @State private var selectedPreset: EnhancementPreset = .natural
    @State private var aiScale = 2
    @State private var showMessage = false
    @State private var message = ""

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
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(.blue)
                                Text("正在本地增强照片…")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
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
            .alert("PhotoClear", isPresented: $showMessage) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
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
                Text("照片只会在这台设备上处理")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("从相册导入")
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
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width - 16, height: proxy.size.height - 16)

                    if let enhancedImage {
                        Image(uiImage: enhancedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width - 16, height: proxy.size.height - 16)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: max(0, (proxy.size.width - 16) * comparisonPosition))
                            }
                    }

                    if enhancedImage != nil {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2)
                            .shadow(color: .black.opacity(0.2), radius: 3)
                            .overlay {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        Image(systemName: "arrow.left.and.right")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.blue)
                                    }
                                    .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                            }
                            .offset(x: (proxy.size.width - 16) * comparisonPosition - (proxy.size.width - 16) / 2)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .contentShape(RoundedRectangle(cornerRadius: 24))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard enhancedImage != nil else { return }
                            let usableWidth = max(proxy.size.width - 16, 1)
                            let localX = value.location.x - 8
                            comparisonPosition = min(max(localX / usableWidth, 0), 1)
                        }
                )
            }
            .frame(height: 390)

            HStack {
                Label(enhancedImage == nil ? "原始照片" : "增强效果", systemImage: "sparkles")
                Spacer()
                Text(enhancedImage == nil ? "完成增强后可拖动对比" : "拖动中间滑块查看前后效果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("原图", systemImage: "photo")
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
                        .foregroundStyle(selectedPreset == preset ? Color.blue : Color.primary)
                        .background(
                            selectedPreset == preset ? Color.blue.opacity(0.09) : Color.white,
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedPreset == preset ? Color.blue.opacity(0.35) : Color.clear)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 42, height: 42)
                        .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI 超分辨率")
                            .font(.headline)
                        Text("Real-ESRGAN · Core ML · 完全离线")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Picker("输出尺寸", selection: $aiScale) {
                    Text("2× 放大").tag(2)
                    Text("4× 放大").tag(4)
                }
                .pickerStyle(.segmented)
                .disabled(isProcessing)

                Button(action: runAIUpscale) {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack")
                        Text(isProcessing ? "AI 正在处理…" : "开始 AI 超分增强")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(Color.blue, in: Capsule())
                }
                .disabled(isProcessing)

                Text("模型随 App 安装，照片不会上传。大尺寸照片会自动按设备内存限制调整处理尺寸。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))

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
                    Text(isProcessing ? "正在处理…" : "开始增强")
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
            .disabled(isProcessing)
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
                  let image = UIImage(data: data) else {
                message = "无法读取这张照片，请换一张图片试试。"
                showMessage = true
                return
            }
            originalImage = image
            enhancedImage = nil
            comparisonPosition = 0.5
        } catch {
            message = "导入照片失败：\(error.localizedDescription)"
            showMessage = true
        }
    }

    private func runEnhancement() {
        guard let originalImage, !isProcessing else { return }
        isProcessing = true
        Task {
            let result = await processor.enhance(originalImage, preset: selectedPreset, strength: strength)
            await MainActor.run {
                enhancedImage = result
                comparisonPosition = 0.5
                isProcessing = false
                if result == nil {
                    message = "照片增强失败，请尝试更小尺寸的图片。"
                    showMessage = true
                }
            }
        }
    }

    private func runAIUpscale() {
        guard let originalImage, !isProcessing else { return }
        isProcessing = true

        Task {
            do {
                let result = try await RealESRGANUpscaler.shared.upscale(originalImage, outputScale: aiScale)
                await MainActor.run {
                    enhancedImage = result.image
                    comparisonPosition = 0.5
                    isProcessing = false
                    if result.inputWasDownscaled {
                        message = "为了保护设备内存，超大照片已自动缩小到安全尺寸后进行 AI 增强。输出尺寸为 \(Int(result.outputPixelSize.width)) × \(Int(result.outputPixelSize.height))。"
                        showMessage = true
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    message = error.localizedDescription
                    showMessage = true
                }
            }
        }
    }

    private func saveEnhanced() {
        guard let enhancedImage else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    message = "没有获得保存照片的权限。请在系统设置中允许 PhotoClear 添加照片。"
                    showMessage = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: enhancedImage)
            } completionHandler: { success, error in
                Task { @MainActor in
                    if success {
                        message = "增强后的照片已经保存到相册。"
                    } else {
                        message = "保存失败：\(error?.localizedDescription ?? "未知错误")"
                    }
                    showMessage = true
                }
            }
        }
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
