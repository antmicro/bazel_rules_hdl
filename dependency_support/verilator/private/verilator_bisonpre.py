"""Run the upstream bisonpre script and only print output on failure."""

import os
import subprocess
import sys


def main() -> None:
    env = os.environ.copy()
    for name in (
        "RUNFILES_DIR",
        "RUNFILES_MANIFEST_FILE",
        "RUNFILES_MANIFEST_ONLY",
        "RUNFILES_REPO_MAPPING",
        "PYTHONSAFEPATH",
    ):
        env.pop(name, None)

    result = subprocess.run(
        [sys.executable] + sys.argv[1:],
        env=env,
        check=False,
        stderr=subprocess.STDOUT,
        stdout=subprocess.PIPE,
        encoding="utf-8",
    )
    if result.returncode:
        print(result.stdout, file=sys.stderr)
        sys.exit(result.returncode)


if __name__ == "__main__":
    main()
