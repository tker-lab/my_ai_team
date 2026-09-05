import SwiftUI
import PhotosUI

/// 写真ライブラリから複数選択するための標準ピッカー(PHPickerViewController)のラッパー。
///
/// 【なぜPHPickerViewControllerか】Appleが用意している、複数選択に対応した標準の写真選択画面。
/// 選んだ結果(PHAssetのlocalIdentifierだけ)を受け取るだけで、写真本体をこのアプリ側にコピーする
/// 処理は一切ない(このアプリの「写真本体は複製しない」という設計方針に沿う)。
struct PhotoPickerView: UIViewControllerRepresentable {
    /// 編集時、すでにリストに入っている写真をあらかじめ選択済みにする(空 = 新規作成として開く)。
    /// これを使うと、ユーザーが選択を外せば「リストから削除」、新しく選べば「リストに追加」になる。
    var preselectedIdentifiers: [String]
    /// ピッカーを閉じた後に呼ばれる。結果として渡すのは常に「今回のピッカー操作後の全選択」
    /// (追加も削除も反映済みの完全なリスト)。1枚も選ばれなかった(全解除された、または
    /// 新規作成でキャンセルされた)場合は空配列が渡る。
    var onFinish: ([String]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0 // 0 = 上限なし
        config.selection = .ordered // 選んだ順を保つ
        config.preselectedAssetIdentifiers = preselectedIdentifiers
        // filterを指定しない = 写真・動画のどちらも選べる(このアプリ自体が両方を扱うため)。
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onFinish: ([String]) -> Void

        init(onFinish: @escaping ([String]) -> Void) {
            self.onFinish = onFinish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let identifiers = results.compactMap(\.assetIdentifier)
            picker.dismiss(animated: true) { [onFinish] in
                onFinish(identifiers)
            }
        }
    }
}
