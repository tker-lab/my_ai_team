---
name: wikidata-un-members-query-and-debug-print-pitfall
description: WikidataでUN加盟国の「現在の」加盟国だけを取るにはP582(終了日)の無いstatementで絞る。デバッグ用print()の出力がシェルリダイレクトでデータファイルに紛れ込み1行分ズレる事故が起きた
metadata:
  type: project
---

## Wikidataで「現在のUN加盟国」だけを取るクエリ
単純に`?country wdt:P463 wd:Q1065`(UNITED NATIONSのmember)で検索すると、ソ連・東ドイツ・
チェコスロバキアのような**過去に加盟していた消滅国家**も混ざる(2026-09-12確認、229件ヒット)。
`p:P463`のstatementに`pq:P582`(終了日)が付いていないものだけに絞ると、現存する193カ国だけに
なる:
```sparql
SELECT ?countryLabel ?iso2 ?iso3 WHERE {
  ?country p:P463 ?stmt .
  ?stmt ps:P463 wd:Q1065 .
  FILTER NOT EXISTS { ?stmt pq:P582 ?end }
  OPTIONAL { ?country wdt:P297 ?iso2 . }
  OPTIONAL { ?country wdt:P298 ?iso3 . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
```
**Why:** 消滅国家の多くはISO 3166コード(P297/P298)を持たないため、実務上は
「iso3が空でない行だけ残す」だけでも同じ効果が得られることが多いが、上記のP582フィルタの方が
本質的で確実。デンマークだけは(理由不明の登録形式差で)このクエリでも漏れるため手で1件補う必要がある。
**How to apply:** 「ご飯」版など、国リストを再度Wikidataから取る場面があれば、このクエリ形と
「デンマークだけ手動追加」を再利用する。

## デバッグ用print()がシェルリダイレクトでデータファイルの1行目に紛れ込んだ事故
`python3 script.py > output.tsv`のようにスクリプト全体の標準出力をファイルへリダイレクトすると、
スクリプト内の`print('total rows', len(rows))`のようなデバッグ表示もそのままファイルの1行として
書き込まれる。TSVをawkで`$1 != ""`のようにフィルタしても、スペース区切りの文字列は1カラム扱いで
"空でない"と判定されるため素通りし、正しいデータが1行分ズレる/上書きされる事故につながった
(2026-09-12、UN加盟国リスト生成で実際に発生、原因究明に時間を要した)。
**Why:** 「ファイルに書き出す処理」と「進捗をターミナルに表示する処理」を同じstdoutに混在させると、
リダイレクトした瞬間にデータが汚染されるが、目視でもすぐには気づきにくい。
**How to apply:** データ生成スクリプトでは、進捗ログは`print(..., file=sys.stderr)`に出すか、
最初からファイルへの書き込みは`open(path,'w').write(...)`のように明示的に行い、stdoutリダイレクトに
一切依存しない設計にする。
