#!/usr/bin/env python3
"""app_strings.dart から Glossary.gs を生成する。"""

from __future__ import annotations

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
STRINGS = ROOT / "lib" / "l10n" / "app_strings.dart"
OUT = pathlib.Path(__file__).resolve().parent / "Glossary.gs"

HAS_JA = re.compile(r"[\u3040-\u30ff\u3400-\u9fff]")


def unescape(s: str) -> str:
    return (
        s.replace(r"\'", "'")
        .replace(r"\\", "\\")
        .replace(r"\n", "\n")
        .replace(r"\t", "\t")
    )


def parse_map(src: str, const_name: str) -> dict[str, str]:
    marker = f"static const {const_name} = <String, String>{{"
    start = src.index(marker) + len(marker)
    depth = 1
    i = start
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    body = src[start : i - 1]
    entries: dict[str, str] = {}
    key = None
    parts: list[str] = []
    for m in re.finditer(r"'((?:\\'|[^'])*)'", body):
        token = unescape(m.group(1))
        after = body[m.end() :].lstrip()
        if key is None:
            key = token
            parts = []
            continue
        parts.append(token)
        if after.startswith(","):
            entries[key] = "".join(parts)
            key = None
            parts = []
    return entries


def js_escape(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )


def emit_obj(mapping: dict[str, str]) -> str:
    lines = ["{"]
    for ja, tr in sorted(mapping.items(), key=lambda x: x[0]):
        lines.append(f'  "{js_escape(ja)}": "{js_escape(tr)}",')
    lines.append("};")
    return "\n".join(lines)


def main() -> None:
    src = STRINGS.read_text(encoding="utf-8")
    ja = parse_map(src, "_ja")
    en = parse_map(src, "_en")
    vi = parse_map(src, "_vi")

    g_en: dict[str, str] = {}
    g_vi: dict[str, str] = {}
    for key, ja_text in ja.items():
        if not HAS_JA.search(ja_text):
            continue
        if key in en and en[key] != ja_text:
            g_en[ja_text] = en[key]
        if key in vi and vi[key] != ja_text:
            g_vi[ja_text] = vi[key]

    extras_en = {
        "操作マニュアル": "User manual",
        "図解で画面ごとの使い方を見る": "Illustrated guide for each screen",
        "osmWashabe？": "osmWashabe?",
    }
    extras_vi = {
        "操作マニュアル": "Hướng dẫn sử dụng",
        "図解で画面ごとの使い方を見る": "Xem cách dùng từng màn hình bằng hình",
        "osmWashabe？": "osmWashabe?",
    }
    g_en.update(extras_en)
    g_vi.update(extras_vi)

    out = (
        "/** アプリ用語の固定訳。完全一致を優先し、残りは機械翻訳。 */\n\n"
        "var GLOSSARY_VI = "
        + emit_obj(g_vi)
        + "\n\nvar GLOSSARY_EN = "
        + emit_obj(g_en)
        + "\n"
    )
    OUT.write_text(out, encoding="utf-8")
    print(f"wrote {OUT} ({len(g_en)} EN, {len(g_vi)} VI)")


if __name__ == "__main__":
    main()
