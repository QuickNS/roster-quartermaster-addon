"""Build a deterministic runtime-only addon ZIP using the TOC as the allowlist."""

import argparse
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


def package(root: Path, output: Path, tag: str | None = None) -> Path:
    root = root.resolve()
    toc = root / "RosterQuartermaster.toc"
    text = toc.read_text(encoding="utf-8")
    match = re.search(r"^## Version: (\d+\.\d+\.\d+)$", text, re.MULTILINE)
    if not match:
        raise ValueError("TOC must contain a semantic version.")
    version = match.group(1)
    if tag is not None and tag != "v" + version:
        raise ValueError("Release tag does not match the TOC version.")
    namespace = (root / "Core/Namespace.lua").read_text(encoding="utf-8")
    if f'version = "{version}"' not in namespace:
        raise ValueError("Namespace and TOC versions differ.")
    paths = ["RosterQuartermaster.toc"]
    paths += [line.strip() for line in text.splitlines() if line.strip().endswith(".lua")]
    if len(paths) != len(set(paths)):
        raise ValueError("Duplicate TOC runtime entry.")
    content = {}
    for relative in paths:
        candidate = root / relative
        if (
            "\\" in relative
            or Path(relative).is_absolute()
            or ".." in Path(relative).parts
            or candidate.is_symlink()
            or not candidate.resolve().is_relative_to(root)
            or not candidate.is_file()
        ):
            raise ValueError(f"Unsafe or missing runtime entry: {relative}")
        content[relative] = candidate.read_bytes()
    destination = output.resolve()
    if destination == root or destination.suffix != ".zip":
        raise ValueError("Output must be a ZIP file.")
    if destination in {(root / path).resolve() for path in paths} or output.is_symlink():
        raise ValueError("Output cannot alias runtime input or be a symlink.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".tmp")
    # Exclusive creation avoids following a pre-existing temporary file/symlink.
    created = False
    try:
        with temporary.open("xb") as stream:
            created = True
            with ZipFile(stream, "w", compression=ZIP_DEFLATED) as archive:
                for relative, data in sorted(content.items()):
                    info = ZipInfo("RosterQuartermaster/" + relative, (2020, 1, 1, 0, 0, 0))
                    info.compress_type = ZIP_DEFLATED
                    info.external_attr = 0o100644 << 16
                    archive.writestr(info, data)
        temporary.replace(destination)
    finally:
        if created:
            temporary.unlink(missing_ok=True)
    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tag")
    args = parser.parse_args()
    try:
        print(package(args.root, args.output, args.tag))
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Package failed: {exc}\n")


if __name__ == "__main__":
    main()
