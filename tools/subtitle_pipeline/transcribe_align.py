#!/usr/bin/env python3
"""
字幕パイプライン ステップ1+2:文字起こし(whisper.cpp)→ 時刻補正(WhisperX)

役割:
  1. whisper.cpp(large-v3、VAD付き)で音声を文字起こしし、無音区間で自然に区切られた
     「文単位」のセグメントをもらう(mechanicalな3秒区切りにしない)
  2. その各セグメントの文字を、WhisperX(日本語アライメントモデル)で音声と突き合わせ、
     「1文字ずつ」の正確な開始・終了時刻(±0.2秒程度)を得る
  3. 結果を中間フォーマット(JSON)として保存する。後続の処理(誤字直し・改行・SRT化)は
     すべてこの中間JSONだけを見て動くので、将来ステップ1を有料クラウド文字起こしに
     差し替える場合も、この中間JSONと同じ形を吐き出せば後続はそのまま使える。

中間フォーマット(*.aligned.json):
{
  "audio_path": "...",
  "segments": [
    {
      "id": 0,
      "start": 2.24, "end": 3.84,      # whisper.cppのセグメント境界(参考値)
      "text": "はじめまして、こたろうと申します。",
      "chars": [
        {"char": "は", "start": 0.15, "end": 0.23, "score": 0.65},
        ...
      ]
    }, ...
  ]
}

使い方:
  video_venv/bin/python3 transcribe_align.py <入力wav> <出力prefix> [--language ja] [--model <ggml-model.bin>]
"""
from __future__ import annotations
import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]  # ~/my_ai_team
DEFAULT_WHISPER_CLI = REPO_ROOT / "tools/whisper.cpp/build/bin/whisper-cli"
DEFAULT_MODEL = REPO_ROOT / "tools/whisper.cpp/models/ggml-large-v3.bin"
DEFAULT_VAD_MODEL = REPO_ROOT / "tools/whisper.cpp/models/for-tests-silero-v6.2.0-ggml.bin"


def run_whisper_cpp(wav_path: Path, out_prefix: Path, language: str,
                     model: Path, whisper_cli: Path, vad_model: Path,
                     use_vad: bool = True) -> Path:
    """whisper.cppを実行し、full JSON(-ojf)を書き出す。返り値はJSONファイルのパス。"""
    cmd = [
        str(whisper_cli),
        "-m", str(model),
        "-f", str(wav_path),
        "-l", language,
        "-oj", "-ojf",
        "-of", str(out_prefix),
        "-pp",
    ]
    if use_vad and vad_model.exists():
        cmd += ["--vad", "--vad-model", str(vad_model)]
    print("[transcribe] running:", " ".join(cmd), file=sys.stderr)
    subprocess.run(cmd, check=True)
    json_path = out_prefix.with_suffix(".json")
    if not json_path.exists():
        # whisper.cppは "<prefix>.json" ではなく "<out_prefix>.json" を作る想定だが、
        # -of に拡張子が付いていた場合のフォールバック
        candidates = list(out_prefix.parent.glob(out_prefix.name + "*.json"))
        if candidates:
            json_path = candidates[0]
    return json_path


def whisper_cpp_json_to_segments(json_path: Path) -> list[dict]:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    segments = []
    for i, seg in enumerate(data.get("transcription", [])):
        text = seg["text"].strip()
        if not text:
            continue
        start_ms = seg["offsets"]["from"]
        end_ms = seg["offsets"]["to"]
        segments.append({
            "id": i,
            "start": start_ms / 1000.0,
            "end": end_ms / 1000.0,
            "text": text,
        })
    return segments


def align_with_whisperx(wav_path: Path, segments: list[dict], language: str,
                         device: str = "cpu") -> list[dict]:
    import whisperx  # 遅延import(このスクリプトのhelpだけ見たい時にtorch読み込みを避ける)

    print("[align] loading WhisperX alignment model for language=", language, file=sys.stderr)
    model_a, metadata = whisperx.load_align_model(language_code=language, device=device)
    audio = whisperx.load_audio(str(wav_path))

    # whisperx.align()はsegmentに"start"/"end"/"text"のリストを要求する
    wx_input = [{"start": s["start"], "end": s["end"], "text": s["text"]} for s in segments]
    result = whisperx.align(wx_input, model_a, metadata, audio, device,
                             return_char_alignments=True)

    aligned_segments = []
    for seg_idx, seg in enumerate(result["segments"]):
        orig = segments[seg_idx]
        chars = []
        # return_char_alignments=Trueの場合 seg["chars"] に1文字ずつのタイムスタンプが入る
        for c in seg.get("chars", []):
            if c.get("start") is None:
                continue
            chars.append({
                "char": c["char"],
                "start": round(float(c["start"]), 3),
                "end": round(float(c["end"]), 3),
                "score": round(float(c.get("score", 0.0)), 3),
            })
        # WhisperXが一部のセグメントでアライメントに失敗する(backtrack failed)ことがあり、
        # その場合 chars が空になる。空のままだと後続処理(誤字直し・改行)が
        # タイムスタンプ0にフォールバックして字幕の時刻がずれるため、
        # ここでwhisper.cpp側の区間(start〜end)に均等割りした仮のタイムスタンプを補う。
        if not chars and orig["text"]:
            n = len(orig["text"])
            dur = max(orig["end"] - orig["start"], 0.01)
            step = dur / n
            for i, ch in enumerate(orig["text"]):
                chars.append({
                    "char": ch,
                    "start": round(orig["start"] + i * step, 3),
                    "end": round(orig["start"] + (i + 1) * step, 3),
                    "score": 0.0,
                })
            print(f"[align] WARNING: segment {orig['id']} had no char alignment; "
                  f"using evenly-spaced fallback timestamps within [{orig['start']}, {orig['end']}]",
                  file=sys.stderr)
        aligned_segments.append({
            "id": orig["id"],
            "start": orig["start"],
            "end": orig["end"],
            "text": orig["text"],
            "chars": chars,
        })
    return aligned_segments


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("wav_path", type=Path, help="入力音声(wav推奨、16kHz mono)")
    ap.add_argument("out_prefix", type=Path, help="出力ファイルの接頭辞(例: output/3156)")
    ap.add_argument("--language", default="ja")
    ap.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    ap.add_argument("--whisper-cli", type=Path, default=DEFAULT_WHISPER_CLI)
    ap.add_argument("--vad-model", type=Path, default=DEFAULT_VAD_MODEL)
    ap.add_argument("--no-vad", action="store_true")
    ap.add_argument("--skip-align", action="store_true", help="WhisperXをスキップしwhisper.cppの結果のみ出力(動作確認用)")
    args = ap.parse_args()

    args.out_prefix.parent.mkdir(parents=True, exist_ok=True)

    json_path = run_whisper_cpp(args.wav_path, args.out_prefix, args.language,
                                 args.model, args.whisper_cli, args.vad_model,
                                 use_vad=not args.no_vad)
    segments = whisper_cpp_json_to_segments(json_path)
    print(f"[transcribe] {len(segments)} segments from whisper.cpp", file=sys.stderr)

    if args.skip_align:
        aligned = [{**s, "chars": []} for s in segments]
    else:
        aligned = align_with_whisperx(args.wav_path, segments, args.language)

    out_path = args.out_prefix.with_suffix(".aligned.json")
    out_path.write_text(json.dumps({
        "audio_path": str(args.wav_path),
        "segments": aligned,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[align] wrote {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
