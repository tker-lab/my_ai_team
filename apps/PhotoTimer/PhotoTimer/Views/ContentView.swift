import SwiftUI

/// ホーム画面(タイマー設定)。ここが「アプリを開いたら即使える」の中心。
/// フィルタ条件を何も選ばなくても(=全件対象で)すぐにスタートできる。
struct ContentView: View {
    @StateObject private var libraryIndex = LibraryIndex.shared
    /// タイマー時間は秒単位で保持する(CEO要望・2026-09-04:秒単位で使えるようにする)。
    @AppStorage("PhotoTimer.SelectedSeconds") private var selectedSeconds: Int = 300 // 既定 5分
    @State private var filterSettings: FilterSettings = FilterSettingsStore.load()
    /// 写真の表示秒数・動画の再生時間の扱い(CEO要望・2026-09-04:設定画面から変更できるようにする)。
    @State private var playbackSettings: PlaybackSettings = PlaybackSettingsStore.load()
    /// アラーム(音・鳴らし方)の設定(CEO要望・2026-09-05:設定画面から変更できるようにする)。
    @State private var alarmSettings: AlarmSettings = AlarmSettingsStore.load()
    @State private var showingFilterSheet = false
    @State private var showingPlaybackSettingsSheet = false
    @State private var showingAlarmSettingsSheet = false
    @State private var showingHelpSheet = false
    @State private var showingSlideshow = false

