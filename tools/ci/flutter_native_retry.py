#!/usr/bin/env python3
"""Retry a failed, checksum-verified SQLite download, never a failed test.

The sqlite3 Dart hook verifies its downloaded library against a digest shipped
in the package. A transient bad response can leave a corrupt shared hook cache.
This runner removes only that generated SQLite cache and retries the original
command, with the original integrity check still in force. A persistent digest
mismatch and every other failure stay red.

Usage: python3 tools/ci/flutter_native_retry.py -- flutter test ...
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


SQLITE_HASH_FAILURE = re.compile(
    r"Hash of downloaded file (?:lib)?sqlite3\.[^\s]+ is [0-9a-f]{64}, "
    r"expected [0-9a-f]{64}",
    re.IGNORECASE,
)


def is_retryable(log: str) -> bool:
    return (
        SQLITE_HASH_FAILURE.search(log) is not None
        and "Building native assets failed" in log
        and "Some tests failed" not in log
    )


def discard_sqlite_hook_cache(project: Path) -> list[Path]:
    """Discard only reproducible SQLite outputs inside this checkout."""
    project = project.resolve()
    hooks = project / ".dart_tool" / "hooks_runner"
    discarded = []
    for relative in (Path("shared/sqlite3"), Path("sqlite3")):
        target = hooks / relative
        # Never follow a generated-directory symlink into a different checkout
        # or into the package cache. Keep unrelated packages' outputs intact.
        if not target.exists() or target.is_symlink():
            continue
        if not target.resolve().is_relative_to(project):
            continue
        shutil.rmtree(target)
        discarded.append(target)
    return discarded


def run(command: list[str], *, attempts: int = 3, delay: float = 2) -> int:
    for attempt in range(1, attempts + 1):
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
            )
        except OSError as error:
            print(f"Could not start command: {error}", file=sys.stderr)
            return 127
        output = []
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="", flush=True)
            output.append(line)
        status = process.wait()
        if status == 0 or not is_retryable("".join(output)):
            return status
        if attempt == attempts:
            print(
                "SQLite download still fails its published checksum; "
                "the integrity gate remains failed.",
                file=sys.stderr,
            )
            return status
        discarded = discard_sqlite_hook_cache(Path.cwd())
        print(
            f"SQLite native download failed its checksum. Removed "
            f"{len(discarded)} generated cache directories; retrying "
            f"({attempt + 1}/{attempts}) with verification enabled.",
            file=sys.stderr,
            flush=True,
        )
        time.sleep(delay)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--attempts", type=int, default=3, choices=range(1, 4))
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("supply the original command after --")
    return run(command, attempts=args.attempts)


if __name__ == "__main__":
    raise SystemExit(main())
