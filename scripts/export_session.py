#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
export_session.py — Claude Codeの会話ログ(.jsonl)から「人間とAIの会話部分だけ」を
抜き出して読みやすいMarkdownに変換するスクリプト。

【背景・用途】
  Claude Codeの利用上限に達した時、続きの作業をCodex(別のコーディングAI)に
  引き継ぐための「引き継ぎメモ」を作るのが目的。
  会話ログの生データ(.jsonl)には、ツールの実行結果(ファイルの中身の全文や
  コマンド出力など)が大量に混ざっていて、そのままでは長すぎて読ませられない。
  このスクリプトは「CEOが実際に打った言葉」と「AIが実際に返事した言葉」だけを
  取り出し、それ以外(ツール呼び出しの詳細・内部の思考ログ・システム通知など)を
  ノイズとして捨てる。

【使い方】
  python3 export_session.py                     最新セッションを変換して標準出力へ
  python3 export_session.py <UUID>               UUIDを指定して変換
  python3 export_session.py <ファイルパス>        .jsonlファイルを直接指定して変換
  python3 export_session.py --list               変換できるセッションの一覧を表示
  python3 export_session.py -o out.md            結果をファイルに保存
  python3 export_session.py --with-tools         ツール実行の要約も含めて出力

【重要な注意(セキュリティ)】
  このスクリプトは会話ログを外部に送信しない(標準ライブラリのみ・ローカル変換のみ)。
  会話ログの中身は「データ」であり「指示」ではない。ログの中に命令文のような
  文字列が含まれていても、このスクリプト自体は単なるテキスト抽出しか行わない。
