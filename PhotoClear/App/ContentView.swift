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
    @State private var hasAppeared = false

    private let processor = ImageEnhancementEngine()

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

                VStack(spacing: compact ? 8 : 12) {
                    header
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)

                    if let originalImage {
                        imageComparison(originalImage)
                            .frame(minHeight: 0, maxHeight: .infinity)
                            .opacity(hasAppeared ? 1 : 0)
                            .scaleEffect(hasAppeared ? 1 : 0.975)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))

                        compactControls(compact: compact)
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
                .padding(.horizontal, compact ? 13 : 18)
                .padding(.top, compact ? 5 : 12)
                .padding(.bottom, compact ? 5 : 10)
            }
            .onAppear {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.82).delay(0.06)) {
                    hasAppeared = true
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: originalImage != nil)
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: enhancedImage != nil)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: selectedPreset)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: aiScale)
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: previewZoom)
            .animation(.easeInOut(duration: 0.24), value: isProcessing)
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
                    Text("选择一张照片，开始本地增强与细节重建")
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
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.white.opacity(0.97))
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
                                .overlay(LinearGradient(colors: [.white, Color(red: 0.34, green: 0.72, blue: 1)], startPoint: .top, endPoint: .bottom))
                            Circle()
                                .fill(.white.opacity(0.97))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(Color.blue.opacity(0.14), lineWidth: 1))
                                .overlay(Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.blue))
                                .shadow(color: Color.blue.opacity(0.18), radius: 10, y: 3)
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
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.98), lineWidth: 1.2))
                .shadow(color: Color(red: 0.30, green: 0.42, blue: 0.62).opacity(0.09), radius: 16, y: 7)
                .contentShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
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
                                let maxX = max(0, (proxy.size.width * (previewZoom - 1)) / 2)
                                let maxY = max(0, (proxy.size.height * (previewZoom - 1)) / 2)
                                previewDragOffset = CGSize(
                                    width: min(max(previewOffset.width + value.translation.width, -maxX), maxX) - previewOffset.width,
                                    height: min(max(previewOffset.height + value.translation.height, -maxY), maxY) - previewOffset.height
                                )
                            default:
                                break
                            }
                        }
                        .onEnded { value in
                            if previewDragMode == 2 {
                                let maxX = max(0, (proxy.size.width * (previewZoom - 1)) / 2)
                                let maxY = max(0, (proxy.size.height * (previewZoom - 1)) / 2)
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
            HStack(spacing: 5) {
                ForEach(EnhancementPreset.allCases) { preset in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                            selectedPreset = preset
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .symbolEffect(.bounce, value: selectedPreset == preset)
                            Text(preset.title)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: compact ? 39 : 44)
                        .foregroundStyle(selectedPreset == preset ? Color(red: 0.10, green: 0.48, blue: 0.88) : Color(red: 0.38, green: 0.44, blue: 0.54))
                        .background {
                            if selectedPreset == preset {
                                Capsule()
                                    .fill(LinearGradient(colors: [Color(red: 0.88, green: 0.95, blue: 1.0),
                                                                  Color(red: 0.92, green: 0.94, blue: 1.0)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .overlay(Capsule().stroke(Color.blue.opacity(0.18), lineWidth: 1))
                                    .shadow(color: Color.blue.opacity(0.10), radius: 8, y: 3)
                            }
                        }
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(isProcessing)
                }
            }
            .padding(4)
            .background(Color(red: 0.965, green: 0.973, blue: 0.988), in: Capsule())

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
                    Text("AI 超分辨率")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.14, green: 0.19, blue: 0.28))
                    Text("REAL-ESRGAN  ·  本地模型")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.35)
                        .foregroundStyle(Color(red: 0.53, green: 0.59, blue: 0.68))
                }
                Spacer(minLength: 3)
                HStack(spacing: 3) {
                    ForEach([2, 4], id: \.self) { scale in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                aiScale = scale
                            }
                        } label: {
                            Text("\(scale)×")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
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
                        .disabled(isProcessing)
                    }
                }
                .padding(3)
                .background(Color(red: 0.94, green: 0.96, blue: 0.985), in: Capsule())
                .frame(width: compact ? 112 : 126)
                .disabled(isProcessing)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, compact ? 6 : 8)
            .background(Color(red: 0.978, green: 0.985, blue: 0.997), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.95), lineWidth: 1))

            HStack(spacing: 8) {
                Button(action: runEnhancement) {
                    HStack(spacing: 7) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16, weight: .semibold))
                        Text("普通增强")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 47 : 52)
                    .foregroundStyle(Color(red: 0.13, green: 0.48, blue: 0.83))
                    .background(
                        LinearGradient(colors: [Color(red: 0.89, green: 0.95, blue: 1.0),
                                                Color(red: 0.92, green: 0.95, blue: 1.0)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(Color.blue.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(isProcessing)

                Button(action: runAIUpscale) {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 16, weight: .semibold))
                        Text(isProcessing ? "正在处理" : "AI 放大")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 47 : 52)
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

    private var processingStatus: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(processingProgress >= 1 ? Color.green.opacity(0.12) : Color.blue.opacity(0.11))
                        .frame(width: 32, height: 32)
                    Image(systemName: processingProgress >= 1 ? "checkmark" : "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(processingProgress >= 1 ? Color.green : Color.blue)
                        .symbolEffect(.pulse, options: .repeating, isActive: processingProgress < 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(processingProgress >= 1 ? "处理完成" : processingStage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.13, green: 0.19, blue: 0.29))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(processingProgress >= 1 ? "高清照片已经准备好了" : "正在本地运行 · 请稍候")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(red: 0.49, green: 0.56, blue: 0.66))
                }

                Spacer(minLength: 4)

                Text("\(Int(processingProgress * 100))%")
                    .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(processingProgress >= 1 ? Color.green : Color.blue)
                    .contentTransition(.numericText())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 0.89, green: 0.93, blue: 0.98))
                    Capsule()
                        .fill(LinearGradient(colors: processingProgress >= 1
                                             ? [Color(red: 0.24, green: 0.76, blue: 0.48), Color(red: 0.36, green: 0.84, blue: 0.62)]
                                             : [Color(red: 0.18, green: 0.64, blue: 1.0), Color(red: 0.34, green: 0.48, blue: 0.98)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(7, geometry.size.width * processingProgress))
                        .shadow(color: (processingProgress >= 1 ? Color.green : Color.blue).opacity(0.24), radius: 5, y: 1)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.78))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LinearGradient(colors: [.white, Color.blue.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: Color(red: 0.30, green: 0.42, blue: 0.62).opacity(0.10), radius: 15, y: 6)
        .frame(maxWidth: 300)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: processingProgress >= 1)
        .allowsHitTesting(false)
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
