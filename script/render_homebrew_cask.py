#!/usr/bin/env python3
"""Render the Homebrew cask for an exact GitHub release artifact."""

from __future__ import annotations

import argparse
import pathlib
import re


VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z.-]+)?$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def render(version: str, sha256: str) -> str:
    if not VERSION_PATTERN.fullmatch(version):
        raise ValueError("version must be a semantic version without a leading v")
    if not SHA256_PATTERN.fullmatch(sha256):
        raise ValueError("sha256 must be 64 lowercase hexadecimal characters")

    return f'''cask "aerospace-pilot" do
  version "{version}"
  sha256 "{sha256}"

  url "https://github.com/junderhill/aerospace-pilot/releases/download/v#{{version}}/AeroSpace-Pilot-#{{version}}.zip"
  name "AeroSpace Pilot"
  desc "Save, preview, and restore AeroSpace workspace layouts"
  homepage "https://junderhill.github.io/aerospace-pilot/"

  depends_on macos: :sonoma

  app "AeroSpace Pilot.app"

  caveats <<~EOS
    AeroSpace Pilot requires AeroSpace. Install it with:
      brew install --cask nikitabobko/tap/aerospace
  EOS
end
'''


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("sha256")
    parser.add_argument("output", type=pathlib.Path)
    arguments = parser.parse_args()

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(render(arguments.version, arguments.sha256), encoding="utf-8")


if __name__ == "__main__":
    main()
