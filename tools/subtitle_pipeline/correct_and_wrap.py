#!/usr/bin/env python3
"""
字幕パイプライン ステップ3+4+5:誤字直し(用語集参照)→ 改行・区切り → SRT出力

入力:transcribe_align.py が書き出した中間JSON(*.aligned.json)
出力:
  - <out>.srt          … 完成候補の字幕ファイル
  - <out>.corrected.json … 修正後テキスト+タイムスタンプ(次工程/検証用)

このスクリプトが自動でやること:
  - 用語集(youtube_team_glossary.md)の「誤認識しやすい例」に完全一致する箇所を正しい表記に置換
  - 「うつ」のひらがな統一
  - フィラー(まあ、あのー等)の削除
  - BudouX(Google製の日本語分かち書き・改行位置推定ツール)で文節相当の塊に分割し、
    その塊の境界でだけ改行・字幕を区切る(単語・文節の途中で割らない)
  - 1字幕2行以内に収める(収まらない場合は複数の字幕に分割)
  - 字幕の開始時刻を、実際にその字幕の最初の文字を話し始めた時刻(WhisperXアライメント結果)に
    正確に合わせる(機械的な一定間隔ではない)
  - 字幕同士が時間的に重ならないようにする

このスクリプトが自動でやらないこと(人:Claudeが目視で仕上げる前提):
  - 用語集に載っていない誤字・言い回しの整形(「言い直しの整理」「文脈的な言い換え」等)
  - 意味の切れ目の最終判断(BudouXは文節の塊は分かるが「文章として意味が完結したか」の
    判断はできないため、機械的な文字数だけで区切ると不自然になる箇所が残り得る)
  → そのため、このスクリプトの出力は「完成候補」であり、そのまま最終稿として使う前に
    人(Claude)がガイドライン(youtube_team.md)と読み合わせて仕上げる工程を必ず挟むこと。
"""
from __future__ import annotations
import argparse
import difflib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glossary_lib import (parse_glossary, build_substitution_map, normalize_utsu,
                           strip_fillers)

import budoux

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_GLOSSARY = REPO_ROOT / "youtube_team_glossary.md"

MAX_CHARS_PER_LINE = 18   # 1行あたりの目安文字数(全角)。youtube_team.mdに数値指定は無いため
                          # 一般的なYouTube字幕の可読性目安(全角18〜20字/行)を採用。
MAX_LINES = 2
MIN_CUE_DURATION = 0.6    # 短すぎる字幕(誤爆)を避けるための最低表示時間(秒)
GAP_BETWEEN_CUES = 0.05   # 字幕同士が重ならないようにするための最小間隔(秒)


def apply_corrections(text: str, chars: list[dict], sub_map: dict[str, str]) -> tuple[str, list[dict]]:
    """用語集の置換・うつのひらがな統一・フィラー除去を適用し、
    置換後テキストの各文字に対応するタイムスタンプをdifflibで可能な限り引き継ぐ。
    (置換で増減した部分は前後の実測タイムスタンプから線形補間する)
    """
    original = text
    corrected = original
    for wrong, right in sub_map.items():
        corrected = corrected.replace(wrong, right)
    corrected = normalize_utsu(corrected)
    corrected = strip_fillers(corrected)

    # original(=chars由来の文字列)と corrected を文字単位でdiffし、
    # 一致部分はそのままタイムスタンプを引き継ぎ、置換/追加部分は前後の時刻から補間する。
    orig_chars_str = "".join(c["char"] for c in chars) if chars else original
    sm = difflib.SequenceMatcher(a=orig_chars_str, b=corrected, autojunk=False)
    result_chars: list[dict | None] = [None] * len(corrected)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                if i1 + k < len(chars):
                    result_chars[j1 + k] = chars[i1 + k]
    # 補間:Noneの箇所を前後の既知タイムスタンプで埋める
    n = len(result_chars)
    for j in range(n):
        if result_chars[j] is not None:
            continue
        # 直前の既知
        prev = next(((k, result_chars[k]) for k in range(j - 1, -1, -1) if result_chars[k]), None)
        nxt = next(((k, result_chars[k]) for k in range(j + 1, n) if result_chars[k]), None)
        if prev and nxt:
            pk, pv = prev
            nk, nv = nxt
            span = nk - pk
            ratio = (j - pk) / span if span else 0.5
            start = pv["end"] + (nv["start"] - pv["end"]) * ratio
        elif prev:
            start = prev[1]["end"]
        elif nxt:
            start = nxt[1]["start"]
        else:
            start = 0.0
        end = start + 0.05
        result_chars[j] = {"char": corrected[j], "start": round(start, 3), "end": round(end, 3), "score": 0.0}
    return corrected, result_chars  # type: ignore[return-value]