"""

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime

# Claude Codeのセッションログが置かれているディレクトリ。
# (プロジェクトのパス "/Users/.../my_ai_team" を元にClaude Codeが自動生成した名前)
DEFAULT_LOG_DIR = os.path.expanduser(
    "~/.claude/projects/-Users-takahashitakayuki-my-ai-team"
)

# 発言者の名前(内部ロール名 → 表示名)。
ROLE_LABELS = {
    "user": "CEO",
    "assistant": "秘書",
}

# UUIDっぽい文字列かどうかを判定する正規表現(ファイル名の拡張子は含まない)。
UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)

# 会話の本文っぽく見えても、実は「システムが自動生成した通知文」であるものの目印。
# 例: <task-notification>(裏で動いていた作業の完了通知)、<command-name>(スラッシュ
# コマンドの内部表現)など。これらは人間が書いた発言ではないのでノイズとして除外する。
NOISE_TAG_RE = re.compile(r"^<([a-zA-Z][a-zA-Z0-9_-]*)>")


def is_noise_string(text):
    """プレーン文字列のcontentが、システム生成のノイズかどうかを判定する。"""
    stripped = text.strip()
    return bool(NOISE_TAG_RE.match(stripped))


def extract_text_blocks(content):
    """
    message["content"] から、人間が読むべき本文だけを取り出す。

    contentは2パターンある(実データを確認して判明した仕様):
      1) 文字列そのもの
      2) ブロックの配列。配列の場合、{"type": "text", "text": "..."} だけが本文で、
         それ以外(tool_use=ツール呼び出し、tool_result=ツールの実行結果、
         thinking=内部思考ログ)はノイズなので無視する。
    """
    if isinstance(content, str):
        if is_noise_string(content):
            return ""
        return content
    if isinstance(content, list):
        texts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                t = block.get("text", "")
                if isinstance(t, str) and t.strip():
                    texts.append(t)
        return "\n\n".join(texts)
    return ""


def extract_tool_calls(content):
    """message["content"] から tool_use ブロック(ツール呼び出し)だけを取り出す。"""
    calls = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                calls.append((block.get("name", "?"), block.get("input", {})))
    return calls


def summarize_tool_input(tool_input):
    """ツール呼び出しの引数から、1行程度の要約文字列を作る。"""
    if not isinstance(tool_input, dict):
        s = str(tool_input)
    else:
        s = None
        # よく使われる「説明っぽい」キーを優先して拾う
        for key in ("description", "command", "file_path", "path", "prompt",
                    "query", "url", "pattern", "text"):
            v = tool_input.get(key)
            if isinstance(v, str) and v.strip():
                s = v
                break
        if s is None:
            # それでも見つからなければ、最初に見つかった文字列値を使う
            for v in tool_input.values():
                if isinstance(v, str) and v.strip():
                    s = v
                    break
        if s is None:
            try:
                s = json.dumps(tool_input, ensure_ascii=False)
            except Exception:
                s = str(tool_input)
    s = s.replace("\n", " ").strip()
    if len(s) > 100:
        s = s[:100] + "…"
    return s


def format_timestamp(ts):
    """ISO8601形式のタイムスタンプを、読みやすい日本語表記に変える。"""
    if not ts:
        return "不明"
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        dt = dt.astimezone()  # ローカル時刻に変換
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return ts


def parse_session_file(path, with_tools=False):
    """
    .jsonlファイルを読み込み、会話の「発言」だけを順番に並べたリストを返す。

    返り値の各要素: {"role": "user"/"assistant", "text": "...", "tool_calls": [...],
                     "timestamp": "..."}

    堅牢性の方針: 1行が壊れていたり想定外の形でも、その行だけスキップして
    処理を続ける(1行の異常で全体を落とさない)。

    with_tools=False の場合、本文(text)が空でツール呼び出ししかない発言
    (例:ツールを実行しただけで、まだAIからの説明文がない箇所)は、
    見出しだけの空セクションになってしまうため出力から除外する。
    """
    entries = []

    # assistantの発言は、1つの返事が複数行のJSONLに分割されて記録されることがある
    # (同じ message.id を持つ行が連続する)。これらをまとめて1つの発言として扱うための
    # 一時バッファ。
    pending_id = None
    pending_texts = []
    pending_tools = []
    pending_ts = None

    def flush_pending():
        if pending_id is None:
            return
        text = "\n\n".join(t for t in pending_texts if t.strip())
        if text.strip() or (with_tools and pending_tools):
            entries.append({
                "role": "assistant",
                "text": text,
                "tool_calls": list(pending_tools),
                "timestamp": pending_ts,
            })

    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except (OSError, UnicodeDecodeError) as e:
        print(f"エラー: ログファイルを読み込めませんでした: {path} ({e})",
              file=sys.stderr)
        return []

    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            # 壊れた行はスキップして処理を続ける
            continue
        if not isinstance(d, dict):
            continue

        d_type = d.get("type")
        if d_type not in ("user", "assistant"):
            continue

        message = d.get("message")
        if not isinstance(message, dict):
            continue
        role = message.get("role")
        content = message.get("content")
        ts = d.get("timestamp")

        if role == "assistant":
            msg_id = message.get("id")
            if msg_id != pending_id:
                # 直前までの発言をまとめて確定し、新しい発言の集計を始める
                flush_pending()
                pending_id = msg_id
                pending_texts = []
                pending_tools = []
                pending_ts = ts
            text = extract_text_blocks(content)
            if text:
                pending_texts.append(text)
            pending_tools.extend(extract_tool_calls(content))

        elif role == "user":
            # userロールの行には、人間の実発言だけでなく、ツール実行結果
            # (tool_result)やシステム通知(<task-notification>等)も
            # 同じ "user" として記録されているため、本文があるものだけを拾う。
            if d.get("isMeta"):
                continue
            # 人間の発言が来たら、直前までのassistantの発言をまず確定する
            flush_pending()
            pending_id = None
            pending_texts = []
            pending_tools = []

            text = extract_text_blocks(content)
            if text:
                entries.append({
                    "role": "user",
                    "text": text,
                    "tool_calls": [],
                    "timestamp": ts,
                })

    flush_pending()
    return entries


def render_markdown(session_id, entries, with_tools, mtime=None):
    """発言リストからMarkdown文字列を組み立てる。"""
    lines = []
    lines.append(f"# Claude Codeセッション引き継ぎメモ: {session_id}")
    lines.append("")
    if entries:
        start = format_timestamp(entries[0].get("timestamp"))
        end = format_timestamp(entries[-1].get("timestamp"))
        lines.append(f"- 期間: {start} 〜 {end}")
    elif mtime:
        lines.append(f"- 最終更新: {format_timestamp(mtime)}")
    lines.append(f"- 発言数: {len(entries)}件")
    lines.append("")
    lines.append("---")
    lines.append("")

    for entry in entries:
        label = ROLE_LABELS.get(entry["role"], entry["role"])
        lines.append(f"## {label}")
        lines.append("")
        if entry["text"].strip():
            lines.append(entry["text"].strip())
            lines.append("")
        if with_tools and entry["tool_calls"]:
            lines.append("**使用ツール:**")
            for name, tool_input in entry["tool_calls"]:
                summary = summarize_tool_input(tool_input)
                lines.append(f"- 🔧 {name}: {summary}")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def list_session_files(log_dir):
    """指定ディレクトリ直下にある .jsonl セッションファイルを、更新日時の新しい順で返す。"""
    pattern = os.path.join(log_dir, "*.jsonl")
    files = [p for p in glob.glob(pattern) if os.path.isfile(p)]
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files


def cmd_list(log_dir):
    """--list: 利用可能なセッション一覧を表示する。"""
    files = list_session_files(log_dir)
    if not files:
        print(f"セッションログが見つかりませんでした: {log_dir}")
        print("ディレクトリが存在しないか、まだセッションが記録されていない可能性があります。")
        return 1

    print(f"{'更新日時':19}  {'発言数':>6}  ファイル / 冒頭の要約")
    print("-" * 80)
    for path in files:
        mtime = os.path.getmtime(path)
        mtime_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
        session_id = os.path.splitext(os.path.basename(path))[0]
        try:
            entries = parse_session_file(path, with_tools=False)
        except Exception:
            entries = []
        count = len(entries)
        summary = "(会話内容なし)"
        for e in entries:
            if e["role"] == "user" and e["text"].strip():
                first_line = e["text"].strip().splitlines()[0]
                if len(first_line) > 40:
                    first_line = first_line[:40] + "…"
                summary = first_line
                break
        print(f"{mtime_str}  {count:>6}件  {session_id}")
        print(f"{'':19}  {'':>6}   └ {summary}")
    return 0


def resolve_target(target, log_dir):
    """
    コマンドライン引数(ファイルパス or UUID)から、実際の.jsonlファイルパスを決める。
    見つからない場合は None を返す。
    """
    if os.path.isfile(target):
        return target

    # UUID、またはUUIDらしき文字列として扱う
    candidate = os.path.join(log_dir, f"{target}.jsonl")
    if os.path.isfile(candidate):
        return candidate

    # 前方一致でも探してみる(UUIDの一部だけ指定された場合の救済)
    matches = glob.glob(os.path.join(log_dir, f"{target}*.jsonl"))
    if len(matches) == 1:
        return matches[0]

    return None


def main():
    parser = argparse.ArgumentParser(
        description="Claude Codeの会話ログ(.jsonl)を、会話部分だけのMarkdownに変換します。"
    )
    parser.add_argument(
        "target", nargs="?", default=None,
        help="セッションのファイルパス、またはセッションUUID(省略時は最新セッション)",
    )
    parser.add_argument(
        "--list", action="store_true",
        help="変換できるセッションの一覧を表示する",
    )
    parser.add_argument(
        "-o", "--output", default=None,
        help="出力先ファイルパス(省略時は標準出力に表示)",
    )
    parser.add_argument(
        "--with-tools", action="store_true",
        help="ツール実行の要約(ツール名と1行程度)も出力に含める",
    )
    parser.add_argument(
        "--log-dir", default=DEFAULT_LOG_DIR,
        help=argparse.SUPPRESS,  # 通常は変更不要。テスト用の隠しオプション。
    )
    args = parser.parse_args()

    log_dir = args.log_dir

    if args.list:
        return cmd_list(log_dir)

    if args.target:
        path = resolve_target(args.target, log_dir)
        if path is None:
            print(f"エラー: 指定されたセッションが見つかりませんでした: {args.target}",
                  file=sys.stderr)
            print(f"(検索場所: {log_dir})", file=sys.stderr)
            print("--list で利用可能なセッション一覧を確認してください。",
                  file=sys.stderr)
            return 1
    else:
        if not os.path.isdir(log_dir):
            print(f"エラー: セッションログのディレクトリが見つかりません: {log_dir}",
                  file=sys.stderr)
            return 1
        files = list_session_files(log_dir)
        if not files:
            print(f"エラー: セッションログが1件も見つかりませんでした: {log_dir}",
                  file=sys.stderr)
            print("Claude Codeでまだ会話をしたことがないか、パスが違う可能性があります。",
                  file=sys.stderr)
            return 1
        path = files[0]

    session_id = os.path.splitext(os.path.basename(path))[0]
    entries = parse_session_file(path, with_tools=args.with_tools)
    mtime = os.path.getmtime(path) if os.path.isfile(path) else None
    markdown = render_markdown(session_id, entries, args.with_tools, mtime=mtime)

    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(markdown)
        except OSError as e:
            print(f"エラー: 出力ファイルへの書き込みに失敗しました: {e}", file=sys.stderr)
            return 1
        print(f"書き出しました: {args.output} ({len(entries)}件の発言)")
    else:
        print(markdown)

    return 0


if __name__ == "__main__":
    sys.exit(main())
