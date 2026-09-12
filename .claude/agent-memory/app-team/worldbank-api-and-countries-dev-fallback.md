---
name: worldbank-api-and-countries-dev-fallback
description: 世界銀行APIの一括取得はmrv=1と組み合わせると古いデータの国が抜け落ちる。REST Countriesの無料キー不要な代替(countries.dev)は borders欠落が「本当に0」か「取得漏れ」か判別できない
metadata:
  type: project
---

## 世界銀行API: `country/all/indicator/<code>?mrv=1` は古いデータの国を取り漏らす
`https://api.worldbank.org/v2/country/all/indicator/NY.GDP.MKTP.CD?mrv=1&per_page=400`のように
「全カ国まとめて1回」の一括取得+`mrv=1`(最新値)を組み合わせると、データが何年も
更新されていない国(エリトリアのGDPが2011年で止まっている、等)の値が結果に含まれない。
同じ国を`country/{iso3}/indicator/...?mrv=1`で単体で問い合わせると正しく取れる
(国カードバトルのカード生成で2026-09-12に実際に発生、193カ国×8指標のうちGDPで13カ国抜けた)。
**Why:** 一括+mrv=1の内部実装が原因と思われるが詳細未特定。日付範囲(`date=1990:2026`)を足しても
一括モードでは直らなかった(単体クエリでは元々date指定無しでも問題ない)。
**How to apply:** 世界銀行APIを「全カ国一括」で叩く時は、必ず取得件数を対象カ国数と比較し、
足りない国だけ個別に(1カ国ずつ)`mrv=1`で再取得するフォールバックを入れる。[[app-team-country-cards-data-pipeline]]

## countries.dev(REST Countries v2互換の無料・キー不要ミラー)の隣接国データは欠落が紛れる
REST Countries公式(v5)はアカウント登録+メール確認が必須になったため、キー不要な代替として
`https://countries.dev/alpha/{ISO3}`を採用した。`languages`は193カ国全て取れたが、`borders`
(陸上国境=隣接国)は155/193カ国分しか無い。欠けている38カ国の大半は実際に陸上国境が無い島国
(日本・オーストラリア等)だが、**シンガポール(マレーシアと道路橋で陸続き)・チェコ(複数の陸上
国境がある)のように、本当は隣接国があるのに`borders`キー自体が欠落している国も混在**していた。
**Why:** 「キーが無い=0件」と決め打ちすると、シンガポール・チェコのような実在する隣接国を持つ国を
誤って0件と表示してしまう。
**How to apply:** このAPIで`borders`キーが無い国は「データ不明」として扱い、0件と推測しない
(=カードを作らない)。1件でも実例(シンガポール等)で誤りが見つかったら、その代替APIの「キー欠落
=0」という解釈は信用しないほうがよい。次回データ更新時は本家REST Countries(要アカウント)への
切り替えを推奨。
