import Foundation

/// 1枚(1本)あたりの表示時間の設定。MVPでは固定値だったが、CEO要望(2026-09-04)により
/// ユーザーが設定画面から変更できるようにする。
/// UserDefaults に JSON で保存し、次回起動時も同じ設定を復元する(外部へは送信しない)。
struct PlaybackSettings: Codable, Equatable {
    /// 写真1枚あたりの表示秒数。
    /// 既定値は元の固定値(4秒)を維持。
    var photoSlideDurationSeconds: Double = 4.0

    /// 動画の再生時間の扱い。既定値は元の挙動(20秒で打ち切り)を維持するため `.capped`。
    var videoPlaybackMode: VideoPlaybackMode = .capped

    /// videoPlaybackMode が `.capped` の時、何秒で次に切り替えるか。
    /// 既定値は元の固定値(20秒)を維持。
    var videoCapSeconds: Double = 20.0

    /// 動画の音と、他アプリ(音楽アプリ等)の音との関係。CEO要望(2026-09-05)により追加。
    /// 「自分の音楽を再生しながらタイマーを使う」という使い方を想定し、既定は
    /// 「音楽を小さくして動画の音を上に乗せる(ダッキング)」にしている。詳細は
    /// VideoAudioMixMode のコメント・TimerController.activateAudioSessionIfNeeded参照。
    var videoAudioMixMode: VideoAudioMixMode = .duckOthers

    /// 演出パターン(結婚式ムービー風・スタジアムビジョン風 等)。CEO要望(2026-09-05)により追加。
    /// 既定値の `.classic` は、これまで通り「1枚ずつ・フェードで切り替え」の見せ方(変更なし)。
    /// 【2026-09-05 CEO決定:演出パターンを選ぶと表示秒数の設定が無効になる】
    /// `.classic` 以外を選んだ場合、`photoSlideDurationSeconds`・`videoPlaybackMode`・
    /// `videoCapSeconds` はもう使われない(パターン自身が「間」ごとの秒数を決めるため。
    /// TimerController.PresentationBeat参照)。UI側(PlaybackSettingsView)は `.classic` 以外を
    /// 選んだ時、この2項目の設定行を隠す(混乱を避けるため)。
    var presentationPattern: PresentationPattern = .classic

    static let `default` = PlaybackSettings()

    init() {}

    /// 【2026-09-05追加:項目を増やしても既存の保存データを壊さないためのカスタムデコード】
    /// Swiftの自動生成Decodableは「構造体に無いキーがJSON側にあれば無視する」が、
    /// 逆に「構造体にあるプロパティのキーがJSON側に無い」場合は、そのプロパティに
    /// デフォルト値が指定されていてもデコード全体が失敗する(デフォルト値は自動では使われない)。
    /// そのため、この項目(videoAudioMixMode)を追加する前に保存されていた設定ファイルには
    /// このキー自体が存在せず、何もしなければ自動生成のデコードに任せた場合、
    /// 読み込み全体が失敗して「写真1枚あたりの表示秒数」等、他の項目まで一緒に既定値へ
    /// 巻き戻ってしまう(PlaybackSettingsStore.load()がtry?で失敗を握りつぶし.defaultへ
    /// フォールバックするため、CEOが設定していた値が黙って消える)。
    /// `decodeIfPresent` で「無ければデフォルト値」という自前の初期化にすることで、
    /// 古い保存データでも新しい項目だけが既定値、他の項目はそのまま復元されるようにする。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        photoSlideDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .photoSlideDurationSeconds) ?? 4.0
        videoPlaybackMode = try container.decodeIfPresent(VideoPlaybackMode.self, forKey: .videoPlaybackMode) ?? .capped
        videoCapSeconds = try container.decodeIfPresent(Double.self, forKey: .videoCapSeconds) ?? 20.0
        videoAudioMixMode = try container.decodeIfPresent(VideoAudioMixMode.self, forKey: .videoAudioMixMode) ?? .duckOthers
        presentationPattern = try container.decodeIfPresent(PresentationPattern.self, forKey: .presentationPattern) ?? .classic
    }
}

/// 動画の音と他アプリの音楽との関係。CEO要望(2026-09-05)。
///
/// 【前提】以前は動画再生時に音声セッションのカテゴリ(`.playback`、オプション無し)を
/// 素で有効化していたため、他アプリ(音楽アプリ等)の再生が動画のたびに強制的に止まっていた。
/// CEOは「自分の音楽を流しながらタイマーを使う」想定で、「理想は両方流れること」と考えている。
///
/// 【アラームへの影響について】この設定は**動画再生時の音声セッション**
/// (TimerController.activateAudioSessionIfNeeded)にのみ影響する。アラーム(タイマー終了音)は
/// これとは別の場所(TimerController.playAlarm)で常に `.duckOthers` を使っており、この3択の
/// どれを選んでも変えない(マナーモードでも鳴る現在の挙動を壊さないため。CEO実機確認済み)。
enum VideoAudioMixMode: String, Codable, Hashable, CaseIterable {
    /// 両方そのまま鳴らす。音量調整はしない(AVAudioSessionの `.mixWithOthers` オプション)。
    case mixWithOthers
    /// 音楽を小さくして動画の音を上に乗せる(AVAudioSessionの `.duckOthers` オプション)。既定。
    case duckOthers
    /// 他アプリの音楽が鳴っている間は動画の音を出さない(自動判定。動画の再生を始める瞬間に
    /// `AVAudioSession.isOtherAudioPlaying` を見て、鳴っていれば音声セッションを確保せず
    /// 動画自体をミュートする。鳴っていなければ通常どおり音を出す)。
    case muteWhenOtherAudioPlaying
}

/// 動画の再生時間の扱い。
enum VideoPlaybackMode: String, Codable, Hashable, CaseIterable {
    /// 動画を最後まで再生する(タイマーの残り時間より長い動画は、残り時間を超えて再生され続けることがある)。
    case full
    /// 指定した秒数(videoCapSeconds)に達したら、動画の途中でも次に切り替える。
    case capped
}

// MARK: - 選べる値の一覧
//
// 「一瞬だけ映るのも面白い」というCEOの意向(2026-09-04)があるため、写真の表示秒数は
// 1秒未満(0.5秒)まで選べるようにしている。フリー入力ではなく固定リストにしているのは、
// 他の設定項目(絞り込み条件)と同じ考え方(選択肢が多すぎると逆に選びにくくなるため)。
enum PlaybackSettingsChoices {
    /// 写真1枚あたりの表示秒数として選べる値。
    static let photoDurations: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 7, 8, 10, 12, 15, 20, 30]

    /// 動画を「秒数で切り上げる」時に選べる秒数。
    static let videoCapDurations: [Double] = [3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
}

// MARK: - 永続化
enum PlaybackSettingsStore {
    private static let key = "PhotoTimer.PlaybackSettings.v1"

    static func load() -> PlaybackSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(PlaybackSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: PlaybackSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
