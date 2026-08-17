#!/usr/bin/env python3
"""Check that every app ARB's @@locale matches its filename.

Flutter's gen-l10n refuses to generate localizations when app_<code>.arb
declares an @@locale that differs from <code>, which fails `flutter pub get`
and breaks every build. Crowdin writes the full regional code ("es-ES") into
@@locale while naming files with the two-letter code, so the two drift apart
on translation syncs.

Run with no arguments to check, or --fix to rewrite @@locale to match the
filename. Exits non-zero when a mismatch remains.
"""

import argparse
import json
import pathlib
import re
import sys

ARB_DIR = pathlib.Path(__file__).resolve().parent.parent / "app" / "lib" / "l10n"
FILENAME_RE = re.compile(r"^app_(?P<code>[A-Za-z0-9_-]+)\.arb$")


def check(fix: bool) -> int:
    files = sorted(ARB_DIR.glob("app_*.arb"))
    if not files:
        print(f"error: no ARB files found in {ARB_DIR}", file=sys.stderr)
        return 1

    failures = []
    for path in files:
        match = FILENAME_RE.match(path.name)
        if not match:
            failures.append(f"{path.name}: unexpected filename shape")
            continue
        expected = match.group("code")

        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            failures.append(f"{path.name}: invalid JSON ({exc})")
            continue

        actual = data.get("@@locale")
        if actual == expected:
            continue

        if fix and actual is not None:
            # Rewrite in place rather than re-serializing, so translator-facing
            # formatting and key order survive untouched.
            text = path.read_text(encoding="utf-8")
            patched = text.replace(
                f'"@@locale": {json.dumps(actual)}',
                f'"@@locale": {json.dumps(expected)}',
                1,
            )
            if patched != text:
                path.write_text(patched, encoding="utf-8")
                print(f"fixed {path.name}: {actual!r} -> {expected!r}")
                continue

        failures.append(
            f"{path.name}: @@locale is {actual!r} but the filename says {expected!r}"
        )

    if failures:
        print("ARB locale check failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        print(
            "\nFlutter's gen-l10n requires @@locale to match the filename; "
            "otherwise `flutter pub get` exits 1.\n"
            "Run `python3 scripts/check_arb_locales.py --fix` to correct them.",
            file=sys.stderr,
        )
        return 1

    print(f"ARB locale check passed ({len(files)} files).")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fix",
        action="store_true",
        help="rewrite @@locale to match the filename instead of only reporting",
    )
    sys.exit(check(parser.parse_args().fix))
