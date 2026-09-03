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

    static let `default` = PlaybackSettings()
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
