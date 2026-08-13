#!/usr/bin/env bash
set -euo pipefail

fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/fixtures/migration-v5-production" && pwd)"

terraform -chdir="$fixture_dir" init -backend=false -input=false -lockfile=readonly >/dev/null
terraform -chdir="$fixture_dir" test -no-color
