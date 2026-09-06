import SwiftUI
import StoreKit

/// プレミアム機能(演出パターン・自作リスト(リスト作成)・場所での絞り込み)の購入・復元を行う画面。
/// 設定画面(表示設定)・絞り込み画面のロックされた項目のどちらからも、このシートを開く導線がある。
struct PurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var isPurchasing = false
    @State private var isRestoring = false
    /// 見出し・説明文・ボタンの字体をテーマに合わせるために参照する(CEO要望・2026-09-06)。
    @AppStorage(AppThemeStore.key) private var themeRawValue: String = AppTheme.default.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .default }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    featureRow(icon: "wand.and.stars", title: "演出パターン")
                    featureRow(icon: "list.star", title: "自作リスト(リスト作成)")
                    featureRow(icon: "mappin.and.ellipse", title: "場所での絞り込み")
                } header: {
                    Text("プレミアム機能でできること").fontDesign(theme.fontDesign)
                }

                Section {
                    if purchaseManager.isPremiumUnlocked {
                        Label {
                            Text("購入済みです").fontDesign(theme.fontDesign)
                        } icon: {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                        .accessibilityIdentifier("premiumUnlockedLabel")
                    } else if let product = purchaseManager.product {
                        Button {
                            Task {
                                isPurchasing = true
                                await purchaseManager.purchase()
                                isPurchasing = false
                            }
                        } label: {
                            HStack {
                                Text("\(product.displayName)を購入(\(product.displayPrice))")
                                    .fontDesign(theme.fontDesign)
                                Spacer()
                                if isPurchasing { ProgressView() }
                            }
                        }
                        .disabled(isPurchasing)
                        .accessibilityIdentifier("purchasePremiumButton")
                    } else if purchaseManager.isLoadingProduct {
                        HStack {
                            ProgressView()
                            Text("商品情報を取得しています…").fontDesign(theme.fontDesign)
                        }
                    } else {
                        Text("商品情報を取得できませんでした。通信状況を確認し、時間をおいてもう一度お試しください。")
                            .fontDesign(theme.fontDesign)
                        Button {
                            Task { await purchaseManager.loadProduct() }
                        } label: {
                            Text("もう一度読み込む").fontDesign(theme.fontDesign)
                        }
                    }

                    Button {
                        Task {
                            isRestoring = true
                            await purchaseManager.restorePurchases()
                            isRestoring = false
                        }
                    } label: {
                        HStack {
                            Text("購入を復元").fontDesign(theme.fontDesign)
                            Spacer()
                            if isRestoring { ProgressView() }
                        }
                    }
                    .disabled(isRestoring)
                    .accessibilityIdentifier("restorePurchasesButton")
                } header: {
                    Text("購入").fontDesign(theme.fontDesign)
                } footer: {
                    Text("機種変更などで購入済みのはずなのに機能が使えない場合は、「購入を復元」をお試しください。")
                        .fontDesign(theme.fontDesign)
                }

                if let message = purchaseManager.lastErrorMessage {
                    Section {
                        Text(message).fontDesign(theme.fontDesign).foregroundStyle(.red)
                    }
                }
            }
            .themedFormBackground()
            .themedFontDesign()
            .navigationTitle("プレミアム機能")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("閉じる").fontDesign(theme.fontDesign) }
                }
            }
            .task {
                if purchaseManager.product == nil {
                    await purchaseManager.loadProduct()
                }
            }
        }
    }

    private func featureRow(icon: String, title: String) -> some View {
        Label {
            Text(title).fontDesign(theme.fontDesign)
        } icon: {
            Image(systemName: icon).foregroundStyle(theme.accentColor)
        }
    }
}
