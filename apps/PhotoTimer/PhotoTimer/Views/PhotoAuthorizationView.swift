import SwiftUI
import Photos

/// 写真ライブラリへのアクセスを依頼する画面。
/// これはOSが必ず要求する許可であり、アプリ独自の「事前解析による待たせる」ものではない。
struct PhotoAuthorizationView: View {
    @ObservedObject private var manager = PhotoLibraryManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("写真タイマー")
                .font(.title2).bold()

            Text("タイマーが動いている間、写真フォルダの写真・動画をスライドショーのように流します。\nすべての処理は端末内だけで行われ、外部には送信されません。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                Text("写真へのアクセスが許可されていません。設定アプリから許可してください。")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("写真へのアクセスを許可する") {
                    Task { await manager.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
