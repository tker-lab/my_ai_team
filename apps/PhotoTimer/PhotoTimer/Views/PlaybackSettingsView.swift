import SwiftUI

/// 「写真1枚あたりの表示秒数」「動画の再生時間の扱い」を設定する画面。
/// CEO要望(2026-09-04):これまで固定値だった2つの値をユーザーが変更できるようにする。
struct PlaybackSettingsView: View {
    @Binding var settings: PlaybackSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("表示秒数", selection: $settings.photoSlideDurationSeconds) {
                        ForEach(PlaybackSettingsChoices.photoDurations, id: \.self) { value in
                            Text(Self.label(for: value)).tag(value)
                        }
                    }
                    // 選択肢が多い(17個)ため、タップでメニューが開く方式にする。
                    .pickerStyle(.menu)
                    // 自動テスト(XCUITest)がこのピッカーを確実に見つけられるようにするための目印。
                    .accessibilityIdentifier("photoDurationPicker")
                } header: {
                    Text("写真1枚あたりの表示時間")
                } footer: {
                    Text("短くすると次々に切り替わり、一瞬だけ映る写真も楽しめます。長くするとじっくり見せられ、表示中に次の候補を探せる時間も増えます。")
                }

                Section {
                    Picker("動画の再生", selection: $settings.videoPlaybackMode) {
                        Text("最後まで再生する").tag(VideoPlaybackMode.full)
                        Text("指定秒数で切り上げる").tag(VideoPlaybackMode.capped)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("videoModePicker")

                    if settings.videoPlaybackMode == .capped {
                        Picker("切り上げる秒数", selection: $settings.videoCapSeconds) {
                            ForEach(PlaybackSettingsChoices.videoCapDurations, id: \.self) { value in
                                Text("\(Int(value))秒").tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("videoCapPicker")
                    }
                } header: {
                    Text("動画の再生時間")
                } footer: {
                    // 【説明文の修正】以前は「タイマーの残り時間を超えて再生され続けることがある」としていたが、
                    // 実際の実装ではタイマー終了時に動画を必ず止める(TimerController.finish())ため誤りだった。
                    // 実際の挙動(タイマーが終わったらそこで打ち切られる)に合わせて説明文を直した。
                    Text(settings.videoPlaybackMode == .full
                         ? "動画は最後まで再生されます。ただしタイマーの残り時間より動画が長い場合は、タイマー終了と同時にそこで打ち切られます。"
                         : "指定した秒数に達したら、動画の途中でも次の写真・動画に切り替えます。")
                }

                Section {
                    Picker("動画の音", selection: $settings.videoAudioMixMode) {
                        Text("両方そのまま鳴らす").tag(VideoAudioMixMode.mixWithOthers)
                        Text("音楽を小さくして重ねる").tag(VideoAudioMixMode.duckOthers)
                        Text("音楽が鳴っていたら動画は無音").tag(VideoAudioMixMode.muteWhenOtherAudioPlaying)
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("videoAudioMixModePicker")
                } header: {
                    Text("動画の音と他アプリの音楽")
                } footer: {
                    Text(videoAudioMixModeFooter)
                }
            }
            .navigationTitle("表示設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    /// "0.5秒" / "4秒" のような表記(整数はそのまま、それ以外は小数第1位まで)。
    private static func label(for value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))秒"
        }
        return String(format: "%.1f秒", value)
    }

    /// 選んでいる項目に応じた説明文。判定の内部事情には触れず、実際に起きることだけを書く。
    private var videoAudioMixModeFooter: String {
        switch settings.videoAudioMixMode {
        case .mixWithOthers:
            return "音楽アプリなどを流しながらタイマーを使うと、動画の音と両方がそのまま鳴ります。音量の調整はされません。"
        case .duckOthers:
            return "音楽アプリなどを流しながらタイマーを使うと、その音楽を少し小さくして、上に動画の音を重ねて鳴らします。"
        case .muteWhenOtherAudioPlaying:
            return "音楽アプリなどが鳴っている間は、動画の音を出しません(音楽はそのままの音量で流れ続けます)。何も鳴っていない時は動画の音を通常どおり出します。"
        }
    }
}
