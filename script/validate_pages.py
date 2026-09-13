#!/usr/bin/env python3
"""Validate the static GitHub Pages output and its local references."""

from __future__ import annotations

import json
from html.parser import HTMLParser
import pathlib
import sys
from urllib.parse import unquote, urlsplit


class ReferenceParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.references: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        for attribute in ("href", "src"):
            value = values.get(attribute)
            if value:
                self.references.append(value)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} SITE_DIRECTORY")

    root = pathlib.Path(sys.argv[1]).resolve()
    index = root / "index.html"
    if not index.is_file():
        raise SystemExit("index.html is missing")

    parser = ReferenceParser()
    parser.feed(index.read_text(encoding="utf-8"))
    missing: list[str] = []
    for reference in parser.references:
        parsed = urlsplit(reference)
        if parsed.scheme or parsed.netloc or reference.startswith(("#", "mailto:")):
            continue
        target = root / unquote(parsed.path)
        if parsed.path and not target.exists():
            missing.append(reference)

    manifest = json.loads((root / "site.webmanifest").read_text(encoding="utf-8"))
    if manifest.get("name") != "AeroSpace Pilot":
        raise SystemExit("site.webmanifest has the wrong application name")
    if missing:
        raise SystemExit("Missing local references: " + ", ".join(sorted(set(missing))))

    print(f"Validated {len(parser.references)} page references")


if __name__ == "__main__":
    main()
