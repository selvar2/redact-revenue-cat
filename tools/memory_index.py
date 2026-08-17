#!/usr/bin/env python3
"""Memory retrieval index for the Redact project vault.

Chunks every Markdown note under docs/ by heading, builds a BM25 keyword index,
and answers queries with ranked, source-cited excerpts.

Why stdlib-only: this index must still work in two years with no API key, no
network, and no dependency that has rotted. Retrieval quality matters less than
the index existing at all when a cold session needs it.

Usage:
    python3 tools/memory_index.py build
    python3 tools/memory_index.py query "why regex for PAN"
    python3 tools/memory_index.py query "redaction" --phase 1 --top 3
"""

import argparse
import json
import math
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
INDEX_PATH = os.path.join(DOCS, "memory-index.json")

# BM25 tuning. k1 controls term-frequency saturation, b controls length
# normalisation. These are the standard defaults and have not needed tuning.
K1 = 1.5
B = 0.75

STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "if", "then", "than", "so", "of", "to",
    "in", "on", "at", "for", "with", "by", "from", "is", "are", "was", "were",
    "be", "been", "it", "its", "this", "that", "these", "those", "as", "we",
    "i", "you", "he", "she", "they", "not", "no", "do", "does", "did", "can",
}

TOKEN_RE = re.compile(r"[a-z0-9_]+")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
WIKILINK_RE = re.compile(r"\[\[([^\]]+)\]\]")


def tokenize(text):
    """Lowercase, split on non-word chars, drop stopwords and 1-char noise."""
    return [t for t in TOKEN_RE.findall(text.lower())
            if t not in STOPWORDS and len(t) > 1]


def parse_frontmatter(lines):
    """Extract a flat YAML frontmatter block. Deliberately minimal: we only
    need scalar and inline-list values, so a real YAML parser is overkill."""
    meta = {}
    if not lines or lines[0].strip() != "---":
        return meta, lines
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return meta, lines[i + 1:]
        if ":" in line:
            key, _, value = line.partition(":")
            value = value.strip()
            if value.startswith("[") and value.endswith("]"):
                value = [v.strip().strip("\"'")
                         for v in value[1:-1].split(",") if v.strip()]
            meta[key.strip()] = value
    return meta, lines


def chunk_file(path):
    """Split one note into chunks at heading boundaries.

    Heading-level chunking beats fixed-size windows here because these notes are
    written to a known template — the headings *are* the semantic boundaries.
    """
    with open(path, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()

    meta, body = parse_frontmatter(lines)
    rel = os.path.relpath(path, ROOT)

    chunks = []
    heading = os.path.basename(path)
    buffer = []
    line_start = 1

    def flush(end_line):
        text = "\n".join(buffer).strip()
        if text:
            chunks.append({
                "file": rel,
                "heading": heading,
                "line": line_start,
                "text": text,
                "meta": meta,
                "links": WIKILINK_RE.findall(text),
            })

    for offset, line in enumerate(body, start=1):
        match = HEADING_RE.match(line)
        if match:
            flush(offset)
            heading = match.group(2).strip()
            buffer = []
            line_start = offset
        else:
            buffer.append(line)
    flush(len(body))
    return chunks


def build():
    chunks = []
    for dirpath, dirnames, filenames in os.walk(DOCS):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in sorted(filenames):
            if name.endswith(".md"):
                chunks.extend(chunk_file(os.path.join(dirpath, name)))

    if not chunks:
        print("No markdown found under docs/. Nothing to index.")
        return

    doc_freq = Counter()
    for chunk in chunks:
        tokens = tokenize(chunk["text"] + " " + chunk["heading"])
        chunk["tf"] = dict(Counter(tokens))
        chunk["len"] = len(tokens)
        for term in set(tokens):
            doc_freq[term] += 1

    total = len(chunks)
    avg_len = sum(c["len"] for c in chunks) / total

    index = {
        "version": 1,
        "chunk_count": total,
        "avg_len": avg_len,
        "doc_freq": dict(doc_freq),
        "chunks": chunks,
    }
    with open(INDEX_PATH, "w", encoding="utf-8") as handle:
        json.dump(index, handle)

    print("Indexed {} chunks from {} notes -> {}".format(
        total,
        len({c["file"] for c in chunks}),
        os.path.relpath(INDEX_PATH, ROOT),
    ))


def score(chunk, terms, doc_freq, total, avg_len):
    """Standard BM25. IDF is floored at 0 so a term appearing in every chunk
    contributes nothing rather than going negative."""
    result = 0.0
    for term in terms:
        freq = chunk["tf"].get(term, 0)
        if not freq:
            continue
        n_q = doc_freq.get(term, 0)
        idf = max(0.0, math.log((total - n_q + 0.5) / (n_q + 0.5) + 1.0))
        norm = freq * (K1 + 1) / (
            freq + K1 * (1 - B + B * chunk["len"] / avg_len)
        )
        result += idf * norm
    return result


def query(text, top, phase, tag):
    if not os.path.exists(INDEX_PATH):
        print("No index yet. Run: python3 tools/memory_index.py build")
        sys.exit(1)

    with open(INDEX_PATH, "r", encoding="utf-8") as handle:
        index = json.load(handle)

    terms = tokenize(text)
    if not terms:
        print("Query had no searchable terms after stopword removal.")
        sys.exit(1)

    candidates = index["chunks"]
    if phase is not None:
        candidates = [c for c in candidates
                      if str(c["meta"].get("phase", "")) == str(phase)]
    if tag:
        candidates = [c for c in candidates if tag in (c["meta"].get("tags") or [])]

    ranked = sorted(
        ((score(c, terms, index["doc_freq"], index["chunk_count"],
                index["avg_len"]), c) for c in candidates),
        key=lambda pair: pair[0],
        reverse=True,
    )
    hits = [(s, c) for s, c in ranked if s > 0][:top]

    if not hits:
        print("No matches for: {}".format(text))
        return

    for rank, (value, chunk) in enumerate(hits, start=1):
        print("\n{}. {}  [{}:{}]  score={:.2f}".format(
            rank, chunk["heading"], chunk["file"], chunk["line"], value))
        body = chunk["text"]
        print("   " + (body[:400] + "…" if len(body) > 400 else body).replace("\n", "\n   "))
        if chunk["links"]:
            print("   related: " + " ".join("[[{}]]".format(l) for l in chunk["links"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("build", help="rebuild the index from docs/")

    q = sub.add_parser("query", help="search project memory")
    q.add_argument("text", help="what you want to know")
    q.add_argument("--top", type=int, default=5)
    q.add_argument("--phase", default=None, help="filter by phase number")
    q.add_argument("--tag", default=None, help="filter by frontmatter tag")

    args = parser.parse_args()
    if args.command == "build":
        build()
    else:
        query(args.text, args.top, args.phase, args.tag)


if __name__ == "__main__":
    main()
