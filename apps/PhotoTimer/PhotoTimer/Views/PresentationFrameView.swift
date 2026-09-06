import SwiftUI

/// 演出パターン(結婚式ムービー風・スタジアムビジョン風)の「間」を実際に描画するビュー。
/// 動画は対象外(TimerController側が常にこれまで通りのフルスクリーン再生に振り分ける)。
struct PresentationFrameView: View {
    let frame: PresentationFrame

    /// 【2026-09-06 バグA追加調査で判明した根本原因への対応】以前は`.transition()`+`.id()`で
    /// 新旧の「間」を差し替え、それを`.animation(value:)`でアニメーションさせていた。しかし
    /// フルスクリーン・コラージュの中身はGeometryReaderでサイズを決めており、
    /// GeometryReaderを含むViewの「挿入・削除」自体をアニメーション対象にすると、SwiftUIが
    /// 差し替わりの瞬間にレイアウトの再計算をアニメーションの一部として扱ってしまい、
    /// 一時的に不正確な(画面の一部にしか満たない)サイズを返すことがあると実機・シミュレータ
    /// 双方で確認できた(結果として「フレームが見切れる」「前後の間が重なって見える」)。
    /// これを避けるため、ここでは新旧の「間」を**both**を確定した完成サイズでマウントしたままにし
    /// (=GeometryReaderのレイアウト計算はアニメーションの外で先に確定させ)、消えていく側の
    /// 不透明度「だけ」をアニメーションさせる手動クロスフェードに変更した。
    @State private var displayedFrame: PresentationFrame?
    @State private var outgoingFrame: PresentationFrame?
    @State private var outgoingOpacity: Double = 0
    /// zoomPunch切り替わり(PresentationTransition.zoomPunch)用。新しい「間」が迫ってくるように
    /// 小さい状態から等倍まで戻す(1.0を超えないため主素材が画面外に出て欠けることは無い)。
    @State private var incomingScale: CGFloat = 1.0

    /// フルスクリーンのゆっくりズーム(Ken Burns)・勢いよく迫る登場(zoomPunch)は、
    /// 見た目上は「拡大率が時間とともに変わる」連続的なアニメーションなので、切り替わりの
    /// transition(挿入・削除の演出)とは別に、ここで状態として持って withAnimation で動かす。
    @State private var fullScreenScaleSettled = false
    /// ホワイトアウト・フラッシュの一瞬の白い光。0=見えない、1=真っ白。
    @State private var flashOpacity: Double = 0

