"""
用語集(youtube_team_glossary.md)と要点メモ(youtube_team_episode_notes_XX.md)を
読み込むための共通ヘルパー。

用語集のMarkdown表は「正しい表記 | 読み方 | AIが誤認識しやすい例 | 補足」の
形式の表(パイプ区切りMarkdown table)を想定している。表の書式が多少変わっても
崩れないよう、緩めのパースにしている。
"""
from __future__ import annotations
import re
from pathlib import Path
from dataclasses import dataclass, field


@dataclass
class GlossaryEntry:
    correct: str
    reading: str = ""
    mis_examples: list[str] = field(default_factory=list)
    note: str = ""


def _split_row(line: str) -> list[str]:
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def _is_separator_row(cells: list[str]) -> bool:
    return all(re.fullmatch(r"-{2,}", c) for c in cells if c)


def parse_glossary(path: str | Path) -> list[GlossaryEntry]:
    """youtube_team_glossary.md のMarkdown表をすべて読み取り、GlossaryEntryのリストにする。"""
    text = Path(path).read_text(encoding="utf-8")
    entries: list[GlossaryEntry] = []
    header_cells: list[str] | None = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line.startswith("|"):
            header_cells = None
            continue
        cells = _split_row(line)
        if _is_separator_row(cells):
            continue
        if header_cells is None:
            header_cells = cells
            continue
        if len(cells) < 2 or not cells[0] or cells[0] in ("---",):
            continue
        # 表は「正しい表記 | 読み方 | 誤認識例 | 補足」または「正しい表記 | 読み方 | 補足」の2パターンがある
        correct = cells[0]
        reading = cells[1] if len(cells) > 1 else ""
        if len(cells) >= 4:
            mis_raw = cells[2]
            note = cells[3]
        elif len(cells) == 3:
            mis_raw = ""
            note = cells[2]
        else:
            mis_raw = ""
            note = ""
        mis_examples = []
        for m in re.findall(r"「([^」]+)」", mis_raw):
            mis_examples.append(m)
        entries.append(GlossaryEntry(correct=correct, reading=reading,
                                      mis_examples=mis_examples, note=note))
    return entries


def build_substitution_map(entries: list[GlossaryEntry]) -> dict[str, str]:
    """『AIが誤認識しやすい例』に挙がっている誤変換文字列 → 正しい表記、の辞書を作る。
    完全一致の誤変換例(「子宮頸部に行きました」等)のみを対象にした単純な文字列置換。
    文脈判断が必要な修正はこの辞書だけではカバーしきれないため、
    別途このパイプラインを回す人(Claude)が目視でも確認すること。
    """
    subs: dict[str, str] = {}
    for e in entries:
        for mis in e.mis_examples:
            if mis and mis != e.correct:
                subs[mis] = e.correct
    return subs


UTSU_PATTERN = re.compile(r"[鬱欝]")


def normalize_utsu(text: str) -> str:
    """『うつ』は必ずひらがな表記に統一するルールを適用する。"""
    return UTSU_PATTERN.sub("うつ", text)


# 字幕から削除するフィラー(内容を持たない口癖)。
# youtube_team.md「字幕の分け方」参照。文中・文頭どちらでも削除できるよう正規表現で用意。
FILLER_PATTERNS = [
    r"あのー+",
    r"あの[ー、]",
    r"えーと+",
    r"えーっと+",
    r"まぁ",
    r"まあ",
    r"なんて言うんでしょうね",
    r"なんていうんでしょう",
    r"そうですね(?=[、。]|$)",
]
FILLER_RE = re.compile("|".join(FILLER_PATTERNS))


def strip_fillers(text: str) -> str:
    out = FILLER_RE.sub("", text)
    # フィラー除去で生まれた不自然な重複読点・空白を整理
    out = re.sub(r"、{2,}", "、", out)
    out = re.sub(r"^、", "", out)
    out = re.sub(r"\s{2,}", " ", out)
    return out


def parse_episode_notes(path: str | Path) -> str:
    """要点メモファイルをそのままテキストとして返す(用語ヒント・アドリブ範囲の参考情報として
    修正時にプロンプト/参照に使うだけなので、厳密な構造パースはしない)。"""
    p = Path(path)
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8")


if __name__ == "__main__":
    import sys
    entries = parse_glossary(sys.argv[1] if len(sys.argv) > 1 else
                              str(Path(__file__).resolve().parents[2] / "youtube_team_glossary.md"))
    for e in entries:
        print(e)
    print("---substitution map---")
    print(build_substitution_map(entries))
