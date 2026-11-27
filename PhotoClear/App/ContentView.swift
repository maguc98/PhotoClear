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
    @State private var comparisonPosition: CGFloat = 0.5
    @State private var aiScale = 2
    @State private var enhancementMode: EnhancementMode = .natural
    @AppStorage("photoclear.stackedUpscalingEnabled") private var stackedUpscalingEnabled = true
    @AppStorage("photoclear.dat2DetailEngineEnabled") private var dat2DetailEngineEnabled = false
    @AppStorage("photoclear.custom.detail") private var customDetail: Double = 0.52
    @AppStorage("photoclear.custom.sharpen") private var customSharpen: Double = 0.18
    @AppStorage("photoclear.custom.denoise") private var customDenoise: Double = 0.18
    @AppStorage("photoclear.custom.texture") private var customTexture: Double = 0.30
    @AppStorage("photoclear.custom.naturalness") private var customNaturalness: Double = 0.92
    @AppStorage("photoclear.custom.color") private var customColor: Double = 0.96
    @State private var showMessage = false
    @State private var message = ""
    @State private var previewZoom: CGFloat = 1
    @State private var previewBaseZoom: CGFloat = 1
    @State private var previewOffset: CGSize = .zero
    @State private var previewDragOffset: CGSize = .zero
    @State private var previewDragMode = 0 // 1: divider, 2: pan image, 3: compare
    @State private var previewDragStartPosition: CGFloat = 0.5
    @State private var hasAppeared = false
    @State private var processingTask: Task<Void, Never>?
    @State private var livePreviewImage: UIImage?
    @State private var livePreviewTileRect: CGRect?
    @State private var livePreviewTileIndex = 0
    @State private var livePreviewTileCount = 0
    @State private var floatingProgressPosition: CGPoint?
    @State private var floatingProgressDragStart: CGPoint?


    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 760
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.952, green: 0.969, blue: 0.995),
                        Color(red: 0.970, green: 0.965, blue: 0.992),
                        Color(red: 0.952, green: 0.979, blue: 0.986)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(Color(red: 0.67, green: 0.82, blue: 1.0).opacity(0.32))
                    .frame(width: 250, height: 250)
                    .blur(radius: 65)
                    .offset(x: 165, y: -300)
                    .allowsHitTesting(false)

                Circle()
                    .fill(Color(red: 0.83, green: 0.76, blue: 1.0).opacity(0.22))
                    .frame(width: 230, height: 230)
                    .blur(radius: 70)
                    .offset(x: -170, y: 320)
                    .allowsHitTesting(false)

                VStack(spacing: compact ? 12 : 14) {
                    header
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)

                    if let originalImage {
                        imageComparison(originalImage)
                            // The spacer below keeps the controls anchored at the bottom
                            // while preserving a dedicated, non-overlapping photo viewport.
                            .frame(
                                width: max(0, geometry.size.width - (compact ? 32 : 40)),
                                height: geometry.size.height * (compact
                                    ? (enhancementMode == .custom ? 0.28 : 0.38)
                                    : (enhancementMode == .custom ? 0.35 : 0.43))
                            )
                            .clipped()
                            .layoutPriority(0)
                            .opacity(hasAppeared ? 1 : 0)
                            .scaleEffect(hasAppeared ? 1 : 0.975)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))

                        Spacer(minLength: compact ? 6 : 10)
                            .frame(maxHeight: compact ? 20 : 26)
                            .layoutPriority(-1)

                        compactControls(compact: compact)
                            .frame(width: max(0, geometry.size.width - (compact ? 32 : 40)))
                            .layoutPriority(1)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        importCard
                            .frame(maxHeight: .infinity)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    privacyNote
                        .opacity(hasAppeared ? 1 : 0)
                }
                .padding(.horizontal, compact ? 16 : 20)
                .padding(.top, compact ? 5 : 12)
                .padding(.bottom, compact ? 5 : 10)
            }
            .overlay(alignment: .topLeading) {
                if isProcessing {
                    floatingProcessingWindow(in: geometry.size)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.82, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.92).combined(with: .opacity)
                        ))
                        .zIndex(100)
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.82).delay(0.06)) {
                    hasAppeared = true
                }
                if floatingProgressPosition == nil {
                    floatingProgressPosition = CGPoint(x: geometry.size.width / 2, y: 150)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: originalImage != nil)
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: enhancedImage != nil)
                        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: aiScale)
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: previewZoom)
            .animation(.easeInOut(duration: 0.24), value: isProcessing)
                        .sensoryFeedback(.selection, trigger: aiScale)
            .sensoryFeedback(.selection, trigger: enhancementMode)
            .sensoryFeedback(.selection, trigger: stackedUpscalingEnabled)
            .onChange(of: stackedUpscalingEnabled) { _, enabled in
                if !enabled && aiScale > 4 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        aiScale = 4
                    }
                }
            }
            .onChange(of: dat2DetailEngineEnabled) { _, enabled in
                if enabled && aiScale > 4 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        aiScale = 4
                    }
                }
            }
            .animation(.linear(duration: 0.18), value: processingProgress)
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.blue)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("PHOTOCLEAR STUDIO")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(2.1)
                        .foregroundStyle(Color(red: 0.15, green: 0.52, blue: 0.91))
                }
                Text("照片清晰增强")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(Color(red: 0.10, green: 0.15, blue: 0.24))
                Text("让每一处细节，都清晰一点")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.48, green: 0.55, blue: 0.65))
            }

            Spacer(minLength: 6)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.92))
                        .frame(width: 50, height: 50)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.95), lineWidth: 1)
                        }
                        .shadow(color: Color.blue.opacity(0.10), radius: 14, y: 6)

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            LinearGradient(colors: [Color.blue, Color(red: 0.31, green: 0.56, blue: 0.96)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 50, height: 50)

                    Circle()
                        .fill(Color(red: 0.27, green: 0.78, blue: 0.56))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: -7, y: 7)
                }
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(isProcessing)
            .accessibilityLabel("选择照片")
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
    }

    private var importCard: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
            VStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.08))
                        .frame(width: 104, height: 104)
                    Circle()
                        .stroke(Color.blue.opacity(0.12), lineWidth: 1)
                        .frame(width: 88, height: 88)
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 38, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            LinearGradient(colors: [Color.blue, Color(red: 0.53, green: 0.56, blue: 0.96)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .symbolEffect(.bounce, value: hasAppeared)
                }

                VStack(spacing: 5) {
                    Text("把照片变清晰")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.18, blue: 0.28))
                    Text("选择照片，使用 AI 重建细节并提升分辨率")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("从相册选择")
                        .font(.system(size: 14, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(height: 48)
                .background(
                    LinearGradient(colors: [Color(red: 0.16, green: 0.58, blue: 0.98),
                                            Color(red: 0.28, green: 0.43, blue: 0.94)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
                .shadow(color: Color.blue.opacity(0.22), radius: 14, y: 7)

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("照片仅在本机处理，不会上传")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color(red: 0.48, green: 0.57, blue: 0.67))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
            .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(LinearGradient(colors: [.white, Color.blue.opacity(0.12)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: Color(red: 0.23, green: 0.39, blue: 0.62).opacity(0.09), radius: 24, y: 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isProcessing)
    }

    private func imageComparison(_ image: UIImage) -> some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                let photoWidth = max(proxy.size.width - 10, 1)
                let photoHeight = max(proxy.size.height - 10, 1)
                let photoSize = CGSize(width: photoWidth, height: photoHeight)

                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.white.opacity(0.97))

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: photoWidth, height: photoHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .scaleEffect(previewZoom)
                        .offset(x: previewOffset.width + previewDragOffset.width,
                                y: previewOffset.height + previewDragOffset.height)

                    if isProcessing, let livePreviewImage {
                        // DAT2 publishes the actual assembled output after each tile.
                        // Untouched regions retain the source baseline; completed tiles
                        // visibly replace those regions with reconstructed detail.
                        Image(uiImage: livePreviewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: photoWidth, height: photoHeight)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                liveTileMarker(in: photoSize)
                            }
                            .scaleEffect(previewZoom)
                            .offset(x: previewOffset.width + previewDragOffset.width,
                                    y: previewOffset.height + previewDragOffset.height)
                            .transition(.opacity)
                    } else if !isProcessing, let enhancedImage {
                        Image(uiImage: enhancedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: photoWidth, height: photoHeight)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .scaleEffect(previewZoom)
                            .offset(x: previewOffset.width + previewDragOffset.width,
                                    y: previewOffset.height + previewDragOffset.height)
                            .mask(alignment: .trailing) {
                                Rectangle()
                                    .frame(width: max(0, photoWidth * (1 - comparisonPosition)))
                            }
                    }

                    if !isProcessing, enhancedImage != nil {
                        ZStack {
                            Rectangle()
                                .fill(.white)
                                .frame(width: 2)
                                .overlay(
                                    LinearGradient(
                                        colors: [.white, Color(red: 0.34, green: 0.72, blue: 1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            Circle()
                                .fill(.white.opacity(0.97))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(Color.blue.opacity(0.14), lineWidth: 1))
                                .overlay(
                                    Image(systemName: "arrow.left.and.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.blue)
                                )
                                .shadow(color: Color.blue.opacity(0.18), radius: 10, y: 3)
                        }
                        .position(
                            x: 5 + photoWidth * comparisonPosition,
                            y: 5 + photoHeight / 2
                        )
                    }

                    VStack {
                        if isProcessing {
                            EmptyView()
                        } else {
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
                        }

                        Spacer()

                        HStack {
                            badge(isProcessing ? "原图底图" : "原图")
                            Spacer()
                            if isProcessing {
                                badge(livePreviewTileCount == 0
                                      ? "等待第一块重构"
                                      : "已完成 \(livePreviewTileIndex)/\(livePreviewTileCount) 块")
                            } else {
                                badge(enhancedImage == nil
                                      ? "待增强"
                                      : (previewZoom > 1.01 ? "增强图 · 放大查看" : "增强图 · 拖动对比"))
                            }
                        }
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.98), lineWidth: 1.2)
                )
                .shadow(
                    color: Color(red: 0.30, green: 0.42, blue: 0.62).opacity(0.09),
                    radius: 16,
                    y: 7
                )
                .contentShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                .highPriorityGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            guard !isProcessing else { return }
                            previewZoom = min(max(previewBaseZoom * value, 1), 5)
                        }
                        .onEnded { _ in
                            guard !isProcessing else { return }
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
                            guard !isProcessing else { return }
                            if previewDragMode == 0 {
                                let dividerX = 5 + photoWidth * comparisonPosition
                                let touchNearDivider = abs(value.startLocation.x - dividerX) <= 38
                                previewDragStartPosition = comparisonPosition
                                if enhancedImage != nil && touchNearDivider {
                                    previewDragMode = 1
                                } else {
                                    // Allow repositioning the crop even at the default zoom.
                                    // Compare divider dragging still takes priority when touched.
                                    previewDragMode = 2
                                }
                            }
                            switch previewDragMode {
                            case 1, 3:
                                comparisonPosition = min(
                                    max(previewDragStartPosition + value.translation.width / max(photoWidth, 1), 0),
                                    1
                                )
                            case 2:
                                let fillScale = max(
                                    photoWidth / max(image.size.width, 1),
                                    photoHeight / max(image.size.height, 1)
                                ) * previewZoom
                                let renderedWidth = image.size.width * fillScale
                                let renderedHeight = image.size.height * fillScale
                                let maxX = max(0, (renderedWidth - photoWidth) / 2)
                                let maxY = max(0, (renderedHeight - photoHeight) / 2)
                                previewDragOffset = CGSize(
                                    width: min(max(previewOffset.width + value.translation.width, -maxX), maxX) - previewOffset.width,
                                    height: min(max(previewOffset.height + value.translation.height, -maxY), maxY) - previewOffset.height
                                )
                            default:
                                break
                            }
                        }
                        .onEnded { value in
                            guard !isProcessing else {
                                previewDragOffset = .zero
                                previewDragMode = 0
                                return
                            }
                            if previewDragMode == 2 {
                                let fillScale = max(
                                    photoWidth / max(image.size.width, 1),
                                    photoHeight / max(image.size.height, 1)
                                ) * previewZoom
                                let renderedWidth = image.size.width * fillScale
                                let renderedHeight = image.size.height * fillScale
                                let maxX = max(0, (renderedWidth - photoWidth) / 2)
                                let maxY = max(0, (renderedHeight - photoHeight) / 2)
                                previewOffset = CGSize(
                                    width: min(max(previewOffset.width + value.translation.width, -maxX), maxX),
                                    height: min(max(previewOffset.height + value.translation.height, -maxY), maxY)
                                )
                            }
                            previewDragOffset = .zero
                            previewDragMode = 0
                        }
                )
            }
        }
    }

    private func floatingProcessingWindow(in screen: CGSize) -> some View {
        let windowWidth = min(screen.width - 36, 340)
        let defaultPosition = CGPoint(x: screen.width / 2, y: 150)
        let position = floatingProgressPosition ?? defaultPosition

        return VStack(spacing: 9) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.blue.opacity(0.10)).frame(width: 38, height: 38)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse, options: .repeating)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 正在重构照片")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.20, blue: 0.33))
                    Text(livePreviewTileCount > 0 ? "正在处理细节 · \(livePreviewTileIndex)/\(livePreviewTileCount) 块" : processingStage)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(red: 0.46, green: 0.55, blue: 0.67))
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Text("\(Int(processingProgress * 100))%")
                    .font(.system(size: 16, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.blue)
                    .contentTransition(.numericText())
                Button {
                    processingTask?.cancel()
                    processingTask = nil
                    isProcessing = false
                    livePreviewImage = nil
                    livePreviewTileRect = nil
                    livePreviewTileIndex = 0
                    livePreviewTileCount = 0
                    enhancedImage = nil
                    processingProgress = 0
                    processingStage = "已停止处理"
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                        .background(Color.red.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("停止 AI 处理")
            }

            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.blue.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue, Color(red: 0.38, green: 0.55, blue: 0.98)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, bar.size.width * processingProgress))
                    Capsule().fill(.white.opacity(0.65))
                        .frame(width: 34)
                        .offset(x: max(0, min(bar.size.width - 34, bar.size.width * processingProgress - 17)))
                        .blur(radius: 2)
                        .opacity(processingProgress < 1 ? 0.8 : 0)
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())

            HStack(spacing: 6) {
                Image(systemName: "hand.draw").font(.system(size: 9, weight: .semibold))
                Text("长按拖动 · 可放置在任意位置").font(.system(size: 9, weight: .medium))
                Spacer()
                if livePreviewTileCount > 0 {
                    Text("实时预览").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.blue)
                }
            }
            .foregroundStyle(Color(red: 0.48, green: 0.56, blue: 0.67))
        }
        .padding(12)
        .frame(width: windowWidth)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white, Color(red: 0.965, green: 0.979, blue: 0.995)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.92), lineWidth: 1)
                }
                .shadow(color: Color(red: 0.42, green: 0.57, blue: 0.78).opacity(0.13), radius: 16, y: 7)
        }
        .position(
            x: min(max(position.x, windowWidth / 2 + 8), screen.width - windowWidth / 2 - 8),
            y: min(max(position.y, 72), screen.height - 80)
        )
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if floatingProgressDragStart == nil { floatingProgressDragStart = position }
                    guard let start = floatingProgressDragStart else { return }
                    floatingProgressPosition = CGPoint(
                        x: min(max(start.x + value.translation.width, windowWidth / 2 + 8), screen.width - windowWidth / 2 - 8),
                        y: min(max(start.y + value.translation.height, 72), screen.height - 80)
                    )
                }
                .onEnded { _ in floatingProgressDragStart = nil }
        )
        .animation(.spring(response: 0.36, dampingFraction: 0.76), value: processingProgress)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: livePreviewTileIndex)
    }

    @ViewBuilder
    private func liveTileMarker(in viewport: CGSize) -> some View {
        if let tileRect = livePreviewTileRect, let preview = livePreviewImage {
            let imageSize = preview.size
            let scale = max(
                viewport.width / max(imageSize.width, 1),
                viewport.height / max(imageSize.height, 1)
            )
            let fittedWidth = imageSize.width * scale
            let fittedHeight = imageSize.height * scale
            let originX = (viewport.width - fittedWidth) / 2
            let originY = (viewport.height - fittedHeight) / 2

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.blue.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(.white.opacity(0.95), lineWidth: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.blue.opacity(0.85), lineWidth: 1)
                )
                .frame(
                    width: max(2, fittedWidth * tileRect.width),
                    height: max(2, fittedHeight * tileRect.height)
                )
                .position(
                    x: originX + fittedWidth * tileRect.midX,
                    y: originY + fittedHeight * tileRect.midY
                )
                .animation(.easeInOut(duration: 0.16), value: tileRect)
                .allowsHitTesting(false)
        }
    }

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.15)
            .foregroundStyle(.white.opacity(0.96))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.42), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    private func compactControls(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 11) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.91, green: 0.955, blue: 1.0))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(dat2DetailEngineEnabled ? "AI 细节重构" : "AI 超分辨率")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.14, green: 0.19, blue: 0.28))
                    Text(dat2DetailEngineEnabled ? "4×BHI DAT2 · 照片纹理修复" : "REAL-ESRGAN · 本地 AI 超分")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.25)
                        .foregroundStyle(Color(red: 0.53, green: 0.59, blue: 0.68))
                }
                Spacer(minLength: 3)
                HStack(spacing: 3) {
                    ForEach([2, 4, 8, 12], id: \.self) { scale in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                aiScale = scale
                            }
                        } label: {
                            Text("\(scale)×")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(aiScale == scale ? Color(red: 0.12, green: 0.48, blue: 0.86) : Color(red: 0.48, green: 0.56, blue: 0.66))
                                .frame(maxWidth: .infinity)
                                .frame(height: compact ? 34 : 36)
                                .background {
                                    if aiScale == scale {
                                        Capsule().fill(LinearGradient(colors: [Color.white, Color(red: 0.90, green: 0.96, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                                            .overlay(Capsule().stroke(Color.blue.opacity(0.12), lineWidth: 0.8))
                                            .shadow(color: Color.blue.opacity(0.07), radius: 4, y: 1)
                                    }
                                }
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(isProcessing || (scale > 4 && (!stackedUpscalingEnabled || dat2DetailEngineEnabled)))
                        .opacity(scale > 4 && (!stackedUpscalingEnabled || dat2DetailEngineEnabled) ? 0.38 : 1)
                    }
                }
                .padding(3)
                .background(Color(red: 0.94, green: 0.96, blue: 0.985), in: Capsule())
                .frame(width: compact ? 136 : 164)
                .disabled(isProcessing)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, compact ? 6 : 8)
            .background(Color(red: 0.978, green: 0.985, blue: 0.997), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.95), lineWidth: 1))

            modeSelector

            if !dat2DetailEngineEnabled {
                stackedAlgorithmControl(compact: compact)
            }
            detailEngineControl(compact: compact)

            if enhancementMode == .custom {
                customAdjustmentPanel(compact: compact)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Button(action: runAIUpscale) {
                    HStack(spacing: 8) {
                        Image(systemName: isProcessing ? "sparkles" : "sparkles.rectangle.stack")
                            .font(.system(size: 16, weight: .semibold))
                            .symbolEffect(.pulse, options: .repeating, isActive: isProcessing)
                        Text(isProcessing ? "AI 正在运行" : (dat2DetailEngineEnabled ? "AI 细节重构" : "AI 超分增强"))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 48 : 52)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [Color(red: 0.10, green: 0.59, blue: 0.99),
                                                Color(red: 0.20, green: 0.43, blue: 0.94)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: Color.blue.opacity(0.16), radius: 10, y: 4)
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(isProcessing)

                if enhancedImage != nil {
                    Button(action: saveEnhanced) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.51, blue: 0.90))
                            .frame(width: compact ? 46 : 50, height: compact ? 46 : 50)
                            .background(.white, in: Circle())
                            .overlay(Circle().stroke(Color.blue.opacity(0.10), lineWidth: 1))
                            .shadow(color: Color.blue.opacity(0.08), radius: 8, y: 3)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityLabel("保存增强照片")
                    .transition(.scale.combined(with: .opacity))
                }

                if let enhancedImage {
                    ShareLink(
                        item: Image(uiImage: enhancedImage),
                        preview: SharePreview("PhotoClear AI 超分照片", image: Image(uiImage: enhancedImage))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.51, blue: 0.90))
                            .frame(width: compact ? 42 : 46, height: compact ? 42 : 46)
                            .background(.white, in: Circle())
                            .overlay(Circle().stroke(Color.blue.opacity(0.10), lineWidth: 1))
                            .shadow(color: Color.blue.opacity(0.07), radius: 7, y: 2)
                    }
                    .accessibilityLabel("分享增强照片")
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(compact ? 10 : 13)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(LinearGradient(colors: [.white, Color.blue.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.0)
        }
        .shadow(color: Color(red: 0.25, green: 0.38, blue: 0.59).opacity(0.07), radius: 15, y: 7)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: enhancedImage != nil)
    }

    private var enhancementSettings: EnhancementSettings {
        if enhancementMode != .custom {
            return enhancementMode.defaultSettings
        }
        return EnhancementSettings(
            mode: .custom,
            detailRecovery: Float(customDetail),
            sharpening: Float(customSharpen),
            noiseReduction: Float(customDenoise),
            texture: Float(customTexture),
            naturalness: Float(customNaturalness),
            colorPreservation: Float(customColor)
        )
    }

    private var modeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(EnhancementMode.allCases) { mode in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            enhancementMode = mode
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 10, weight: .semibold))
                            Text(mode.title)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(enhancementMode == mode ? Color(red: 0.12, green: 0.48, blue: 0.86) : Color(red: 0.46, green: 0.54, blue: 0.64))
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(enhancementMode == mode ? Color(red: 0.89, green: 0.95, blue: 1.0) : .white.opacity(0.82), in: Capsule())
                        .overlay(Capsule().stroke(Color.blue.opacity(enhancementMode == mode ? 0.16 : 0.06), lineWidth: 1))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(isProcessing)
                }
            }
            .padding(.horizontal, 1)
        }
        .clipped()
    }

    private func detailEngineControl(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            aiProcessingOption(
                title: dat2DetailEngineEnabled ? "DAT2 细节重构已启用" : "启用 AI 细节重构",
                symbol: "text.magnifyingglass",
                isEnabled: $dat2DetailEngineEnabled,
                compact: compact
            )
            Text(dat2DetailEngineEnabled
                 ? "针对真实照片纹理、轻微模糊和压缩痕迹优化；可改善布料、头发等细节，但不保证还原原图已丢失的信息。"
                 : "开启后使用内嵌 DAT2 模型重建照片纹理；关闭时继续使用现有 Real-ESRGAN。")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(red: 0.53, green: 0.60, blue: 0.69))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(red: 0.978, green: 0.985, blue: 0.997), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white, lineWidth: 1))
    }

    private func stackedAlgorithmControl(compact: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.blue)
                .frame(width: 30, height: 30)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("多阶段堆叠放大")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.32))
                Text(stackedUpscalingEnabled ? "启用分块处理与 8× / 12× 尺寸扩展" : "关闭后仅提供原生 2× / 4×")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(red: 0.53, green: 0.60, blue: 0.69))
            }
            Spacer(minLength: 4)
            Toggle("多阶段堆叠放大", isOn: $stackedUpscalingEnabled)
                .labelsHidden()
                .tint(.blue)
                .scaleEffect(compact ? 0.84 : 0.9)
                .disabled(isProcessing)
                .accessibilityLabel("多阶段堆叠放大")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, compact ? 5 : 7)
        .background(Color(red: 0.978, green: 0.985, blue: 0.997), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white, lineWidth: 1))
    }

    private func customAdjustmentPanel(compact: Bool) -> some View {
        VStack(spacing: compact ? 7 : 9) {
            HStack {
                Text("自定义增强参数")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.32))
                Spacer()
                Text("自动保存在本机")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("恢复默认") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        customDetail = 0.52
                        customSharpen = 0.18
                        customDenoise = 0.18
                        customTexture = 0.30
                        customNaturalness = 0.92
                        customColor = 0.96
                    }
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.blue)
                .disabled(isProcessing)
            }
            HStack(spacing: 12) {
                customParameterSlider("细节恢复", value: $customDetail)
                customParameterSlider("锐化强度", value: $customSharpen)
            }
            HStack(spacing: 12) {
                customParameterSlider("降噪强度", value: $customDenoise)
                customParameterSlider("纹理增强", value: $customTexture)
            }
            HStack(spacing: 12) {
                customParameterSlider("自然度保护", value: $customNaturalness)
                customParameterSlider("色彩保留", value: $customColor)
            }
            Text("调整会作用于最终 AI 输出；数值越高，所对应的处理越明显。")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(red: 0.54, green: 0.61, blue: 0.69))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color(red: 0.965, green: 0.978, blue: 0.995), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white, lineWidth: 1))
    }

    private func customParameterSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(red: 0.38, green: 0.47, blue: 0.59))
                Spacer(minLength: 2)
                Text("\(Int(value.wrappedValue * 100))")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.blue)
            }
            Slider(value: value, in: 0...1)
                .tint(Color(red: 0.25, green: 0.58, blue: 0.94))
                .disabled(isProcessing)
        }
        .frame(maxWidth: .infinity)
    }

    private func aiProcessingOption(title: String, symbol: String, isEnabled: Binding<Bool>, compact: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                isEnabled.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                Spacer(minLength: 2)
                Image(systemName: isEnabled.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isEnabled.wrappedValue
                ? Color(red: 0.13, green: 0.49, blue: 0.86)
                : Color(red: 0.48, green: 0.55, blue: 0.65))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 34 : 37)
            .background(
                isEnabled.wrappedValue
                    ? Color(red: 0.91, green: 0.96, blue: 1.0)
                    : Color.white.opacity(0.72),
                in: Capsule()
            )
            .overlay(Capsule().stroke(Color.blue.opacity(isEnabled.wrappedValue ? 0.14 : 0.06), lineWidth: 1))
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isProcessing)
    }

    private func beginProgress() {
        processingProgress = 0.02
        processingStage = "正在加载 AI 模型…"
    }

    @MainActor
    private func completeProgress() {
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
        HStack(spacing: 7) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.20, green: 0.71, blue: 0.48))
            Text("完全本地处理")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.61))
            Circle()
                .fill(Color(red: 0.70, green: 0.75, blue: 0.82))
                .frame(width: 3, height: 3)
            Text("不上传照片")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(red: 0.52, green: 0.59, blue: 0.68))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(.white.opacity(0.60), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
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
            livePreviewImage = nil
            livePreviewTileRect = nil
            livePreviewTileIndex = 0
            livePreviewTileCount = 0
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

    private func runAIUpscale() {
        guard let originalImage, !isProcessing else { return }
        isProcessing = true
        livePreviewImage = nil
        livePreviewTileRect = nil
        livePreviewTileIndex = 0
        livePreviewTileCount = 0
        enhancedImage = nil
        beginProgress()
        processingTask = Task {
            do {
                let result: RealESRGANResult
                if dat2DetailEngineEnabled {
                    result = try await DAT2DetailReconstructor.shared.upscale(
                        originalImage,
                        outputScale: aiScale,
                        settings: enhancementSettings
                    ) { progress, stage in
                        Task { @MainActor in
                            guard isProcessing else { return }
                            processingProgress = min(max(progress, 0.02), 0.99)
                            processingStage = stage
                        }
                    } livePreview: { preview, tileRect, tileIndex, tileCount in
                        Task { @MainActor in
                            guard isProcessing else { return }
                            livePreviewImage = preview
                            livePreviewTileRect = tileRect
                            livePreviewTileIndex = tileIndex
                            livePreviewTileCount = tileCount
                        }
                    }
                } else {
                    result = try await RealESRGANUpscaler.shared.upscale(
                        originalImage,
                        outputScale: aiScale,
                        settings: enhancementSettings,
                        stackedUpscalingEnabled: stackedUpscalingEnabled
                    ) { progress, stage in
                        Task { @MainActor in
                            guard isProcessing else { return }
                            processingProgress = min(max(progress, 0.02), 0.99)
                            processingStage = stage
                        }
                    }
                }
                await MainActor.run {
                    enhancedImage = result.image
                    livePreviewImage = nil
                    livePreviewTileRect = nil
                    livePreviewTileIndex = 0
                    livePreviewTileCount = 0
                    processingTask = nil
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
                    processingTask = nil
                    livePreviewImage = nil
                    livePreviewTileRect = nil
                    livePreviewTileIndex = 0
                    livePreviewTileCount = 0
                    processingProgress = 0
                    if Task.isCancelled || error is CancellationError {
                        processingStage = "已停止处理"
                        return
                    }
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

private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
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
