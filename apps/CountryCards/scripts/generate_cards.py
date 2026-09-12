#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
「国カードバトル(仮称)」のカードデータ生成パイプライン(Phase 1)。

何をするスクリプトか(アプリ開発初心者のCEO向け解説):
  このアプリのカードは「国 × 要素(人口・GDPなど)」の組み合わせで1枚になる。
  そのカードの元になる数値を、無料の公的API(世界銀行・Wikidata・countries.dev)
  から自動で取ってきて、アプリに埋め込むための1つのJSONファイル
  (../CountryCards/Resources/cards.json)にまとめるのがこのスクリプトの役目。

  実行方法: python3 generate_cards.py
  (このフォルダ内で完結する。インターネット接続が必要。世界銀行APIキー不要)

  年1回程度、データを更新したくなったらこのスクリプトを再実行するだけでよい
  (詳細はapp_team_country_cards.mdの「データ更新の仕組み」を参照)。
"""

import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
OUTPUT_PATH = SCRIPT_DIR.parent / "CountryCards" / "Resources" / "cards.json"

# 世界銀行・Wikidata・countries.dev のいずれも「誰が/何のために呼んでいるか」を
# 名乗るのが行儀のよい使い方なので、連絡先入りのUser-Agentを共通で使う。
USER_AGENT = "CountryCardsApp-DataPipeline/0.1 (contact: tker1996@gmail.com)"


def http_get_json(url, headers=None, retries=3, timeout=30):
    """URLを取得してJSONとして読む。失敗したら少し待って再試行する
    (無料APIはたまに一時的にエラーを返すことがあるため)。"""
    hdrs = {"User-Agent": USER_AGENT}
    if headers:
        hdrs.update(headers)
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=hdrs)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:  # noqa: BLE001 - 生成スクリプトなので広めに拾って再試行
            last_err = e
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"取得に失敗しました: {url} ({last_err})")


# ---------------------------------------------------------------------------
# 1. 国連加盟193カ国のリストを組み立てる
# ---------------------------------------------------------------------------
# Wikidataで「UNITED NATIONS(Q1065)のメンバーである」かつ「その所属が終了して
# いない(過去の加盟=ソ連・東ドイツなど歴史上の国を除く)」ものを検索する。
# ただしデンマークだけ登録のされ方が違うために抜け落ちるため、手で1件補う
# (2026-09-12に一度確認済み。今回のスクリプトでも同じ抜けを確認し、同様に補った)。
WIKIDATA_SPARQL = """
SELECT ?countryLabel ?iso2 ?iso3 WHERE {
  ?country p:P463 ?stmt .
  ?stmt ps:P463 wd:Q1065 .
  FILTER NOT EXISTS { ?stmt pq:P582 ?end }
  OPTIONAL { ?country wdt:P297 ?iso2 . }
  OPTIONAL { ?country wdt:P298 ?iso3 . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} ORDER BY ?countryLabel
"""

# 国連加盟193カ国の日本語名(外務省の一般的な表記に準拠)。
# ISO3(3文字コード)をキーにする。数が多いため、後段でこの辞書と
# Wikidataの取得結果を突き合わせて「1件も過不足がないか」を必ず検証する。
JP_NAMES = {
    "AFG": "アフガニスタン", "AGO": "アンゴラ", "ALB": "アルバニア", "AND": "アンドラ",
    "ARE": "アラブ首長国連邦", "ARG": "アルゼンチン", "ARM": "アルメニア",
    "ATG": "アンティグア・バーブーダ", "AUS": "オーストラリア", "AUT": "オーストリア",
    "AZE": "アゼルバイジャン", "BDI": "ブルンジ", "BEL": "ベルギー", "BEN": "ベナン",
    "BFA": "ブルキナファソ", "BGD": "バングラデシュ", "BGR": "ブルガリア",
    "BHR": "バーレーン", "BHS": "バハマ", "BIH": "ボスニア・ヘルツェゴビナ",
    "BLR": "ベラルーシ", "BLZ": "ベリーズ", "BOL": "ボリビア", "BRA": "ブラジル",
    "BRB": "バルバドス", "BRN": "ブルネイ", "BTN": "ブータン", "BWA": "ボツワナ",
    "CAF": "中央アフリカ共和国", "CAN": "カナダ", "CHE": "スイス", "CHL": "チリ",
    "CHN": "中国", "CIV": "コートジボワール", "CMR": "カメルーン",
    "COD": "コンゴ民主共和国", "COG": "コンゴ共和国", "COL": "コロンビア",
    "COM": "コモロ", "CPV": "カーボベルデ", "CRI": "コスタリカ", "CUB": "キューバ",
    "CYP": "キプロス", "CZE": "チェコ", "DEU": "ドイツ", "DJI": "ジブチ",
    "DMA": "ドミニカ国", "DNK": "デンマーク", "DOM": "ドミニカ共和国",
    "DZA": "アルジェリア", "ECU": "エクアドル", "EGY": "エジプト", "ERI": "エリトリア",
    "ESP": "スペイン", "EST": "エストニア", "ETH": "エチオピア", "FIN": "フィンランド",
    "FJI": "フィジー", "FRA": "フランス", "FSM": "ミクロネシア連邦", "GAB": "ガボン",
    "GBR": "イギリス", "GEO": "ジョージア", "GHA": "ガーナ", "GIN": "ギニア",
    "GMB": "ガンビア", "GNB": "ギニアビサウ", "GNQ": "赤道ギニア", "GRC": "ギリシャ",
    "GRD": "グレナダ", "GTM": "グアテマラ", "GUY": "ガイアナ", "HND": "ホンジュラス",
    "HRV": "クロアチア", "HTI": "ハイチ", "HUN": "ハンガリー", "IDN": "インドネシア",
    "IND": "インド", "IRL": "アイルランド", "IRN": "イラン", "IRQ": "イラク",
    "ISL": "アイスランド", "ISR": "イスラエル", "ITA": "イタリア", "JAM": "ジャマイカ",
    "JOR": "ヨルダン", "JPN": "日本", "KAZ": "カザフスタン", "KEN": "ケニア",
    "KGZ": "キルギス", "KHM": "カンボジア", "KIR": "キリバス",
    "KNA": "セントクリストファー・ネービス", "KOR": "韓国", "KWT": "クウェート",
    "LAO": "ラオス", "LBN": "レバノン", "LBR": "リベリア", "LBY": "リビア",
    "LCA": "セントルシア", "LIE": "リヒテンシュタイン", "LKA": "スリランカ",
    "LSO": "レソト", "LTU": "リトアニア", "LUX": "ルクセンブルク", "LVA": "ラトビア",
    "MAR": "モロッコ", "MCO": "モナコ", "MDA": "モルドバ", "MDG": "マダガスカル",
    "MDV": "モルディブ", "MEX": "メキシコ", "MHL": "マーシャル諸島",
    "MKD": "北マケドニア", "MLI": "マリ", "MLT": "マルタ", "MMR": "ミャンマー",
    "MNE": "モンテネグロ", "MNG": "モンゴル", "MOZ": "モザンビーク",
    "MRT": "モーリタニア", "MUS": "モーリシャス", "MWI": "マラウイ",
    "MYS": "マレーシア", "NAM": "ナミビア", "NER": "ニジェール", "NGA": "ナイジェリア",
    "NIC": "ニカラグア", "NLD": "オランダ", "NOR": "ノルウェー", "NPL": "ネパール",
    "NRU": "ナウル", "NZL": "ニュージーランド", "OMN": "オマーン", "PAK": "パキスタン",
    "PAN": "パナマ", "PER": "ペルー", "PHL": "フィリピン", "PLW": "パラオ",
    "PNG": "パプアニューギニア", "POL": "ポーランド", "PRK": "北朝鮮",
    "PRT": "ポルトガル", "PRY": "パラグアイ", "QAT": "カタール", "ROU": "ルーマニア",
    "RUS": "ロシア", "RWA": "ルワンダ", "SAU": "サウジアラビア", "SDN": "スーダン",
    "SEN": "セネガル", "SGP": "シンガポール", "SLB": "ソロモン諸島",
    "SLE": "シエラレオネ", "SLV": "エルサルバドル", "SMR": "サンマリノ",
    "SOM": "ソマリア", "SRB": "セルビア", "SSD": "南スーダン",
    "STP": "サントメ・プリンシペ", "SUR": "スリナム", "SVK": "スロバキア",
    "SVN": "スロベニア", "SWE": "スウェーデン", "SWZ": "エスワティニ",
    "SYC": "セーシェル", "SYR": "シリア", "TCD": "チャド", "TGO": "トーゴ",
    "THA": "タイ", "TJK": "タジキスタン", "TKM": "トルクメニスタン",
    "TLS": "東ティモール", "TON": "トンガ", "TTO": "トリニダード・トバゴ",
    "TUN": "チュニジア", "TUR": "トルコ", "TUV": "ツバル", "TZA": "タンザニア",
    "UGA": "ウガンダ", "UKR": "ウクライナ", "URY": "ウルグアイ", "USA": "アメリカ合衆国",
    "UZB": "ウズベキスタン", "VCT": "セントビンセント・グレナディーン",
    "VEN": "ベネズエラ", "VNM": "ベトナム", "VUT": "バヌアツ", "WSM": "サモア",
    "YEM": "イエメン", "ZAF": "南アフリカ", "ZMB": "ザンビア", "ZWE": "ジンバブエ",
}


def fetch_un_members():
    """国連加盟193カ国の (iso3, iso2, 英語名, 日本語名) リストを返す。"""
    data = http_get_json(
        "https://query.wikidata.org/sparql?query="
        + urllib.parse.quote(WIKIDATA_SPARQL),
        headers={"Accept": "application/sparql-results+json"},
    )
    countries = {}
    for row in data["results"]["bindings"]:
        iso3 = row.get("iso3", {}).get("value", "")
        iso2 = row.get("iso2", {}).get("value", "")
        name_en = row["countryLabel"]["value"]
        if not iso3:
            # ISO3コードが無い項目は「過去に存在した国」等のノイズなので除外する
            # (ソ連・東ドイツ・チェコスロバキア等。現存する国には必ずISO3が付く)。
            continue
        countries[iso3] = {"iso3": iso3, "iso2": iso2, "nameEn": name_en}

    # デンマークだけ登録形式の違いで漏れるため、判明していれば手で補う。
    if "DNK" not in countries:
        countries["DNK"] = {"iso3": "DNK", "iso2": "DK", "nameEn": "Denmark"}

    if len(countries) != 193:
        raise RuntimeError(
            f"国連加盟国が193カ国ぴったりにならなかった({len(countries)}カ国)。"
            "Wikidata側のデータが変わった可能性があるので、生成を止めて確認が必要。"
        )

    # 日本語名の辞書と実データが完全に一致するか検証する(片方にしか無い国が
    # あると表示が壊れるため、ズレていたら早めに気づけるようにする)。
    missing_jp = sorted(set(countries) - set(JP_NAMES))
    extra_jp = sorted(set(JP_NAMES) - set(countries))
    if missing_jp or extra_jp:
        raise RuntimeError(
            f"日本語名の辞書とWikidataの結果がズレている。"
            f"辞書に無い国: {missing_jp} / 辞書にだけある国: {extra_jp}"
        )

    for iso3, jp in JP_NAMES.items():
        countries[iso3]["nameJa"] = jp

    return countries


# ---------------------------------------------------------------------------
# 2. 世界銀行APIから8要素分のデータを取得する
# ---------------------------------------------------------------------------
# 「全カ国分をまとめて1回のAPI呼び出しで取る」のがポイント。国ごとに呼ぶと
# 193カ国×8要素=1544回の通信になってしまうが、World Bankは
# `country/all/indicator/<コード>?mrv=1` で「全カ国分の最新値」を一括取得できる。
WORLD_BANK_ELEMENTS = [
    # (要素ID, 表示名, 世界銀行の指標コード, 単位表示)
    ("population", "人口", "SP.POP.TOTL", "人"),
    ("childRatio", "子どもの割合", "SP.POP.0014.TO.ZS", "%"),
    ("popGrowth", "人口増加率", "SP.POP.GROW", "%"),
    ("lifeExpectancy", "平均寿命", "SP.DYN.LE00.IN", "歳"),
    ("area", "面積", "AG.LND.TOTL.K2", "km²"),
    ("gdp", "GDP", "NY.GDP.MKTP.CD", "米ドル"),
    ("forestRatio", "森林の割合", "AG.LND.FRST.ZS", "%"),
    ("co2", "CO2排出量", "EN.GHG.CO2.MT.CE.AR5", "百万トン(CO2換算)"),
]


def fetch_world_bank_indicator(indicator_code, target_iso3s):
    """1つの指標について、対象カ国分の最新値を {iso3: (value, year)} で返す。

    まず「全カ国まとめて1回」の一括取得(高速)を試し、それで値が取れなかった
    国だけ、個別に(1カ国ずつ) mrv=1 で問い合わせて埋める。
    【判明した世界銀行APIの癖】全カ国一括+mrv=1の組み合わせだと、データが
    古い年で止まっている国(例:エリトリアのGDPは2011年が最新)の値が
    なぜか抜け落ちる。同じ国を1カ国だけで問い合わせると正しく2011年の値が
    返ってくるため、抜けた国だけ個別に問い合わせて補う2段構えにしている。
    """
    url = (
        "https://api.worldbank.org/v2/country/all/indicator/"
        f"{indicator_code}?format=json&mrv=1&per_page=400"
    )
    data = http_get_json(url)
    result = {}
    if len(data) >= 2 and data[1] is not None:
        for row in data[1]:
            iso3 = row.get("countryiso3code")
            value = row.get("value")
            year = row.get("date")
            if iso3 and value is not None:
                result[iso3] = (value, int(year))

    missing = [c for c in target_iso3s if c not in result]
    for iso3 in missing:
        try:
            single_url = (
                f"https://api.worldbank.org/v2/country/{iso3}/indicator/"
                f"{indicator_code}?format=json&mrv=1"
            )
            single_data = http_get_json(single_url, retries=2, timeout=15)
            if len(single_data) >= 2 and single_data[1]:
                row = single_data[1][0]
                if row.get("value") is not None:
                    result[iso3] = (row["value"], int(row["date"]))
        except Exception as e:  # noqa: BLE001
            print(f"  [警告] {iso3}/{indicator_code} の個別取得にも失敗: {e}")

    return result


# ---------------------------------------------------------------------------
# 3. countries.dev から「公用語の数」「隣接国の数」を取得する
# ---------------------------------------------------------------------------
# 当初はREST Countries(v5)を使う想定だったが、v5化に伴いAPIキー+アカウント登録
# (メール確認込み)が必須になった。今回はCEOが就寝中でメール確認の操作を代行
# できないため、【暫定判断】として同じ出典データ(REST Countriesの旧v2オープン
# データ)をキー不要で提供している非公式ミラー "countries.dev" を使う。
#   - 採用理由: 「陸続きの国境のみを隣接国として数える」という元のREST Countries
#     の定義を保っており(Wikidataの隣接国データは海の国境も混じり不正確だった
#     ため不採用にした経緯がある)、キー不要ですぐ使える。
#   - リスク: 非公式の第三者ミラーなので将来サービスが止まる可能性がある。ただし
#     このアプリはガチャのたびに通信せず、生成時に取得した値をアプリに埋め込む
#     方式なので、影響は「次回のデータ更新時にまた使えるか」だけに留まる。
#   - 次回データ更新時の推奨: 本家REST Countries(v5)のアカウント登録
#     (tker1996@gmail.com)をCEOにメール確認だけ済ませてもらい、以後はそちらの
#     公式APIに切り替えるのが望ましい。
REST_COUNTRIES_ALT_BASE = "https://countries.dev/alpha/"


def fetch_official_languages_and_borders(iso3_list):
    """{iso3: {"languages": int, "borders": int}} を返す。取得できなかった国は
    キーごと含めない(=その国のカードを作らない、という仕様どおりの挙動)。"""
    result = {}
    for i, iso3 in enumerate(iso3_list):
        try:
            data = http_get_json(REST_COUNTRIES_ALT_BASE + iso3, retries=2, timeout=15)
            languages = data.get("languages")
            borders = data.get("borders")
            entry = {}
            if isinstance(languages, list):
                entry["languages"] = len(languages)
            if isinstance(borders, list):
                entry["borders"] = len(borders)
            if entry:
                result[iso3] = entry
        except Exception as e:  # noqa: BLE001
            print(f"  [警告] {iso3} のcountries.dev取得に失敗、この国はスキップ: {e}")
        # 無料の非公式サービスに配慮し、少しだけ間隔をあける。
        if i % 20 == 19:
            time.sleep(0.3)
    return result


# ---------------------------------------------------------------------------
# 4. スコア化(0〜100点)とレア度の割り振り
# ---------------------------------------------------------------------------
# 【対数正規化】人口・面積・GDP・CO2排出量は、国によって桁が全然違う
# (人口が1億人の国と1万人の国が両方ある、など)。このまま0〜100点にすると
# 差が大きすぎる1〜2カ国だけが100点付近に張り付いてしまうため、log(対数)を
# 取ってから0〜100点に変換する(app_team_country_cards.mdの決定どおり)。
#
# 【線形正規化】子どもの割合・人口増加率・平均寿命・森林の割合・公用語の数・
# 隣接国の数は、%や年齢・個数といった「桁が大きく変わらない」数値で、
# 人口増加率のようにマイナス(人口減少)の国もある。対数はマイナスの数値に
# 使えないため、これらは単純に(値-最小値)/(最大値-最小値)×100の
# 線形正規化を使う。
#   ※ この「対数/線形の使い分け」は仕様書に明記が無かったため今回の
#     【暫定判断】。桁違いの差が出る要素だけ対数、というapp_team_country_cards.md
#     の趣旨(人口の例示)に沿った自然な拡張のつもり。
LOG_NORMALIZE_ELEMENTS = {"population", "area", "gdp", "co2"}


def normalize_scores(values_by_iso3, use_log):
    """{iso3: 生の値} を受け取り、{iso3: 0〜100点} を返す。"""
    if not values_by_iso3:
        return {}
    raw = values_by_iso3
    if use_log:
        # 0以下の値はlogが取れない。実際にナウルのCO2排出量が「0.0」で
        # 返ってくるケースがあるため、0や負の値は「データにある最小の正の値の
        # さらに1/10」という極小値に置き換えてからlogを取る(=そのカードは
        # 最下位スコア付近になる。カード自体を除外はしない)。
        positive_values = [v for v in raw.values() if v > 0]
        floor = (min(positive_values) * 0.1) if positive_values else 1e-9
        transformed = {k: math.log(v if v > 0 else floor) for k, v in raw.items()}
    else:
        transformed = dict(raw)
    lo = min(transformed.values())
    hi = max(transformed.values())
    scores = {}
    for iso3, v in transformed.items():
        if hi == lo:
            scores[iso3] = 50.0  # 全カ国同値という極端なケースの保険
        else:
            scores[iso3] = round((v - lo) / (hi - lo) * 100, 2)
    return scores


def assign_rarities(values_by_iso3):
    """生の値をもとに、値が「両端に近い(極端に大きい/極端に小さい)」ほど
    レア度が高くなるようにN/SR/SSR/URを割り振る。

    【暫定判断】app_team_country_cards.mdの分岐点6(レア度をどちらの端に
    付けるか)は文書内で「両端をレアにする」という案がCEOの他の了承事項と
    まとめて触れられているが、正式な最終決定の文言が見当たらなかったため、
    「面積最小のモナコもレアになる」という文書中の例に沿って両端レア方式を
    採用した。しきい値(上下3%をURにする、等)はゲームバランス調整の一環で
    今後いくらでも変更できるよう、この関数1箇所に閉じ込めてある。
    """
    items = sorted(values_by_iso3.items(), key=lambda kv: kv[1])
    n = len(items)
    rarities = {}
    for rank, (iso3, _value) in enumerate(items):
        # rank: 0(最小)〜n-1(最大)。percentileは0(最小)〜1(最大)。
        percentile = (rank + 0.5) / n
        extremity = abs(percentile - 0.5) * 2  # 0(中央)〜1(両端)
        if extremity >= 0.94:
            rarities[iso3] = "UR"
        elif extremity >= 0.80:
            rarities[iso3] = "SSR"
        elif extremity >= 0.55:
            rarities[iso3] = "SR"
        else:
            rarities[iso3] = "N"
    return rarities


# ---------------------------------------------------------------------------
# メイン処理
# ---------------------------------------------------------------------------

def main():
    print("[1/5] 国連加盟193カ国のリストをWikidataから取得中...")
    countries = fetch_un_members()
    print(f"      -> {len(countries)}カ国を確認")

    print("[2/5] 世界銀行APIから8要素分のデータを取得中(1要素=1回の通信)...")
    element_raw_values = {}  # element_id -> {iso3: (value, year)}
    for element_id, name_ja, code, unit in WORLD_BANK_ELEMENTS:
        wb_data = fetch_world_bank_indicator(code, countries.keys())
        # 国連加盟193カ国だけに絞り込む(世界銀行は地域集計や非加盟地域も含むため)。
        filtered = {iso3: v for iso3, v in wb_data.items() if iso3 in countries}
        element_raw_values[element_id] = filtered
        print(f"      - {name_ja}({code}): {len(filtered)}カ国分取得")

    print("[3/5] countries.devから公用語の数・隣接国の数を取得中(193カ国分、少し時間がかかる)...")
    rest_data = fetch_official_languages_and_borders(sorted(countries.keys()))
    lang_values = {iso3: d["languages"] for iso3, d in rest_data.items() if "languages" in d}
    border_values = {iso3: d["borders"] for iso3, d in rest_data.items() if "borders" in d}
    print(f"      - 公用語の数: {len(lang_values)}カ国分取得")
    print(f"      - 隣接国の数: {len(border_values)}カ国分取得(内陸国以外で0の国=島国等は正しく0件)")

    element_raw_values["officialLanguages"] = {
        iso3: (v, None) for iso3, v in lang_values.items()
    }
    element_raw_values["neighboringCountries"] = {
        iso3: (v, None) for iso3, v in border_values.items()
    }

    print("[4/5] スコア(0〜100点)とレア度を計算中...")
    ALL_ELEMENTS = WORLD_BANK_ELEMENTS + [
        ("officialLanguages", "公用語の数", None, "言語"),
        ("neighboringCountries", "隣接国の数", None, "カ国"),
    ]

    cards = []
    elements_meta = []
    for element_id, name_ja, _code, unit in ALL_ELEMENTS:
        raw = element_raw_values[element_id]
        values_only = {iso3: v for iso3, (v, _year) in raw.items()}
        scores = normalize_scores(values_only, use_log=element_id in LOG_NORMALIZE_ELEMENTS)
        rarities = assign_rarities(values_only)

        for iso3, (value, year) in raw.items():
            cards.append({
                "id": f"{iso3}_{element_id}",
                "iso3": iso3,
                "element": element_id,
                "value": value,
                "year": year,
                "score": scores[iso3],
                "rarity": rarities[iso3],
                "isSpecial": False,
            })

        elements_meta.append({
            "id": element_id,
            "nameJa": name_ja,
            "unit": unit,
            "cardCount": len(raw),
        })
        print(f"      - {name_ja}: {len(raw)}枚")

    # 特別カード「北朝鮮のGDP」(HUR、1枚のみ)。数値の代わりに「情報なし」を表示し、
    # 通常のGDPカード一覧には含めない(世界銀行にもGDPデータが無いことを逆手に取った演出)。
    cards.append({
        "id": "PRK_gdp_special",
        "iso3": "PRK",
        "element": "gdp",
        "value": None,
        "year": None,
        "score": 100.0,
        "rarity": "HUR",
        "isSpecial": True,
        "displayValueOverride": "情報なし",
    })
    print("      - GDP(特別カード「北朝鮮のGDP」): 1枚追加")

    output = {
        "generatedAt": time.strftime("%Y-%m-%d"),
        "worldBankLastUpdated": None,  # 世界銀行APIのレスポンスに含まれる更新日。下で埋める。
        "note": "国連加盟193カ国のみを対象にしています。データが無い国・要素の組み合わせにはカードがありません。",
        "elements": elements_meta,
        "countries": [
            {
                "iso3": c["iso3"],
                "iso2": c["iso2"],
                "nameJa": c["nameJa"],
                "nameEn": c["nameEn"],
                "flagCode": c["iso2"].lower(),
            }
            for c in sorted(countries.values(), key=lambda c: c["iso3"])
        ],
        "cards": cards,
    }

    # 世界銀行の「最終更新日」をメタ情報として残しておく(次回いつ更新すれば
    # よいかの目安になる。app_team_country_cards.mdの「データ更新の仕組み」参照)。
    try:
        meta = http_get_json(
            "https://api.worldbank.org/v2/country/JPN/indicator/SP.POP.TOTL?format=json&mrv=1"
        )
        output["worldBankLastUpdated"] = meta[0].get("lastupdated")
    except Exception:  # noqa: BLE001
        pass

    print(f"[5/5] JSONを書き出し中... -> {OUTPUT_PATH}")
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    total_cards = len(cards)
    print(f"完了。カード総数: {total_cards}枚 / 対象国: {len(countries)}カ国")


if __name__ == "__main__":
    main()