    /// 設定できる範囲(秒)。
    /// 下限1秒(CEO要望・2026-09-04):「一瞬だけ写真が映ってもそれはそれで面白い」という考えから、
    /// あえて実用上の下限(数枚は流れる長さ)を設けず、1秒から選べるようにしている。
    /// 上限10800秒(=180分): 元々の分単位の上限(180分)をそのまま秒に換算したもの。
    private let minSeconds = 1
    private let maxSeconds = 180 * 60

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "timer")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text(Self.timeString(selectedSeconds))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    // 自動テスト(XCUITest)が「大きく表示されている時間」を正確に読み取るための目印。
                    // 画面表示や動作には影響しない。
                    .accessibilityIdentifier("homeTimeLabel")

                // iPhone標準「時計」アプリのタイマーと同じ、ホイールを指で回して選ぶ方式。
                // 「分」と「秒」の2列(秒は0〜59を1秒刻み)で、秒単位の自由な指定ができる。
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        Picker("分", selection: minutesBinding) {
                            ForEach(0...(maxSeconds / 60), id: \.self) { m in
                                Text("\(m)").tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("minutesWheel")

                        Text("分")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 16)

                        // 【軽微指摘対応】下限は1秒(0分0秒は選べない)。以前は秒ホイールに常に0〜59を
                        // 表示していたため、「分0・秒0」を選ぶと内部的には1秒に補正されるのに、
                        // ホイールの見た目は0のままで食い違って見える不具合があった。
                        // 「分が0の時だけ、秒の選択肢から0を外す(1〜59のみ)」ことで、
                        // そもそも「分0・秒0」という組み合わせをホイール上で選べないようにし、
                        // 内部の補正とホイールの見た目が食い違う状況自体を起こらなくしている。
                        Picker("秒", selection: secondsBinding) {
                            ForEach(secondsWheelRange, id: \.self) { s in
                                Text("\(s)").tag(s)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("secondsWheel")

                        Text("秒")
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 150)

                    Text("設定可能な範囲: \(Self.presetLabel(minSeconds)) 〜 180分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Spacer()

                Button {
                    showingFilterSheet = true
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("絞り込み条件")
                        Spacer()
                        Text(filterSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .accessibilityIdentifier("filterButton")

                Button {
                    showingSlideshow = true
                } label: {
                    Text("スタート")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom)
                // 自動テスト(XCUITest)がこのボタンを確実に見つけられるようにするための目印。
                // 画面表示や動作には影響しない。
                .accessibilityIdentifier("startButton")
            }
            .navigationTitle("写真タイマー")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingHelpSheet = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    // 自動テスト(XCUITest)がこのボタンを確実に見つけられるようにするための目印。
                    .accessibilityIdentifier("helpButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAlarmSettingsSheet = true
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityIdentifier("alarmSettingsButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPlaybackSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    // 自動テスト(XCUITest)がこのボタンを確実に見つけられるようにするための目印。
                    .accessibilityIdentifier("playbackSettingsButton")
                }
            }
            .sheet(isPresented: $showingFilterSheet, onDismiss: {
                FilterSettingsStore.save(filterSettings)
            }) {
                FilterOptionsView(settings: $filterSettings)
            }
            .sheet(isPresented: $showingPlaybackSettingsSheet, onDismiss: {
                PlaybackSettingsStore.save(playbackSettings)
            }) {
                PlaybackSettingsView(settings: $playbackSettings)
            }
            .sheet(isPresented: $showingAlarmSettingsSheet, onDismiss: {
                AlarmSettingsStore.save(alarmSettings)
            }) {
                AlarmSettingsView(settings: $alarmSettings)
            }
            .sheet(isPresented: $showingHelpSheet) {
                HelpView()
            }
            .fullScreenCover(isPresented: $showingSlideshow) {
                SlideshowView(totalSeconds: selectedSeconds, settings: filterSettings, playbackSettings: playbackSettings, alarmSettings: alarmSettings, placeClusters: libraryIndex.placeClusters)
            }
            .onAppear {
                libraryIndex.refreshIfNeeded()
            }
        }
    }

    // MARK: - 分・秒それぞれのホイール用バインディング

    /// 「分」ホイールの選択。秒の部分はそのまま保ち、合計を範囲内に収める。
    private var minutesBinding: Binding<Int> {
        Binding<Int>(
            get: { selectedSeconds / 60 },
            set: { newMinutes in
                let secondsPart = selectedSeconds % 60
                selectedSeconds = Self.clamp(newMinutes * 60 + secondsPart, min: minSeconds, max: maxSeconds)
            }
        )
    }

    /// 「秒」ホイールの選択(0〜59を1秒刻み)。分の部分はそのまま保ち、合計を範囲内に収める。
    private var secondsBinding: Binding<Int> {
        Binding<Int>(
            get: { selectedSeconds % 60 },
            set: { newSecondsPart in
                let minutesPart = selectedSeconds / 60
                selectedSeconds = Self.clamp(minutesPart * 60 + newSecondsPart, min: minSeconds, max: maxSeconds)
            }
        )
    }

    private static func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        min(max(value, minValue), maxValue)
    }

    /// 秒ホイールに表示する選択肢の範囲。分が0の時だけ0を除く(1〜59)。
    /// 分が1以上の時は合計が必ず60秒以上になるので、下限(1秒)を気にせず0〜59を出せる。
    private var secondsWheelRange: Range<Int> {
        minutesBinding.wrappedValue == 0 ? 1..<60 : 0..<60
    }

    private var filterSummary: String {
        var parts: [String] = []
        if filterSettings.dateRange != .all { parts.append("日時") }
        if filterSettings.mediaType != .all { parts.append(filterSettings.mediaType.rawValue) }
        if filterSettings.excludeScreenshots { parts.append("スクショ除く") }
        if !filterSettings.selectedAlbumIDs.isEmpty { parts.append("アルバム\(filterSettings.selectedAlbumIDs.count)件") }
        if !filterSettings.selectedMoods.isEmpty { parts.append("雰囲気\(filterSettings.selectedMoods.count)件") }
        if !filterSettings.selectedPlaceIDs.isEmpty { parts.append("場所\(filterSettings.selectedPlaceIDs.count)件") }
        if !filterSettings.selectedCategories.isEmpty { parts.append("カテゴリ\(filterSettings.selectedCategories.count)件") }
        return parts.isEmpty ? "すべての写真・動画" : parts.joined(separator: " / ")
    }

    /// "30秒" / "1分" のような短い表記(秒未満は秒表記、それ以外は分表記)。「設定可能な範囲」の説明文で使う。
    private static func presetLabel(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)秒"
        }
        return "\(seconds / 60)分"
    }

    /// 大きい表示用の "分:秒" 形式("01:30" のような表記に統一)。
    private static func timeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
