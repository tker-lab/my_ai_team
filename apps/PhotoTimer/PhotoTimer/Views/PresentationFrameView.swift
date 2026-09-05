import SwiftUI

/// 演出パターン(結婚式ムービー風・スタジアムビジョン風)の「間」を実際に描画するビュー。
/// 動画は対象外(TimerController側が常にこれまで通りのフルスクリーン再生に振り分ける)。
struct PresentationFrameView: View {
    let frame: PresentationFrame

    /// フルスクリーンのゆっくりズーム(Ken Burns)・勢いよく迫る登場(zoomPunch)は、
    /// 見た目上は「拡大率が時間とともに変わる」連続的なアニメーションなので、切り替わりの
    /// transition(挿入・削除の演出)とは別に、ここで状態として持って withAnimation で動かす。
    @State private var fullScreenScaleSettled = false
    /// ホワイトアウト・フラッシュの一瞬の白い光。0=見えない、1=真っ白。
    @State private var flashOpacity: Double = 0

    var body: some View {
        ZStack {
            content
                .id(frame.id)
                .transition(transitionStyle)
        }
        .overlay(
            Color.white.opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        // 斜めの動きは「写真を斜めに切るマスク」ではなく、画面の上を通る細い光として描く。
        // これなら縦横どちらの写真でも、主画像が途中で欠けて見えることはない。
        .overlay {
            if frame.transition == .diagonalWipe {
                DiagonalLightSweep()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            startFullScreenAnimationIfNeeded()
            triggerFlashIfNeeded()
        }
        .onChange(of: frame.id) { _, _ in
            fullScreenScaleSettled = false
            startFullScreenAnimationIfNeeded()
            triggerFlashIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch frame.layout {
        case .fullScreen(let image, let assetID, let style):
            ZStack {
                // 写真の内容を推測して切り抜くことはしない。縦横を問わず主画像の全体を表示し、
                // 余白は暗い背景で受ける。背景だけはぼかして画面の一体感を作る。
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 24)
                    .opacity(0.28)
                    .scaleEffect(1.12)
                    .clipped()
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(10)
                    .scaleEffect(scale(for: style))
            }
            .background(Color.black)
            .ignoresSafeArea()
                .accessibilityIdentifier("media-photo-presentation-\(assetID)")
        case .collage(let main, let secondaries, let arrangement):
            collageBody(main: main, secondaries: secondaries, arrangement: arrangement)
                .accessibilityIdentifier("media-photo-presentation-\(main.assetID)")
        }
    }

    @ViewBuilder
    private func collageBody(
        main: (image: UIImage, assetID: String),
        secondaries: [(image: UIImage, assetID: String)],
        arrangement: PresentationFrame.CollageArrangement
    ) -> some View {
        switch arrangement {
        case .bigWithTwoSmall:
            GeometryReader { geo in
                HStack(spacing: 3) {
                    tile(main.image, width: geo.size.width * 0.66, height: geo.size.height)
                    VStack(spacing: 3) {
                        ForEach(Array(secondaries.prefix(2).enumerated()), id: \.offset) { _, item in
                            tile(item.image, width: geo.size.width * 0.34 - 3, height: nil)
                        }
                        // 追加候補が1枚しか無かった場合、余白を埋めて崩れないようにする。
                        if secondaries.count < 2 {
                            Color.black
                        }
                    }
                    .frame(width: geo.size.width * 0.34)
                }
            }
            .ignoresSafeArea()
        case .mosaicThree:
            GeometryReader { geo in
                VStack(spacing: 3) {
                    tile(main.image, width: geo.size.width, height: geo.size.height * 0.6)
                    HStack(spacing: 3) {
                        ForEach(Array(secondaries.prefix(2).enumerated()), id: \.offset) { _, item in
                            tile(item.image, width: nil, height: geo.size.height * 0.4 - 3)
                        }
                        if secondaries.count < 2 {
                            Color.black
                        }
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func tile(_ image: UIImage, width: CGFloat?, height: CGFloat?) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: height == nil ? .infinity : nil)
            .background(Color.black.opacity(0.82))
    }

    // MARK: - 切り替わりの見せ方(transition)

    private var transitionStyle: AnyTransition {
        switch frame.transition {
        case .crossfade, .whiteout, .flash:
            // ホワイトアウト・フラッシュは「白い光」自体をoverlayで別途表現するため、
            // 中身の切り替わり自体はクロスフェードのままにしておく(白い光と自然に重なる)。
            return .opacity
        case .zoomPunch:
            // 主画像を一瞬でも拡大すると、aspect fitでも周縁が見切れる可能性がある。
            // 写真は常に全体を収めるという方針を守り、勢いはフラッシュ等の隣接遷移との
            // リズムで作る。ここでは拡大を伴わないフェードだけを使う。
            return .opacity
        case .diagonalWipe:
            // 以前はここで画面全体(=写真本体を含む)を斜めの形にマスクしていたため、
            // スタジアムビジョン風で写真が斜めに欠けて見えることがあった。写真の切り抜きは
            // しない方針なので、切り替え自体はフェード、斜め要素は上の光の帯だけにする。
            return .opacity
        }
    }

    // MARK: - フルスクリーンの連続アニメーション(Ken Burns / zoomPunch)

    private func scale(for style: PresentationFrame.FullScreenStyle) -> CGFloat {
        switch style {
        // 拡大で主画像を切らない。動きは切り替え側のtransitionと透明度で付ける。
        case .kenBurns, .zoomPunch: return 1.0
        }
    }

    private func startFullScreenAnimationIfNeeded() {
        guard case .fullScreen(_, _, let style) = frame.layout else { return }
        switch style {
        case .kenBurns:
            withAnimation(.linear(duration: 0.1)) { fullScreenScaleSettled = true }
        case .zoomPunch:
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { fullScreenScaleSettled = true }
        }
    }

    private func triggerFlashIfNeeded() {
        switch frame.transition {
        case .whiteout:
            flashOpacity = 0
            withAnimation(.easeIn(duration: 0.3)) { flashOpacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.5)) { flashOpacity = 0 }
            }
        case .flash:
            flashOpacity = 0
            withAnimation(.easeIn(duration: 0.05)) { flashOpacity = 0.85 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.2)) { flashOpacity = 0 }
            }
        case .crossfade, .zoomPunch, .diagonalWipe:
            flashOpacity = 0
        }
    }
}

// MARK: - 写真を切らない斜めの光

private struct DiagonalLightSweep: View {
    @State private var offset: CGFloat = -1.4

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.white.opacity(0.42))
                .frame(width: max(90, geo.size.width * 0.18), height: geo.size.height * 1.8)
                .blur(radius: 16)
                .rotationEffect(.degrees(24))
                .offset(x: offset * geo.size.width)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) { offset = 1.4 }
        }
    }
}

