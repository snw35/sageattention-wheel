import os
import pathlib
import re
import sys


def main() -> int:
    version = os.environ.get("SAGE_VERSION")
    suffix = os.environ.get("SAGE_CUDA_SUFFIX")
    if not version:
        return 0
    if suffix:
        version = f"{version}+{suffix}"

    path = pathlib.Path("setup.py")
    text = path.read_text()
    new_text, count = re.subn(
        r"version\s*=\s*['\"][^'\"]+['\"]",
        f"version='{version}'",
        text,
        count=1,
    )
    if count == 0:
        raise SystemExit("Unable to find version= in setup.py for patching")
    path.write_text(new_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
