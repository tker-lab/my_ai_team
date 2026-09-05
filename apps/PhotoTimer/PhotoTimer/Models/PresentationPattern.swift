import UIKit

/// タイマー実行中の写真・動画の「見せ方」のパターン。CEO要望(2026-09-05)。
///
/// 【設計方針】`.classic`(これまで通り、1枚ずつフェードで切り替え)を既定値にすることで、
/// 演出パターンを選ばないすべてのユーザー・すべての既存の自動テストの挙動を一切変えない。
/// `.weddingFilm`・`.stadiumVision` の2つが今回app-team担当分。将来Codex側が担当する2パターンも、
/// この enum にケースを追加し `beats` に並びを定義するだけで組み込めるようにしてある。
enum PresentationPattern: String, Codable, CaseIterable, Identifiable, Hashable {
    case classic
    case weddingFilm
    case stadiumVision

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "シンプル"
        case .weddingFilm: return "結婚式ムービー風"
        case .stadiumVision: return "スタジアムビジョン風"
        }
    }

    /// 設定画面に出す説明文。判定の内部事情(専用検出・高精度等)には触れず、実際に起きることだけを書く。
    var summary: String {
        switch self {
        case .classic:
            return "写真・動画を1枚ずつ、これまで通りフェードで切り替えます。"
        case .weddingFilm:
            return "上品でやわらかい雰囲気。フルスクリーンの1枚と、複数枚を組み合わせた見せ方を、ゆっくりとした動きで交互に切り替えます。"
        case .stadiumVision:
            return "力強くダイナミックな雰囲気。勢いよく迫る登場や、複数枚を同時に見せる演出を取り入れます。"
        }
    }

    /// この「間(ま)」の並び(=見せ方の順番)が演出パターンの実体。
    ///
    /// 【2026-09-05 CEO決定:ランダムではなく固定の順番で繰り返す】
    /// 一巡したら最初に戻る、決定的な並び順にする。理由:ランダムだと同じ出し方が連続したり
    /// 偏ったりするため、順番を決めて繰り返す方が「狙った演出」に近づく、というCEO判断。
    /// (CEOが説明用に挙げた具体的な並び順の例はそのまま採用していない。ここでの並び・秒数・
    /// 組み合わせは実装側の判断による、パターンごとに独自のもの)
    ///
    /// 隣り合う「間」同士(最後→最初の巡回も含む)は、見せ方(layout)・切り替わり方(transition)の
    /// 少なくとも一方が必ず変わるように並べてある。「同じフレーム・同じ見せ方がずっと続くのは禁止」
    /// という共通要件を満たすため。
    var beats: [PresentationBeat] {
        switch self {
        case .classic:
            return []
        case .weddingFilm:
            return [
                PresentationBeat(duration: 4.5, content: .photoFullScreen(.kenBurns), transition: .crossfade),
                PresentationBeat(duration: 5.5, content: .photoCollage(secondaryCount: 2, arrangement: .bigWithTwoSmall), transition: .whiteout),
                PresentationBeat(duration: 4.0, content: .photoFullScreen(.kenBurns), transition: .crossfade),
                PresentationBeat(duration: 6.0, content: .video, transition: .whiteout),
                PresentationBeat(duration: 5.0, content: .photoCollage(secondaryCount: 2, arrangement: .bigWithTwoSmall), transition: .crossfade),
                PresentationBeat(duration: 4.0, content: .photoFullScreen(.kenBurns), transition: .whiteout),
            ]
        case .stadiumVision:
            return [
                PresentationBeat(duration: 2.2, content: .photoFullScreen(.zoomPunch), transition: .zoomPunch),
                PresentationBeat(duration: 3.0, content: .photoCollage(secondaryCount: 2, arrangement: .mosaicThree), transition: .diagonalWipe),
                PresentationBeat(duration: 2.0, content: .photoFullScreen(.zoomPunch), transition: .flash),
                PresentationBeat(duration: 5.0, content: .video, transition: .zoomPunch),
                PresentationBeat(duration: 3.0, content: .photoCollage(secondaryCount: 2, arrangement: .mosaicThree), transition: .diagonalWipe),
                PresentationBeat(duration: 2.0, content: .photoFullScreen(.zoomPunch), transition: .flash),
            ]
        }
    }
}

/// 演出パターンの中の「1コマ(間)」。何を(content)・何秒(duration)・どんな切り替わり方で
/// (transition)見せるかを表す固定データ。パターン自体はこれの配列(順番)を持つだけ。
struct PresentationBeat {
    let duration: Double
    let content: Content
    let transition: PresentationTransition

    enum Content {
        /// 動画をこれまで通りフルスクリーンで見せる「間」(音の3択設定はそのまま従う。
        /// TimerController.configureAudioForVideoPlayback参照)。
        case video
        /// 写真1枚をフルスクリーンで見せる。styleで「ゆっくりズーム」「勢いよく登場」を切り替える。
        case photoFullScreen(PresentationFrame.FullScreenStyle)
        /// 写真を複数枚組み合わせて見せる(結婚式=大1小2、スタジアム=モザイク3枚 等)。
        /// secondaryCountは主役級の1枚に加えて追加で何枚使うか。
        case photoCollage(secondaryCount: Int, arrangement: PresentationFrame.CollageArrangement)

        var isVideo: Bool {
            if case .video = self { return true }
            return false
        }
    }
}

/// 演出パターンが「今どんな見せ方をしているか」を画面(PresentationFrameView)に伝えるための値。
/// 写真の時だけ使う(動画は常にこれまで通りフルスクリーン単体表示。SlideshowViewはこの値がnilの時、
/// これまで通りcurrentImage/currentPlayerを描画する)。
struct PresentationFrame: Identifiable {
    /// 切り替わるたびに新しい値になる。この値の変化がSwiftUI側のアニメーション(transition)の
    /// トリガーになる(.id(frame.id)で使う)。
    let id = UUID()
    let layout: Layout
    let transition: PresentationTransition

    enum Layout {
        case fullScreen(image: UIImage, assetID: String, style: FullScreenStyle)
        case collage(main: (image: UIImage, assetID: String), secondaries: [(image: UIImage, assetID: String)], arrangement: CollageArrangement)
    }

    enum FullScreenStyle {
        /// ゆっくりとしたズーム(Ken Burns効果)。結婚式ムービー風で使う。
        case kenBurns
        /// 勢いよく迫ってくる登場。スタジアムビジョン風で使う。
        case zoomPunch
    }

    enum CollageArrangement {
        /// 大きい1枚 + 小さい2枚(結婚式ムービー風)。
        case bigWithTwoSmall
        /// 3枚を均等に近い配置で並べるモザイク(スタジアムビジョン風)。
        case mosaicThree
    }
}

/// 切り替わり自体の見せ方(複数用意し、「間」ごとに変える。共通要件)。
enum PresentationTransition {
    case crossfade
    case whiteout
    case zoomPunch
    case diagonalWipe
    case flash
}
