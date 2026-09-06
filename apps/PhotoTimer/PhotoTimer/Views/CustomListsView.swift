import SwiftUI
import Photos

/// 自作リスト(CEOが写真ライブラリから自分で選んだ写真をまとめたリスト)の一覧・作成・削除画面。
/// 個々のリストの名前変更・写真の追加削除は CustomListEditView で行う。
struct CustomListsView: View {
    @State private var lists: [CustomPhotoList] = CustomPhotoListStore.load()
    @State private var showingPicker = false
    @State private var pendingIdentifiers: [String] = []
    @State private var showingNamePrompt = false
    @State private var newListName = ""
    @State private var editingList: CustomPhotoList?

    var body: some View {
        List {
            if lists.isEmpty {
                Text("まだリストがありません。右上の「+」から、写真ライブラリから選んで作成できます。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lists) { list in
                    Button {
                        editingList = list
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name).foregroundStyle(.primary)
                                Text("\(list.assetLocalIdentifiers.count)枚")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete(perform: deleteLists)
            }
        }
        .themedFormBackground()
        .themedFontDesign()
        .navigationTitle("保存したリスト")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pendingIdentifiers = []
                    showingPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addCustomListButton")
            }
        }
        // 新規作成用のピッカー(preselectedIdentifiersは常に空)。編集時のピッカーは
        // CustomListEditView自身が持つ(それぞれのシートが独立して開けるようにするため)。
        .sheet(isPresented: $showingPicker) {
            PhotoPickerView(preselectedIdentifiers: []) { identifiers in
                pendingIdentifiers = identifiers
                if !identifiers.isEmpty {
                    newListName = ""
                    showingNamePrompt = true
                }
            }
        }
        .alert("リストの名前", isPresented: $showingNamePrompt) {
            TextField("例: 家族旅行", text: $newListName)
            Button("保存") { commitNewList() }
            Button("キャンセル", role: .cancel) { pendingIdentifiers = [] }
        } message: {
            Text("\(pendingIdentifiers.count)枚を選びました")
        }
        .sheet(item: $editingList) { list in
            CustomListEditView(
                list: list,
                onSave: { updated in
                    if let index = lists.firstIndex(where: { $0.id == updated.id }) {
                        lists[index] = updated
                        CustomPhotoListStore.save(lists)
                    }
                },
                onDelete: {
                    lists.removeAll { $0.id == list.id }
                    CustomPhotoListStore.save(lists)
                }
            )
        }
    }

    private func commitNewList() {
        guard !pendingIdentifiers.isEmpty else { return }
        let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = CustomPhotoList(name: trimmed.isEmpty ? "名称未設定のリスト" : trimmed, assetLocalIdentifiers: pendingIdentifiers)
        lists.append(list)
        CustomPhotoListStore.save(lists)
        pendingIdentifiers = []
    }

    private func deleteLists(at offsets: IndexSet) {
        lists.remove(atOffsets: offsets)
        CustomPhotoListStore.save(lists)
    }
}

/// 1件の自作リストの名前変更・写真の追加削除・削除を行う画面。
private struct CustomListEditView: View {
    @State var list: CustomPhotoList
    let onSave: (CustomPhotoList) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showingPicker = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("リストの名前", text: $list.name)
                        .accessibilityIdentifier("customListNameField")
                }
                Section {
                    if list.assetLocalIdentifiers.isEmpty {
                        Text("写真がありません").foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 6) {
                            ForEach(list.assetLocalIdentifiers, id: \.self) { assetID in
                                CustomListThumbnail(assetID: assetID) {
                                    list.assetLocalIdentifiers.removeAll { $0 == assetID }
                                }
                            }
                        }
                    }
                    Button {
                        showingPicker = true
                    } label: {
                        Label("写真を追加・選び直す", systemImage: "photo.badge.plus")
                    }
                    .accessibilityIdentifier("editCustomListPhotosButton")
                } header: {
                    Text("写真(\(list.assetLocalIdentifiers.count)枚)")
                } footer: {
                    Text("写真の右上の×で、このリストから外せます(写真そのものは削除されません)。")
                }
                Section {
                    Button("このリストを削除", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                    .accessibilityIdentifier("deleteCustomListButton")
                }
            }
            .themedFormBackground()
            .themedFontDesign()
            .navigationTitle("リストを編集")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onSave(list)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                // 【重要】PHPickerViewControllerは「ユーザーがキャンセルを押した」場合も
                // 「1枚も選ばずに確定した」場合も、どちらも空の結果を返す(Appleの仕様上、
                // delegateのコールバックだけではこの2つを区別できない)。編集画面(この画面)は
                // 既存の写真をあらかじめ選択済み状態でピッカーを開くため、もし空の結果をそのまま
                // 「新しい内容」として上書きしてしまうと、単にキャンセルしただけのつもりが
                // リストの中身を全部消してしまう事故になる。安全側に倒し、空の結果は
                // 「キャンセルされた(変更なし)」として無視する。本当に全部外したい時は、
                // 個々のサムネイルの×ボタンで1枚ずつ外す(曖昧さの無い、明確な操作)。
                PhotoPickerView(preselectedIdentifiers: list.assetLocalIdentifiers) { identifiers in
                    guard !identifiers.isEmpty else { return }
                    list.assetLocalIdentifiers = identifiers
                }
            }
            .alert("「\(list.name)」を削除しますか?", isPresented: $showingDeleteConfirm) {
                Button("削除", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("リストの中身(\(list.assetLocalIdentifiers.count)枚)が削除されるだけで、写真そのものは残ります。")
            }
        }
    }
}

/// リスト編集画面のサムネイル1枚。写真がすでにライブラリから削除されている場合は、
/// 落ちずに「見つかりません」の表示に切り替える(絶対制約:リストが指す写真が後で削除されていた
/// 場合に、落ちずに除外して扱うこと)。
private struct CustomListThumbnail: View {
    let assetID: String
    let onRemove: () -> Void
    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if missing {
                    Color.gray.opacity(0.2).overlay {
                        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                    }
                } else {
                    Color.gray.opacity(0.15).overlay { ProgressView() }
                }
            }
            .frame(height: 90)
            .clipped()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: assetID) {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = fetchResult.firstObject else {
                missing = true
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            image = await Self.thumbnail(for: asset, options: options)
        }
    }

    /// 【他所(SlideshowView.HistoryThumbnail等)と同じ理由】opportunisticは低画質→高画質と
    /// 2回コールバックが来ることがあるため、二重完了を防ぐ小さなBoxを使う。
    private static func thumbnail(for asset: PHAsset, options: PHImageRequestOptions) async -> UIImage? {
        await withCheckedContinuation { continuation in
            final class ResumeBox: @unchecked Sendable { var didResume = false }
            let box = ResumeBox()
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 200, height: 200), contentMode: .aspectFill, options: options) { image, info in
                guard !box.didResume else { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                guard !degraded || image == nil else { return }
                box.didResume = true
                continuation.resume(returning: image)
            }
        }
    }
}