def budoux_chunks(text: str, parser) -> list[str]:
    """BudouXで文節相当の塊に分割する。句読点はBudouXの塊にそのまま含まれる。"""
    chunks = [c for c in parser.parse(text) if c]
    return _merge_unsplittable(chunks)


# BudouXの塊分割が細かすぎて、そのまま改行位置に使うと不自然な割れ方になるケースへの補正。
# youtube_team.mdの「助詞の「と」と単語の先頭の「と」を混同しないこと」の例と同種の問題
# (「〜という」「〜ていただく」等の機能的な続き言葉が単独の塊として孤立し、
#  それを改行位置に使うと文節の途中で割れたように見える)。
# → これらの塊は必ず直前の塊にくっつけ、単独で行頭に来ないようにする。
_BOUND_CONTINUATION_RE = re.compile(
    r"^(という|といった|っていう|いうの|いうこと|いうよう|ていただ|させていただ|"
    r"ておりま|おります|おりまし|ています|てくれ|てもらい|てもらう|でした|"
    r"ください|くださっ|んですけど|んですが)"
)
# 逆に、指示語(この/その/あの/どの等)だけの短い塊が行末に孤立して残るのを防ぐため、
# これらは直後の塊にくっつけて「指示語+直後の名詞」を1つの塊として扱う。
_DEMONSTRATIVE_RE = re.compile(r"^(この|その|あの|どの|これ|それ|あれ|どれ)$")


def _merge_unsplittable(chunks: list[str]) -> list[str]:
    if not chunks:
        return chunks
    # 1st pass: 機能的な続き言葉を直前の塊へ吸収
    merged: list[str] = []
    for c in chunks:
        if merged and _BOUND_CONTINUATION_RE.match(c):
            merged[-1] += c
        else:
            merged.append(c)
    # 2nd pass: 孤立しやすい指示語を直後の塊へ吸収(後ろから走査して結合)
    result: list[str] = []
    i = 0
    while i < len(merged):
        c = merged[i]
        if _DEMONSTRATIVE_RE.match(c) and i + 1 < len(merged):
            result.append(c + merged[i + 1])
            i += 2
        else:
            result.append(c)
            i += 1
    return result


def pack_chunks_into_cues(chunks: list[str], chars: list[dict]) -> list[dict]:
    """BudouXの塊を、1字幕=最大2行・1行MAX_CHARS_PER_LINE文字以内になるよう
    貪欲法(greedy)でまとめ、字幕(cue)のリストを作る。塊の内部では絶対に改行・分割しない。
    各cueは {"lines": [str, str?], "start": float, "end": float} を返す。
    """
    cues: list[dict] = []
    lines: list[str] = []
    cur_line = ""
    char_cursor = 0        # chunks を消費した文字数(=charsに対するオフセット)。今のchunkを含まない位置
    cue_start_idx = 0      # 今のcueの最初の文字のchars上のインデックス

    def make_cue(end_idx: int) -> dict | None:
        if not lines:
            return None
        start_t = chars[cue_start_idx]["start"] if cue_start_idx < len(chars) else 0.0
        end_t = chars[end_idx - 1]["end"] if 0 < end_idx <= len(chars) else start_t + 1.0
        return {"lines": lines[:MAX_LINES], "start": start_t, "end": end_t}

    for chunk in chunks:
        chunk_len = len(chunk)
        if len(cur_line) + chunk_len <= MAX_CHARS_PER_LINE:
            cur_line += chunk
            char_cursor += chunk_len
            continue
        # 今の行がいっぱいなので確定し、このchunkは次の行の先頭にする
        # (chunkの内部では絶対に改行しない=分割しない)
        if cur_line:
            lines.append(cur_line)
        cur_line = chunk
        if len(lines) >= MAX_LINES:
            # 2行分すでに確定済み → ここまでを1つのcueとして確定し、
            # 今回のchunk(=次の行の先頭)から新しいcueを開始する
            cue = make_cue(char_cursor)
            if cue:
                cues.append(cue)
            lines = []
            cue_start_idx = char_cursor
        char_cursor += chunk_len

    if cur_line:
        lines.append(cur_line)
    cue = make_cue(char_cursor)
    if cue:
        cues.append(cue)
    return cues