/// 主写真・動画には一切マスクを掛けず、周囲だけで世界観を作る装飾。
/// 表示順から決まる3段階のため、ランダムではなく固定順で変化する。
struct PresentationDecorationOverlay: View {
    let pattern: PresentationPattern
    let variation: Int
    private var phase: Int { variation % 3 }

    var body: some View {
        if pattern != .classic {
            GeometryReader { geo in
                ZStack {
                    switch pattern {
                    case .weddingFilm: wedding(geo.size)
                    case .stadiumVision: stadium(geo.size)
                    case .retirementCeremony: retirement(geo.size)
                    case .blooperCredits: bloopers(geo.size)
                    case .classic: EmptyView()
                    }
                }.frame(width: geo.size.width, height: geo.size.height)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func wedding(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [.clear, Color(red: 0.93, green: 0.77, blue: 0.47).opacity(0.24), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 26).stroke(LinearGradient(colors: [.white.opacity(0.95), Color(red: 0.88, green: 0.66, blue: 0.27), .white.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: phase == 1 ? 7 : 4).padding(phase == 2 ? 18 : 28)
            Image(systemName: "sparkle").font(.system(size: 20)).foregroundStyle(.white.opacity(0.85)).position(x: 30, y: 55)
            Image(systemName: "sparkle").font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).position(x: size.width - 28, y: 70)
            if phase != 1 { HStack(spacing: 8) { capsule; capsule; capsule }.frame(width: 120).position(x: size.width / 2, y: 25) }
        }
    }

    private func stadium(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.15), Color(red: 0.02, green: 0.14, blue: 0.28).opacity(0.55), .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
            ledStrip.frame(height: phase == 1 ? 12 : 8).position(x: size.width / 2, y: 15)
            ledStrip.frame(height: phase == 1 ? 12 : 8).position(x: size.width / 2, y: size.height - 15)
            RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.9), lineWidth: phase == 2 ? 5 : 3).shadow(color: .cyan.opacity(0.8), radius: 8).padding(phase == 0 ? 20 : 30)
            HStack { score("LIVE"); Spacer(); score(phase == 2 ? "REPLAY" : "MOMENT") }.padding(.horizontal, 28).frame(width: size.width).position(x: size.width / 2, y: 31)
        }
    }

    private func retirement(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.01, green: 0.04, blue: 0.12).opacity(0.5), .clear, Color(red: 0.01, green: 0.04, blue: 0.12).opacity(0.5)], startPoint: .top, endPoint: .bottom)
            spotlight(-28).position(x: size.width * 0.18, y: size.height * 0.08)
            spotlight(28).position(x: size.width * 0.82, y: size.height * 0.08)
            RoundedRectangle(cornerRadius: 8).stroke(LinearGradient(colors: [.gray, Color(red: 0.8, green: 0.63, blue: 0.28), .gray], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: phase == 0 ? 4 : 7).padding(phase == 1 ? 26 : 18)
            Text(phase == 2 ? "A MOMENT TO REMEMBER" : "THANK YOU").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.9)).position(x: size.width / 2, y: 24)
        }
    }

    private func bloopers(_ size: CGSize) -> some View {
        ZStack {
            Color(red: 0.98, green: 0.68, blue: 0.21).opacity(0.12)
            RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.88), lineWidth: phase == 1 ? 15 : 11).padding(phase == 2 ? 14 : 22)
            filmHoles.position(x: size.width / 2, y: 15)
            filmHoles.position(x: size.width / 2, y: size.height - 15)
            Text(phase == 0 ? "TAKE TWO" : "OUTTAKE").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 7).background(.black.opacity(0.65), in: Capsule()).position(x: size.width / 2, y: 25)
            confetti(.pink, x: 20, y: 95); confetti(.cyan, x: size.width - 25, y: size.height - 100)
        }
    }

    private var capsule: some View { Capsule().fill(.white.opacity(0.8)).frame(height: 3) }
    private var ledStrip: some View { HStack(spacing: 4) { ForEach(0..<38, id: \.self) { _ in Circle().fill(.cyan.opacity(0.9)).frame(width: 3, height: 3) } } }
    private var filmHoles: some View { HStack(spacing: 8) { ForEach(0..<14, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(.black).frame(width: 11, height: 5) } } }
    private func score(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(.cyan).padding(.horizontal, 8).padding(.vertical, 5).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 3)).overlay(RoundedRectangle(cornerRadius: 3).stroke(.cyan.opacity(0.7), lineWidth: 1)) }
    private func spotlight(_ angle: Double) -> some View { Rectangle().fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)).frame(width: 80, height: 380).rotationEffect(.degrees(angle)).blur(radius: 5) }
    private func confetti(_ color: Color, x: CGFloat, y: CGFloat) -> some View { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 18).rotationEffect(.degrees(phase == 1 ? 32 : -24)).position(x: x, y: y) }
}
