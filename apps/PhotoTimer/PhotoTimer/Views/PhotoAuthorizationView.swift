import SwiftUI
import Photos

/// 写真ライブラリへのアクセスを依頼する画面。
/// これはOSが必ず要求する許可であり、アプリ独自の「事前解析による待たせる」ものではない。
struct PhotoAuthorizationView: View {
    @ObservedObject private var manager = PhotoLibraryManager.shared
    /// 文字の字体をテーマに合わせるために参照する(CEO要望・2026-09-06)。
    @AppStorage(AppThemeStore.key) private var themeRawValue: String = AppTheme.default.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .default }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("写真タイマー")
                .font(.title2).bold()
                .fontDesign(theme.fontDesign)

            Text("タイマーが動いている間、写真フォルダの写真・動画をスライドショーのように流します。\nすべての処理は端末内だけで行われ、外部には送信されません。")
                .fontDesign(theme.fontDesign)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                Text("写真へのアクセスが許可されていません。設定アプリから許可してください。")
                    .fontDesign(theme.fontDesign)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("設定を開く").fontDesign(theme.fontDesign)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await manager.requestAccess() }
                } label: {
                    Text("写真へのアクセスを許可する").fontDesign(theme.fontDesign)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemedScreenBackground())
    }
}
