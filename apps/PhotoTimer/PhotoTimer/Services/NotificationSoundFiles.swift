import Foundation

/// バックグラウンド中に鳴らすローカル通知の「音」を、端末内の決まった場所に書き出しておく仕組み。
///
/// 【なぜ必要か】ローカル通知に独自の音を使うには、Appleの仕様上「アプリのLibrary/Soundsフォルダ」に
/// 音声ファイル(wav/aiff/caf、30秒以内)を置いておく必要がある。このアプリはアラーム音を
/// (外部素材を使わず)AlarmTone.swiftでその場で生成する設計だが、フォアグラウンドでの再生
/// (AVAudioPlayerにその場でDataを渡す)とは異なり、通知の音だけは「ファイルとして存在している」
/// 必要があるため、この仕組みで一度だけディスクに書き出しておく。
///
/// 【端末内で完結・外部送信なし】書き出す内容はAlarmTone.swift(このアプリ内で完結する音声合成)の
/// 出力そのものであり、外部から素材を取得したり、外部へ送信したりすることは一切ない。
enum NotificationSoundFiles {
    /// 書き出し先(アプリコンテナ内のLibrary/Sounds)。
    private static let directory: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let dir = library.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func fileName(for tone: AlarmTonePattern) -> String {
        switch tone {
        case .beep: return "alarm_beep.wav"
        case .bell: return "alarm_bell.wav"
        case .siren: return "alarm_siren.wav"
        }
    }

    /// 通知に渡す音のファイル名(Library/Sounds内のファイル名。UNNotificationSoundName相当)を返す。
    /// まだファイルが無ければこの場で書き出す(初回のみディスクI/Oが発生。以降は既存ファイルを使い回す)。
    /// 書き出しに失敗した場合は nil(呼び出し側はOS既定の通知音にフォールバックする)。
    static func soundName(for tone: AlarmTonePattern) -> String? {
        let name = fileName(for: tone)
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            return name
        }
        do {
            try AlarmTone.data(for: tone).write(to: url, options: .atomic)
            return name
        } catch {
            NSLog("[PhotoTimer] 通知音ファイルの書き出しに失敗しました: \(error)")
            return nil
        }
    }

    /// 音色を変更した時など、3種類まとめて事前に書き出しておきたい場合に呼ぶ(任意。呼ばなくても
    /// soundName(for:)が必要になった時点で個別に書き出されるため必須ではない)。
    static func prepareAll() {
        for tone in AlarmTonePattern.allCases {
            _ = soundName(for: tone)
        }
    }
}
