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
            return .diagonalWipe
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

// MARK: - 斜めのワイプ(スタジアムビジョン風)

private struct DiagonalWipeModifier: ViewModifier, Animatable {
    /// 0 = 完全に隠れている、1 = 完全に見えている。
    var progress: CGFloat

    func body(content: Content) -> some View {
        content.mask(
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let shift = w * (1 - progress) * 1.4
                Path { path in
                    path.move(to: CGPoint(x: -shift - h * 0.6, y: 0))
                    path.addLine(to: CGPoint(x: w - shift, y: 0))
                    path.addLine(to: CGPoint(x: w - shift - h * 0.6, y: h))
                    path.addLine(to: CGPoint(x: -shift, y: h))
                    path.closeSubpath()
                }
                .fill(Color.white)
            }
        )
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
}

extension AnyTransition {
    /// 斜めの帯が画面を横切りながら切り替わる「ワイプ」演出。
    fileprivate static var diagonalWipe: AnyTransition {
        .modifier(
            active: DiagonalWipeModifier(progress: 0),
            identity: DiagonalWipeModifier(progress: 1)
        )
    }
}
