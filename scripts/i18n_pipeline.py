#!/usr/bin/env python3
"""One-shot i18n refresh: extract → html scan → js scan → augment → inject.

Run after any UI change. Designed to be called from the Makefile
(`make i18n`) and from CI. Exits non-zero if missing strings remain
after the augment pass — that means a new TR string was hardcoded with
no curated translation and the EN_FALLBACK path was taken; the
maintainer should add an explicit translation to
scripts/i18n_translate.py (and i18n_augment.py for TR→EN) before
merging.
"""
from __future__ import annotations
import subprocess
import sys


def run(name):
    print(f"\n── {name} ──")
    r = subprocess.run([sys.executable, f"scripts/{name}.py"])
    return r.returncode


def main():
    rc = 0
    rc |= run("i18n_extract") << 0
    rc |= run("i18n_html_scan") << 1
    rc |= run("i18n_js_scan") << 2
    rc |= run("i18n_augment") << 3
    rc |= run("i18n_inject") << 4
    print(f"\nPipeline finished, composite rc={rc}")
    sys.exit(0 if rc == 0 else 1)


if __name__ == "__main__":
    main()