SENTENCE_END_RE = re.compile(r"(?<=[。!?])")


def split_into_sentences(text: str, chars: list[dict]) -> list[tuple[str, list[dict]]]:
    """句点(。!?)で文単位に分割する(「意味の完結点で必ず区切る」ルールに対応)。
    1セグメント(VADの無音区切り)内に複数文が入っている場合に、文の切れ目でも
    字幕を分けられるようにするため。
    """
    if not text:
        return []
    parts = [p for p in SENTENCE_END_RE.split(text) if p]
    result = []
    offset = 0
    for p in parts:
        result.append((p, chars[offset:offset + len(p)]))
        offset += len(p)
    return result


def build_srt(cues: list[dict]) -> str:
    def fmt(t: float) -> str:
        if t < 0:
            t = 0.0
        h = int(t // 3600)
        m = int((t % 3600) // 60)
        s = int(t % 60)
        ms = int(round((t - int(t)) * 1000))
        if ms == 1000:
            ms = 0
            s += 1
        return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

    out = []
    for i, cue in enumerate(cues, start=1):
        out.append(str(i))
        out.append(f"{fmt(cue['start'])} --> {fmt(cue['end'])}")
        out.extend(cue["lines"])
        out.append("")
    return "\n".join(out)


def enforce_no_overlap_and_min_duration(cues: list[dict]) -> list[dict]:
    for i, cue in enumerate(cues):
        if cue["end"] - cue["start"] < MIN_CUE_DURATION:
            cue["end"] = cue["start"] + MIN_CUE_DURATION
    for i in range(len(cues) - 1):
        if cues[i]["end"] > cues[i + 1]["start"] - GAP_BETWEEN_CUES:
            cues[i]["end"] = max(cues[i]["start"] + 0.2, cues[i + 1]["start"] - GAP_BETWEEN_CUES)
    return cues


def main():
    global MAX_CHARS_PER_LINE
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("aligned_json", type=Path)
    ap.add_argument("out_prefix", type=Path)
    ap.add_argument("--glossary", type=Path, default=DEFAULT_GLOSSARY)
    ap.add_argument("--max-chars-per-line", type=int, default=MAX_CHARS_PER_LINE)
    args = ap.parse_args()

    MAX_CHARS_PER_LINE = args.max_chars_per_line

    data = json.loads(args.aligned_json.read_text(encoding="utf-8"))
    glossary_entries = parse_glossary(args.glossary)
    sub_map = build_substitution_map(glossary_entries)

    parser = budoux.load_default_japanese_parser()

    all_cues: list[dict] = []
    corrected_segments_out = []
    for seg in data["segments"]:
        corrected_text, corrected_chars = apply_corrections(seg["text"], seg.get("chars", []), sub_map)
        corrected_segments_out.append({"id": seg["id"], "text": corrected_text})
        for sent_text, sent_chars in split_into_sentences(corrected_text, corrected_chars):
            sent_text_stripped = sent_text.strip()
            if not sent_text_stripped:
                continue
            chunks = budoux_chunks(sent_text, parser)
            cues = pack_chunks_into_cues(chunks, sent_chars)
            all_cues.extend(cues)

    all_cues = enforce_no_overlap_and_min_duration(all_cues)

    srt_text = build_srt(all_cues)
    srt_path = args.out_prefix.with_suffix(".srt")
    srt_path.write_text(srt_text, encoding="utf-8")

    corrected_path = args.out_prefix.with_suffix(".corrected.json")
    corrected_path.write_text(json.dumps({
        "segments": corrected_segments_out,
        "cues": all_cues,
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"[wrap] wrote {srt_path} ({len(all_cues)} cues)", file=sys.stderr)
    print(f"[wrap] wrote {corrected_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
