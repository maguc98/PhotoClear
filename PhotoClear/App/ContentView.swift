import SwiftUI
import PhotosUI
import Photos

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var originalImage: UIImage?
    @State private var enhancedImage: UIImage?
    @State private var isProcessing = false
    @State private var processingProgress: Double = 0
    @State private var processingStage = "准备处理照片…"
    @State private var isAIProcessing = false
    @State private var progressTask: Task<Void, Never>?
    @State private var comparisonPosition: CGFloat = 0.5
    @State private var strength: Double = 0.65
    @State private var selectedPreset: EnhancementPreset = .natural
    @State private var aiScale = 2
    @State private var showMessage = false
    @State private var message = ""
    @State private var previewZoom: CGFloat = 1
    @State private var previewBaseZoom: CGFloat = 1
    @State private var previewOffset: CGSize = .zero
    @State private var previewDragOffset: CGSize = .zero
    @State private var previewDragMode = 0 // 1: divider, 2: pan image, 3: compare
    @State private var previewDragStartPosition: CGFloat = 0.5

    private let processor = ImageEnhancementEngine()

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 750
            ZStack {
                Color(red: 0.955, green: 0.968, blue: 0.985).ignoresSafeArea()

                VStack(spacing: compact ? 10 : 14) {
                    header

                    if let originalImage {
                        imageComparison(originalImage)
                            .frame(minHeight: 0, maxHeight: .infinity)

                        compactControls(compact: compact)
                    } else {
                        importCard
                            .frame(maxHeight: .infinity)
                    }

                    privacyNote
                }
                .padding(.horizontal, 16)
                .padding(.top, compact ? 6 : 12)
                .padding(.bottom, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedItem) { _, item in Task { await loadPhoto(item) } }
        .alert("PhotoClear", isPresented: $showMessage) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PHOTOCLEAR")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.blue)
                Text("照片清晰增强")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
            }
            Spacer()
            if originalImage != nil {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 42, height: 42)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isProcessing)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var importCard: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue)
                Text("选择照片开始增强")
                    .font(.title3.weight(.semibold))
                Text("导入、处理、对比和保存，一屏完成")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("从相册选择")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(.blue, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(.white, in: RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(.plain)
    }

    private func imageComparison(_ image: UIImage) -> some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(Color.white)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .scaleEffect(previewZoom)
                        .offset(x: previewOffset.width + previewDragOffset.width, y: previewOffset.height + previewDragOffset.height)

                    if let enhancedImage {
                        Image(uiImage: enhancedImage)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .scaleEffect(previewZoom)
                            .offset(x: previewOffset.width + previewDragOffset.width, y: previewOffset.height + previewDragOffset.height)
                            .mask(alignment: .trailing) {
                                Rectangle().frame(width: max(0, proxy.size.width * (1 - comparisonPosition)))
                            }
                    }

                    if enhancedImage != nil {
                        ZStack {
                            Rectangle()
                                .fill(.white)
                                .frame(width: 2)
                            Circle()
                                .fill(.white)
                                .frame(width: 34, height: 34)
                                .overlay(Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.blue))
                                .shadow(color: .black.opacity(0.14), radius: 4, y: 1)
                        }
                        .offset(x: proxy.size.width * comparisonPosition - proxy.size.width / 2)

                    }

                    VStack {
                        HStack {
                            badge(enhancedImage == nil ? "原图" : "原图 / 增强对比")
                            Spacer()
                            if previewZoom > 1.01 {
                                Button {
                                    withAnimation(.spring(duration: 0.25)) {
                                        previewZoom = 1
                                        previewBaseZoom = 1
                                        previewOffset = .zero
                                        previewDragOffset = .zero
                                    }
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(.black.opacity(0.45), in: Circle())
                                }
                                .accessibilityLabel("恢复原比例")
                            }
                        }
                        Spacer()
                        HStack {
                            badge("原图")
                            Spacer()
                            badge(enhancedImage == nil ? "待增强" : (previewZoom > 1.01 ? "增强图 · 放大查看" : "增强图 · 拖动对比"))
                        }
                    }
                    .padding(12)

                    if isProcessing || processingProgress >= 1 {
                        processingStatus
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .contentShape(RoundedRectangle(cornerRadius: 22))
                .highPriorityGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            previewZoom = min(max(previewBaseZoom * value, 1), 5)
                        }
                        .onEnded { _ in
                            previewBaseZoom = previewZoom
                            if previewZoom <= 1.01 {
                                previewZoom = 1
                                previewBaseZoom = 1
                                previewOffset = .zero
                                previewDragOffset = .zero
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            if previewDragMode == 0 {
                                let dividerX = proxy.size.width * comparisonPosition
                                let touchNearDivider = abs(value.startLocation.x - dividerX) <= 38
                                previewDragStartPosition = comparisonPosition
                                if enhancedImage != nil && touchNearDivider {
                                    previewDragMode = 1
                                } else if previewZoom > 1.01 {
                                    previewDragMode = 2
                                } else if enhancedImage != nil {
                                    previewDragMode = 3
                                }
                            }
                            switch previewDragMode {
                            case 1, 3:
                                comparisonPosition = min(max(previewDragStartPosition + value.translation.width / max(proxy.size.width, 1), 0), 1)
                            case 2:
                                previewDragOffset = value.translation
                            default:
                                break
                            }
                        }
                        .onEnded { value in
                            if previewDragMode == 2 {
                                previewOffset.width += value.translation.width
                                previewOffset.height += value.translation.height
                            }
                            previewDragOffset = .zero
                            previewDragMode = 0
                        }
                )
            }
        }
    }

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.black.opacity(0.48), in: Capsule())
    }

    private func compactControls(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: 7) {
                ForEach(EnhancementPreset.allCases) { preset in
                    Button {
                        selectedPreset = preset
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: preset.symbol)
                            Text(preset.title)
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selectedPreset == preset ? .blue : .primary)
                        .background(selectedPreset == preset ? Color.blue.opacity(0.10) : Color.white, in: Capsule())
                        .overlay(Capsule().stroke(selectedPreset == preset ? Color.blue.opacity(0.25) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                }
            }

            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI 超分")
                        .font(.subheadline.weight(.semibold))
                    Text("Real-ESRGAN · 离线")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Picker("放大倍数", selection: $aiScale) {
                    Text("2×").tag(2)
                    Text("4×").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 112)
                .disabled(isProcessing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))

            HStack(spacing: 8) {
                Button(action: runEnhancement) {
                    Label("普通增强", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.blue)
                        .background(Color.blue.opacity(0.09), in: Capsule())
                }
                .disabled(isProcessing)

                Button(action: runAIUpscale) {
                    Label(isProcessing ? "处理中" : "AI 放大", systemImage: "sparkles.rectangle.stack")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(.blue, in: Capsule())
                }
                .disabled(isProcessing)

                if enhancedImage != nil {
                    Button(action: saveEnhanced) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(.blue)
                            .background(.white, in: Circle())
                    }
                    .accessibilityLabel("保存增强照片")
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 20))
    }

    private var processingStatus: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                if processingProgress >= 1 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ProgressView().controlSize(.small).tint(.blue)
                }
                Text(processingProgress >= 1 ? "处理完成" : processingStage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(processingProgress >= 1 ? .green : .primary)
                Spacer()
                Text("\(Int(processingProgress * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: processingProgress)
                .tint(processingProgress >= 1 ? .green : .blue)
                .animation(.easeInOut(duration: 0.25), value: processingProgress)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func beginProgress(ai: Bool) {
        progressTask?.cancel()
        isAIProcessing = ai
        processingProgress = 0.02
        processingStage = ai ? "正在加载 AI 模型…" : "正在分析照片…"
        progressTask = Task { @MainActor in
            while !Task.isCancelled && processingProgress < 0.94 {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { break }
                let step = ai ? 0.006 : 0.022
                processingProgress = min(0.94, processingProgress + step)
                if ai {
                    processingStage = processingProgress < 0.18 ? "正在加载 AI 模型…" :
                        processingProgress < 0.72 ? "AI 正在重建图像…" : "正在生成高清图片…"
                } else {
                    processingStage = processingProgress < 0.35 ? "正在分析照片…" :
                        processingProgress < 0.78 ? "正在增强细节…" : "正在完成处理…"
                }
            }
        }
    }

    @MainActor
    private func completeProgress() {
        progressTask?.cancel()
        processingProgress = 1
        processingStage = "处理完成"
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            if !isProcessing {
                processingProgress = 0
                processingStage = "准备处理照片…"
            }
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield.fill").foregroundStyle(.green)
            Text("完全本地处理 · 不上传照片")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
            previewZoom = 1
            previewBaseZoom = 1
            previewOffset = .zero
            previewDragOffset = .zero
        } catch {
            message = "导入照片失败：\(error.localizedDescription)"
            showMessage = true
        }
    }

    private func runEnhancement() {
        guard let originalImage, !isProcessing else { return }
        isProcessing = true
        beginProgress(ai: false)
        Task {
            let result = await processor.enhance(originalImage, preset: selectedPreset, strength: strength)
            await MainActor.run {
                enhancedImage = result
                comparisonPosition = 0.5
                isProcessing = false
                completeProgress()
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
        beginProgress(ai: true)
        Task {
            do {
                let result = try await RealESRGANUpscaler.shared.upscale(originalImage, outputScale: aiScale)
                await MainActor.run {
                    enhancedImage = result.image
                    comparisonPosition = 0.5
                    isProcessing = false
                    completeProgress()
                    if result.inputWasDownscaled {
                        message = "为了保护设备内存，超大照片已自动缩小到安全尺寸后进行 AI 增强。输出尺寸为 \(Int(result.outputPixelSize.width)) × \(Int(result.outputPixelSize.height))。"
                        showMessage = true
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    progressTask?.cancel()
                    processingProgress = 0
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
                    message = success ? "增强后的照片已经保存到相册。" : "保存失败：\(error?.localizedDescription ?? "未知错误")"
                    showMessage = true
                }
            }
        }
    }
}

private struct ZoomComparisonView: View {
    let original: UIImage
    let enhanced: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var comparison: CGFloat = 0.5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                ZStack {
                    Image(uiImage: enhanced ?? original)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture().onChanged { value in
                                zoom = min(max(baseZoom * value, 1), 6)
                            }.onEnded { _ in baseZoom = zoom
                            }
                        )
                        .simultaneousGesture(DragGesture().onChanged { value in
                            if zoom > 1 { offset = value.translation }
                        })

                    if enhanced != nil && zoom == 1 {
                        Image(uiImage: original)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoom)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: proxy.size.width * comparison)
                            }
                            .overlay(alignment: .leading) {
                                Rectangle().fill(.white).frame(width: 2)
                                    .offset(x: proxy.size.width * comparison)
                            }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if enhanced != nil && zoom == 1 {
                        comparison = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                    }
                })
            }

            VStack {
                HStack {
                    Button("完成") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.15), in: Capsule())
                    Spacer()
                    Text(zoom > 1 ? "\(Int(zoom * 100))%" : (enhanced == nil ? "原图" : "增强效果 / 原图对比"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("双指捏合放大 · 放大后拖动查看细节")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
        .statusBarHidden()
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
