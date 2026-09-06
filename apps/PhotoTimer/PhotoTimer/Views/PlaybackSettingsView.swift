import SwiftUI

/// 「写真1枚あたりの表示秒数」「動画の再生時間の扱い」を設定する画面。
/// CEO要望(2026-09-04):これまで固定値だった2つの値をユーザーが変更できるようにする。
struct PlaybackSettingsView: View {
    @Binding var settings: PlaybackSettings
    @Environment(\.dismiss) private var dismiss
    /// アプリ全体のカラーテーマ(CEO要望・2026-09-06)。ここが選択場所。
    @AppStorage(AppThemeStore.key) private var themeRawValue: String = AppTheme.default.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .default }
    /// 課金状態(CEO要望・2026-09-06:演出パターンは有料機能)。購入直後に画面が
    /// 即座に更新されるよう@ObservedObjectで購読する。
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var showingPurchaseSheet = false

    var body: some View {
        NavigationStack {
            Form {
                premiumSection

                Section {
                    // 【重複タイトル対策】.pickerStyle(.inline)はPickerのラベル("テーマ")を
                    // 枠内の一番上に選択不可の見出しとして表示してしまい、Section見出し
                    // (「見た目のテーマ」)と紛らわしく重複する。.labelsHidden()で視覚的にだけ
                    // 隠す(VoiceOver用のラベル自体は残る)。演出パターン・動画の音のPickerも同様。
                    Picker(selection: $themeRawValue) {
                        ForEach(AppTheme.allCases) { themeCase in
                            Text(themeCase.displayName).fontDesign(themeCase.fontDesign).tag(themeCase.rawValue)
                        }
                    } label: {
                        Text("テーマ").fontDesign(theme.fontDesign)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("appThemePicker")
                } header: {
                    Text("見た目のテーマ").fontDesign(theme.fontDesign)
                } footer: {
                    Text("アプリ全体の配色を切り替えます。文言や機能は変わりません。").fontDesign(theme.fontDesign)
                }

                Section {
                    // 【2026-09-06追加:演出パターンは有料機能】「シンプル」以外を選ぼうとした時、
                    // 未購入ならこのBinding自身が選択を反映せず(=シンプルのまま)、代わりに
                    // 購入画面を開く。ロックされている項目には鍵アイコンを添えて分かるようにする
                    // (機能があることは分かるが選べない、というCEO要望の見え方)。
                    Picker(selection: presentationPatternBinding) {
                        ForEach(PresentationPattern.allCases) { pattern in
                            HStack {
                                Text(pattern.displayName).fontDesign(theme.fontDesign)
                                if pattern != .classic && !purchaseManager.isPremiumUnlocked {
                                    Spacer()
                                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                }
                            }
                            .tag(pattern)
                        }
                    } label: {
                        Text("演出パターン").fontDesign(theme.fontDesign)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("presentationPatternPicker")
                } header: {
                    Text("演出パターン").fontDesign(theme.fontDesign)
                } footer: {
                    if !purchaseManager.isPremiumUnlocked {
                        Text("鍵のマークが付いた演出パターンはプレミアム機能です。選ぶと購入画面が開きます。")
                            .fontDesign(theme.fontDesign)
                    }
                }

                // 【2026-09-05 CEO決定】演出パターン(.classic以外)を選んだ時は、パターン自身が
                // 「間」ごとの秒数を決めるため、この2つの設定行は隠す(混乱を避けるため)。
                // .classic(演出パターンを選ばない)の時はこれまで通りここで調整できる。
                if settings.presentationPattern == .classic {
                    Section {
                        Picker(selection: $settings.photoSlideDurationSeconds) {
                            ForEach(PlaybackSettingsChoices.photoDurations, id: \.self) { value in
                                Text(Self.label(for: value)).fontDesign(theme.fontDesign).tag(value)
                            }
                        } label: {
                            Text("表示秒数").fontDesign(theme.fontDesign)
                        }
                        // 選択肢が多い(17個)ため、タップでメニューが開く方式にする。
                        .pickerStyle(.menu)
                        // 自動テスト(XCUITest)がこのピッカーを確実に見つけられるようにするための目印。
                        .accessibilityIdentifier("photoDurationPicker")
                    } header: {
                        Text("写真1枚あたりの表示時間").fontDesign(theme.fontDesign)
                    } footer: {
                        Text("短くすると次々に切り替わり、一瞬だけ映る写真も楽しめます。長くするとじっくり見せられ、表示中に次の候補を探せる時間も増えます。")
                            .fontDesign(theme.fontDesign)
                    }

                    Section {
                        Picker(selection: $settings.videoPlaybackMode) {
                            Text("最後まで再生する").fontDesign(theme.fontDesign).tag(VideoPlaybackMode.full)
                            Text("指定秒数で切り上げる").fontDesign(theme.fontDesign).tag(VideoPlaybackMode.capped)
                        } label: {
                            Text("動画の再生").fontDesign(theme.fontDesign)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("videoModePicker")

                        if settings.videoPlaybackMode == .capped {
                            Picker(selection: $settings.videoCapSeconds) {
                                ForEach(PlaybackSettingsChoices.videoCapDurations, id: \.self) { value in
                                    Text("\(Int(value))秒").fontDesign(theme.fontDesign).tag(value)
                                }
                            } label: {
                                Text("切り上げる秒数").fontDesign(theme.fontDesign)
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("videoCapPicker")
                        }
                    } header: {
                        Text("動画の再生時間").fontDesign(theme.fontDesign)
                    } footer: {
                        // 【説明文の修正】以前は「タイマーの残り時間を超えて再生され続けることがある」としていたが、
                        // 実際の実装ではタイマー終了時に動画を必ず止める(TimerController.finish())ため誤りだった。
                        // 実際の挙動(タイマーが終わったらそこで打ち切られる)に合わせて説明文を直した。
                        Text(settings.videoPlaybackMode == .full
                             ? "動画は最後まで再生されます。ただしタイマーの残り時間より動画が長い場合は、タイマー終了と同時にそこで打ち切られます。"
                             : "指定した秒数に達したら、動画の途中でも次の写真・動画に切り替えます。")
                            .fontDesign(theme.fontDesign)
                    }
                } else {
                    Section {
                        EmptyView()
                    } footer: {
                        Text("演出パターンを選んでいる間は、1枚あたりの表示時間・動画の再生時間はパターン側の設定が使われます(「シンプル」に戻すと、ここで調整できるようになります)。")
                            .fontDesign(theme.fontDesign)
                    }
                }

                Section {
                    Picker(selection: $settings.videoAudioMixMode) {
                        Text("両方そのまま鳴らす").fontDesign(theme.fontDesign).tag(VideoAudioMixMode.mixWithOthers)
                        Text("音楽を小さくして重ねる").fontDesign(theme.fontDesign).tag(VideoAudioMixMode.duckOthers)
                        Text("音楽が鳴っていたら動画は無音").fontDesign(theme.fontDesign).tag(VideoAudioMixMode.muteWhenOtherAudioPlaying)
                    } label: {
                        Text("動画の音").fontDesign(theme.fontDesign)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("videoAudioMixModePicker")
                } header: {
                    Text("動画の音と他アプリの音楽").fontDesign(theme.fontDesign)
                } footer: {
                    Text(videoAudioMixModeFooter).fontDesign(theme.fontDesign)
                }
            }
            .themedFormBackground()
            .navigationTitle("表示設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("完了").fontDesign(theme.fontDesign) }
                }
            }
            .sheet(isPresented: $showingPurchaseSheet) {
                PurchaseView()
            }
        }
        .themedTint()
        .themedFontDesign()
    }

    /// 設定画面のどこからでもプレミアム機能の購入画面へ入れる入口(CEO要望・2026-09-06)。
    private var premiumSection: some View {
        Section {
            HStack {
                Text(purchaseManager.isPremiumUnlocked ? "購入済み" : "未購入")
                    .fontDesign(theme.fontDesign)
                Spacer()
                if purchaseManager.isPremiumUnlocked {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                }
            }
            Button {
                showingPurchaseSheet = true
            } label: {
                Text(purchaseManager.isPremiumUnlocked ? "購入内容を確認する" : "プレミアム機能を購入する")
                    .fontDesign(theme.fontDesign)
            }
            .accessibilityIdentifier("openPurchaseSheetButton")
        } header: {
            Text("プレミアム機能").fontDesign(theme.fontDesign)
        } footer: {
            Text("複数選択削除・自作リスト(リスト作成)・場所での絞り込み・演出パターンをまとめて使えるようになります。")
                .fontDesign(theme.fontDesign)
        }
    }

    /// 「シンプル」以外を未購入で選ぼうとした時は選択を反映せず、購入画面を開く
    /// (機能があることは分かるが選べない、というCEO要望の見え方)。
    private var presentationPatternBinding: Binding<PresentationPattern> {
        Binding(
            get: { settings.presentationPattern },
            set: { newValue in
                if newValue != .classic && !purchaseManager.isPremiumUnlocked {
                    showingPurchaseSheet = true
                    return
                }
                settings.presentationPattern = newValue
            }
        )
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
