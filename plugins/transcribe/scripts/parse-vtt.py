#!/usr/bin/env python3
"""Parse a WebVTT caption file into plain text, collapsing YouTube's rolling-window duplication.

Env:
  VTT_PATH   path to .vtt file
  OUT_PATH   path to write plain-text output
"""
import os
import re
import html
import sys

vtt_path = os.environ.get("VTT_PATH")
out_path = os.environ.get("OUT_PATH")
if not vtt_path or not out_path:
    print("VTT_PATH and OUT_PATH required", file=sys.stderr)
    sys.exit(1)

with open(vtt_path, encoding="utf-8", errors="replace") as f:
    raw = f.read()

raw = re.sub(r"^WEBVTT.*?\n\n", "", raw, count=1, flags=re.S)

lines = []
seen_tail = ""

for block in raw.split("\n\n"):
    block = block.strip()
    if not block:
        continue
    text_lines = []
    for ln in block.splitlines():
        if "-->" in ln:
            continue
        if re.match(r"^\d+$", ln.strip()):
            continue
        ln = re.sub(r"<[^>]+>", "", ln)
        ln = html.unescape(ln).strip()
        if ln:
            text_lines.append(ln)
    if not text_lines:
        continue
    text = " ".join(text_lines)
    if text == seen_tail:
        continue
    if seen_tail:
        max_overlap = min(len(seen_tail), len(text))
        overlap = 0
        for k in range(max_overlap, 0, -1):
            if seen_tail.endswith(text[:k]):
                overlap = k
                break
        if overlap:
            text = text[overlap:].lstrip()
        if not text:
            continue
    lines.append(text)
    seen_tail = (seen_tail + " " + text).strip()[-200:]

with open(out_path, "w", encoding="utf-8") as f:
    f.write(" ".join(lines).strip())
