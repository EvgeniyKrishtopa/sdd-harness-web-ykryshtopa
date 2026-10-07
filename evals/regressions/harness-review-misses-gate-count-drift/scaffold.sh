#!/usr/bin/env bash
# The runner only accepts a scaffold_script inside the case directory, and
# it does not pass prompt.md's env to the scaffold. So this case names its
# defect here and hands off to the shared builder, where every planted
# defect stays readable in one place.
set -euo pipefail
EVAL_DEFECT=harness-config-drift exec bash "$(cd "$(dirname "$0")" && pwd)/../../support/make-repo.sh" "$@"
