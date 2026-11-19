#!/usr/bin/env python3
"""Install this checkout's Chalk Assist files; Python standard library only."""

import argparse
import os
from pathlib import Path
import sys
import tempfile


MAIN_FILE = "chalk-it-up-1v1.lua"
AUTOEXEC_LOADER = "chalk-it-up-loader.lua"
PUBLIC_AUTOEXEC_LOADER = "chalk-autoexec-public.lua"


def folder(value):
    """Resolve aliases before comparing the source and destination folders."""
    result = Path(value).expanduser().resolve()
    if result.exists() and not result.is_dir():
        raise ValueError(f"Not a folder: {result}")
    return result


def check_target(destination, source=None):
    if destination.is_symlink():
        raise ValueError(f"Destination must not be a symbolic link: {destination}")
    if destination.exists() and not destination.is_file():
        raise ValueError(f"Destination is not a regular file: {destination}")
    if source is not None and destination.exists() and os.path.samefile(source, destination):
        raise ValueError(f"Source and destination are the same file: {destination}")


def atomic_write(destination, content, mode):
    """Prepare beside the destination, then replace without a partial file."""
    fd, temporary = tempfile.mkstemp(prefix=".chalk-install-", dir=str(destination.parent))
    temporary = Path(temporary)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.chmod(temporary, mode)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", required=True, help="Executor workspace folder")
    parser.add_argument("--autoexec", help="Optional executor autoexec folder")
    parser.add_argument("--autoexec-source", choices=("public", "local"), default="public",
                        help="Public downloads the latest published build with cache fallback; local pins the installed copy")
    parser.add_argument("--dry-run", action="store_true", help="Check paths and list actions without writing")
    args = parser.parse_args(argv)

    try:
        source_folder = Path(__file__).resolve().parent
        workspace = folder(args.workspace)
        autoexec = folder(args.autoexec) if args.autoexec else None
        if workspace == source_folder or autoexec == source_folder:
            raise ValueError("Use executor folders outside the repository folder")
        if autoexec is not None and autoexec == workspace:
            raise ValueError("Workspace and autoexec must be different folders")
        # Generated executor state belongs outside the checkout, including any
        # nested folder that could otherwise be committed by mistake.
        for target_folder in (workspace, autoexec):
            if target_folder is not None and source_folder in target_folder.parents:
                raise ValueError("Use executor folders outside the repository folder")

        copies = [(source_folder / MAIN_FILE, workspace / MAIN_FILE)]
        if autoexec is not None:
            loader = PUBLIC_AUTOEXEC_LOADER if args.autoexec_source == "public" else AUTOEXEC_LOADER
            copies.append((source_folder / loader, autoexec / AUTOEXEC_LOADER))
        prepared = []
        for source, destination in copies:
            if not source.is_file():
                raise ValueError(f"Required repository file is missing: {source.name}")
            check_target(destination, source)
            prepared.append((destination, source.read_bytes()))
        if args.dry_run:
            for destination, _ in prepared:
                print(f"Would install: {destination}")
            print("Dry run complete; no files changed.")
            return 0

        workspace.mkdir(parents=True, exist_ok=True)
        if autoexec is not None:
            autoexec.mkdir(parents=True, exist_ok=True)
        for destination, content in prepared:
            check_target(destination)
            atomic_write(destination, content, 0o644)
        print(f"Installed Chalk Assist in {workspace}; existing ciu_* settings preserved.")
        if autoexec is not None:
            print(f"{args.autoexec_source.title()} autoexec loader installed in {autoexec}.")
        print('Run locally: loadstring(readfile("chalk-it-up-1v1.lua"))()')
        return 0
    except (OSError, ValueError) as error:
        print(f"Install failed: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Install cancelled.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
