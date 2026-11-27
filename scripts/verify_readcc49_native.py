#!/usr/bin/env python3
"""Retired MD5 importer acceptance entry point; never replays historical commits.

The added film/import feature was removed. A historical importer result cannot
establish a verdict for this source tree. Exit nonzero without producing an old
readcc49-native.json artifact or falling through to unrelated reading tests.
"""
import sys


def main():
    print(
        "RETIRED: Readcc49 MD5-import acceptance was removed with the added film feature; "
        "no historical commit was compiled and no native verdict was produced. "
        "Use current reading/music and film-removal regression suites instead.",
        file=sys.stderr,
    )
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