    var body: some View {
        ZStack {
            if let displayedFrame {
                contentView(for: displayedFrame)
                    .scaleEffect(incomingScale)
            }
            if let outgoingFrame {
                contentView(for: outgoingFrame)
                    .opacity(outgoingOpacity)
            }
        }
        // 【追加調査・2026-09-06】この.frameが無いと、ZStackが周囲の兄弟View
        // (topBarを含むVStack等)の理想サイズに引きずられ、画面の一部にしか
        // 広がらないことが実機・シミュレータの両方で確認できた。明示的に
        // 「取れる限り大きく」と指定することで、常に画面いっぱいに広がるようにする。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            displayedFrame = frame
            startFullScreenAnimationIfNeeded()
            triggerFlashIfNeeded()
        }
        .onChange(of: frame.id) { _, _ in
            advanceToNewFrame()
        }
    }

    /// 新しい「間」への切り替え本体(手動クロスフェード)。上のコメント参照。
    private func advanceToNewFrame() {
        // 直前まで表示していたものを「消えていく側」に回し、そのまま完成した状態で残す
        // (この時点ではまだアニメーションを掛けていないので、GeometryReaderは通常通り
        // 一度だけ正しいサイズを計算する)。
        outgoingFrame = displayedFrame
        outgoingOpacity = 1
        // 新しい「間」を、最初から完成したレイアウトで即座にマウントする。
        displayedFrame = frame
        fullScreenScaleSettled = false
        incomingScale = (frame.transition == .zoomPunch) ? 0.72 : 1.0

        // ここから先、動かすのは不透明度・拡大率という「見た目の効果」だけ。
        // GeometryReaderによるレイアウト計算はこのwithAnimationの外で既に確定しているため、
        // アニメーション中に再計算されて崩れることが無い。
        withAnimation(.easeInOut(duration: 0.4)) {
            outgoingOpacity = 0
            incomingScale = 1.0
        }
        startFullScreenAnimationIfNeeded()
        triggerFlashIfNeeded()
    }

    @ViewBuilder
    private func contentView(for frame: PresentationFrame) -> some View {
        switch frame.layout {
        case .fullScreen(let image, let assetID, let style):
            // 【バグA修正・2026-09-06】以前はここにGeometryReaderが無く、明示的なサイズ指定も
            // 無かったため、コラージュ(GeometryReaderでサイズを与えている)と違って画面全体に
            // 広がらず、画面の一部にしか表示されないことがあった(CEO実機フィードバック
            // 「フレームが見切れてる」の直接原因)。コラージュと同じ考え方で、GeometryReaderが
            // 計測したサイズを明示的に.frame()で与えることで、常に画面いっぱいに表示させる。
            GeometryReader { geo in
                ZStack {
                    // 写真の内容を推測して切り抜くことはしない。縦横を問わず主画像の全体を表示し、
                    // 余白は暗い背景で受ける。背景だけはぼかして画面の一体感を作る。
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 24)
                        .opacity(0.28)
                        .scaleEffect(1.12)
                        .clipped()
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .padding(10)
                        .scaleEffect(scale(for: style))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color.black)
            }
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
                // 【2026-09-06 明示化】以前は小さい2枚の高さをnil(VStackにお任せ)にしていたが、
                // GeometryReaderと組み合わさった時に高さが確定しない瞬間があることが分かったため、
                // 幅・高さとも必ず具体的な数値を渡すようにした(あいまいさを残さない)。
                let smallHeight = (geo.size.height - 3) / 2
                HStack(spacing: 3) {
                    tile(main.image, width: geo.size.width * 0.66, height: geo.size.height)
                    VStack(spacing: 3) {
                        ForEach(Array(secondaries.prefix(2).enumerated()), id: \.offset) { _, item in
                            tile(item.image, width: geo.size.width * 0.34 - 3, height: smallHeight)
                        }
                        // 追加候補が1枚しか無かった場合、余白を埋めて崩れないようにする。
                        if secondaries.count < 2 {
                            Color.black.frame(width: geo.size.width * 0.34 - 3, height: smallHeight)
                        }
                    }
                    .frame(width: geo.size.width * 0.34, height: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
        case .mosaicThree:
            GeometryReader { geo in
                let smallWidth = (geo.size.width - 3) / 2
                let smallHeight = geo.size.height * 0.4 - 3
                VStack(spacing: 3) {
                    tile(main.image, width: geo.size.width, height: geo.size.height * 0.6)
                    HStack(spacing: 3) {
                        ForEach(Array(secondaries.prefix(2).enumerated()), id: \.offset) { _, item in
                            tile(item.image, width: smallWidth, height: smallHeight)
                        }
                        if secondaries.count < 2 {
                            Color.black.frame(width: smallWidth, height: smallHeight)
                        }
                    }
                    .frame(width: geo.size.width, height: smallHeight)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
        }
    }

    /// コラージュの1マス。幅・高さは必ず具体的な数値で受け取る(あいまいさを残さない。
    /// 2026-09-06の調査で、GeometryReaderと組み合わせた時に高さ未指定〔nil〕だと
    /// 確定しない瞬間があると分かったため)。
    ///
    /// 【2026-09-06 見た目の改善】写真の縦横比がマスの形(正方形に近い)と合わない場合、
    /// これまでは黒一色の余白(実質ほぼ見えない`Color.black.opacity(0.82)`)が大きく残り、
    /// 「写真がマスの中で小さく浮いて見える」原因になっていた(フルスクリーン表示は
    /// ぼかした同じ写真を敷いて余白を埋めているのに、コラージュのマスだけそれが無かった)。
    /// フルスクリーンと同じ考え方で、ぼかして暗くした同じ写真を下敷きにすることで、
    /// マスいっぱいに写真の気配で満たす(主画像を切り抜く・欠けさせることはしない)。
    @ViewBuilder
    private func tile(_ image: UIImage, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .blur(radius: 14)
                .opacity(0.35)
                .clipped()
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .background(Color.black)
    }

    // MARK: - 切り替わりの見せ方(transition)
    //
    // 【2026-09-06 手動クロスフェードへの変更に伴う整理】以前はここでSwiftUIの`AnyTransition`
    // (`.transition()`+`.id()`)を組み立てていたが、GeometryReaderとの組み合わせでレイアウトが
    // 一時的に崩れる不具合が判明したため、advanceToNewFrame()での手動クロスフェード+
    // incomingScaleによる手動scale処理に置き換えた。crossfade/whiteout/flash/diagonalWipeは
    // いずれも「消えていく側の不透明度を下げる」という同じ手動クロスフェードで表現でき、
    // whiteout/flashは別途flashOpacityの白い光、diagonalWipeは別途DiagonalLightSweepの光の帯で
    // 差別化している(triggerFlashIfNeeded参照)。zoomPunchだけが追加でincomingScaleを使う。

    // MARK: - フルスクリーンの連続アニメーション(Ken Burns / zoomPunch)

    /// 【バグB修正・2026-09-06】以前はkenBurns・zoomPunchどちらも常に1.0を返しており、
    /// スタイル名と実際の動きが一致していなかった(結果として全パターンが同じ静止表示に
    /// 見えていた)。ここでは「1.0を超えて拡大しない」(=写真の内容が画面外に押し出されず、
    /// 欠けることが無い)という制約を守ったまま、開始値だけをスタイルごとに変える。
    /// fullScreenScaleSettledがfalse→trueに変わる過程をwithAnimationで包むことで実際に動く。
    private func scale(for style: PresentationFrame.FullScreenStyle) -> CGFloat {
        switch style {
        case .kenBurns:
            // ゆっくりと呼吸するような微差のズーム(0.98→1.0)。動き自体は控えめだが、
            // ずっと止め絵ではないことが伝わる程度の変化に留める(上品さを崩さないため)。
            return fullScreenScaleSettled ? 1.0 : 0.98
        case .zoomPunch:
            // 小さい状態(0.7)から等倍(1.0)まで勢いよく迫ってくる。1.0を超えないため、
            // 写真の内容が画面外に出て欠けることは無い。
            return fullScreenScaleSettled ? 1.0 : 0.7
        }
    }

    private func startFullScreenAnimationIfNeeded() {
        guard case .fullScreen(_, _, let style) = frame.layout else { return }
        switch style {
        case .kenBurns:
            // 表示秒数いっぱいを使ってゆっくり変化させる(直線的な動きで「呼吸」のように見せる)。
            withAnimation(.linear(duration: max(0.5, frame.duration))) { fullScreenScaleSettled = true }
        case .zoomPunch:
            // 短時間でバネのように迫ってくる、勢いのある動き。
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
/// 表示順から決まる3段階(phase)で構図が変わることに加え、常時ゆっくり動き続ける
/// アニメーション(呼吸するような光・降り注ぐ粒子等)を持たせている。
///
/// 【2026-09-06 作り込み強化】CEO実機フィードバック「全部フレーム一緒の使い回し感」対応。
/// 以前は4パターンとも「角丸の枠線(RoundedRectangle.stroke)+中央上のバッジ」という
/// 同じ骨格を色だけ変えて使い回しており、色以外の構造がほぼ同じだった。今回、パターンごとに
/// 骨格そのものを変えた:結婚式=枠線を廃止し四隅の装飾+ゆっくり明滅する光、
/// スタジアム=四辺を囲む太いLED帯+ビューファインダー風の角ブラケット+高速に流れる光、
/// 引退セレモニー=枠線を使わず中央から降り注ぐ1本のスポットライト+ゆっくり落ちる光の粒、
/// NG集=四辺すべてのフィルム穴(縦横とも)+斜めに傾いたスタンプ+舞い散る紙吹雪。
struct PresentationDecorationOverlay: View {
    let pattern: PresentationPattern
    let variation: Int
    private var phase: Int { variation % 3 }
    /// 常時ループするアニメーションの起点(0→1を繰り返す)。パターンごとに使い方を変える。
    @State private var pulse = false

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false).accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }

    // MARK: - 結婚式ムービー風:枠線を使わず、四隅の装飾+ゆっくり明滅する柔らかい光

    private func wedding(_ size: CGSize) -> some View {
        ZStack {
            // 中央から柔らかく広がる光が、ゆっくり明滅する(呼吸するような動き)。
            RadialGradient(colors: [Color(red: 0.97, green: 0.85, blue: 0.6).opacity(pulse ? 0.30 : 0.14), .clear], center: .center, startRadius: 10, endRadius: size.width * 0.75)
            // 四隅だけの優雅な弧(枠で囲まない=結婚式らしい軽やかさ)。
            weddingCorner().position(x: 26, y: 26)
            weddingCorner().rotationEffect(.degrees(90)).position(x: size.width - 26, y: 26)
            weddingCorner().rotationEffect(.degrees(-90)).position(x: 26, y: size.height - 26)
            weddingCorner().rotationEffect(.degrees(180)).position(x: size.width - 26, y: size.height - 26)
            // ゆっくり上へ漂う光の粒(結婚式のシャンパンの泡のようなイメージ)。
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: [20, 13, 16][i]))
                    .foregroundStyle(.white.opacity(0.85))
                    .position(x: [30, size.width - 28, size.width * 0.5][i], y: pulse ? [40, 55, 30][i] : [70, 90, 60][i])
            }
            if phase != 1 {
                HStack(spacing: 8) { pearl; pearl; pearl }.frame(width: 120).position(x: size.width / 2, y: 24)
            }
        }
    }

    private func weddingCorner() -> some View {
        // アーチ状の弧1本だけの、控えめな金の飾り(四角い枠ではなく「角の飾り」であることが分かる形)。
        Path { path in
            path.addArc(center: .zero, radius: 22, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        .stroke(LinearGradient(colors: [Color(red: 0.88, green: 0.66, blue: 0.27), .white.opacity(0.9)], startPoint: .leading, endPoint: .trailing), lineWidth: phase == 1 ? 4 : 2.5)
        .frame(width: 44, height: 44)
    }

    private var pearl: some View { Circle().fill(.white.opacity(0.85)).frame(width: 5, height: 5) }

    // MARK: - スタジアムビジョン風:四辺を囲む太いLED帯+角ブラケット+高速に流れる光

    private func stadium(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.18), Color(red: 0.02, green: 0.14, blue: 0.28).opacity(0.5), .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
            // 四辺すべてを囲むLED(結婚式=飾らない/引退=1本の光、と違い、ジャンボトロンの縁全体が光る)。
            ledStrip(count: 40).frame(height: 9).position(x: size.width / 2, y: 13)
            ledStrip(count: 40).frame(height: 9).position(x: size.width / 2, y: size.height - 13)
            ledStrip(count: 14).frame(width: 9).position(x: 13, y: size.height / 2)
            ledStrip(count: 14).frame(width: 9).position(x: size.width - 13, y: size.height / 2)
            // カメラのビューファインダーのような、鋭い角ブラケット(丸い枠線ではなく直角の切れ込み)。
            viewfinderCorners(size)
            // 縁に沿って高速に流れる光(結婚式のゆったりした明滅とは対照的な、素早い動き)。
            Rectangle().fill(Color.cyan.opacity(0.9)).frame(width: 46, height: 9).blur(radius: 3)
                .position(x: pulse ? size.width - 30 : 30, y: 13)
            HStack { score("LIVE"); Spacer(); score(phase == 2 ? "REPLAY" : "MOMENT") }.padding(.horizontal, 30).frame(width: size.width).position(x: size.width / 2, y: 34)
        }
    }

    private func viewfinderCorners(_ size: CGSize) -> some View {
        let len: CGFloat = 26
        let inset: CGFloat = phase == 2 ? 34 : 24
        func bracket(_ corner: UnitPoint) -> some View {
            Path { path in
                path.move(to: CGPoint(x: 0, y: len)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: len, y: 0))
            }
            .stroke(Color.cyan, lineWidth: 4)
            .shadow(color: .cyan.opacity(0.8), radius: 6)
            .frame(width: len, height: len)
        }
        return ZStack {
            bracket(.topLeading).position(x: inset, y: inset)
            bracket(.topTrailing).rotationEffect(.degrees(90)).position(x: size.width - inset, y: inset)
            bracket(.bottomTrailing).rotationEffect(.degrees(180)).position(x: size.width - inset, y: size.height - inset)
            bracket(.bottomLeading).rotationEffect(.degrees(-90)).position(x: inset, y: size.height - inset)
        }
    }

    // MARK: - 引退セレモニー風:枠線を使わず、中央から降り注ぐ1本のスポットライト+落ちる光の粒

    private func retirement(_ size: CGSize) -> some View {
        ZStack {
            // 四隅を暗く落とす重めのビネット(結婚式・スタジアムより暗く、厳かな雰囲気)。
            RadialGradient(colors: [.clear, Color.black.opacity(0.55)], center: .center, startRadius: size.width * 0.35, endRadius: size.width * 0.85)
            // 中央上から1本だけ、ゆっくり左右に揺れるスポットライト(枠で囲まない引退セレモニー特有の演出)。
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 110, height: size.height * 0.9)
                .rotationEffect(.degrees(pulse ? 6 : -6), anchor: .top)
                .position(x: size.width / 2, y: 0)
                .blur(radius: 6)
            // ゆっくり降り積もる光の粒(結婚式の「昇る泡」とは逆に、静かに降りてくる)。
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Color(red: 0.85, green: 0.72, blue: 0.4).opacity(0.8)).frame(width: 4, height: 4)
                    .position(x: size.width * [0.2, 0.42, 0.66, 0.85][i], y: pulse ? size.height * 0.75 : size.height * 0.15)
            }
            VStack(spacing: 4) {
                Text(phase == 2 ? "A MOMENT TO REMEMBER" : "THANK YOU")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                Capsule().fill(Color(red: 0.8, green: 0.63, blue: 0.28)).frame(width: phase == 1 ? 70 : 46, height: 2)
            }
            .position(x: size.width / 2, y: 30)
        }
    }

    // MARK: - NG集エンドロール風:四辺すべてのフィルム穴+斜めのスタンプ+舞い散る紙吹雪

    private func bloopers(_ size: CGSize) -> some View {
        ZStack {
            Color(red: 0.98, green: 0.68, blue: 0.21).opacity(0.10)
            // フィルムの縁(結婚式・スタジアム・引退のどれとも違う、上下左右すべてに穴が並ぶ「フィルムに
            // 囲まれている」感覚。他パターンは上下だけ、または枠を使わないため、ここだけの特徴になる)。
            filmHoles(count: 16, horizontal: true).position(x: size.width / 2, y: 14)
            filmHoles(count: 16, horizontal: true).position(x: size.width / 2, y: size.height - 14)
            filmHoles(count: 8, horizontal: false).position(x: 14, y: size.height / 2)
            filmHoles(count: 8, horizontal: false).position(x: size.width - 14, y: size.height / 2)
            // 斜めに傾いたゴム印風スタンプ。わずかに揺れ続ける、他パターに無いコミカルな動き。
            Text(phase == 0 ? "TAKE TWO" : "OUTTAKE")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.85), lineWidth: 3))
                .rotationEffect(.degrees(pulse ? -16 : -22))
                .position(x: size.width * 0.72, y: size.height * 0.22)
            // 舞い散る紙吹雪。上から降ってくる動きにする(スタジアムの水平な流れ光と対照的)。
            ForEach(0..<4, id: \.self) { i in
                confetti([.pink, .cyan, .yellow, .mint][i], x: size.width * [0.12, 0.85, 0.3, 0.68][i])
            }
        }
    }

    private func confetti(_ color: Color, x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 16)
            .rotationEffect(.degrees(pulse ? 200 : 20))
            .position(x: x, y: pulse ? 130 : 40)
    }

    // MARK: - 共通の小部品(見た目は個別の関数側で大きく変えているため、ここは形の土台のみ)

    private func ledStrip(count: Int) -> some View {
        HStack(spacing: 4) { ForEach(0..<count, id: \.self) { _ in Circle().fill(.cyan.opacity(0.9)).frame(width: 3, height: 3) } }
    }
    private func filmHoles(count: Int, horizontal: Bool) -> some View {
        Group {
            if horizontal {
                HStack(spacing: 8) { ForEach(0..<count, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(.black).frame(width: 11, height: 5) } }
            } else {
                VStack(spacing: 8) { ForEach(0..<count, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(.black).frame(width: 5, height: 11) } }
            }
        }
    }
    private func score(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(.cyan)
            .padding(.horizontal, 8).padding(.vertical, 5).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.cyan.opacity(0.7), lineWidth: 1))
    }
}
