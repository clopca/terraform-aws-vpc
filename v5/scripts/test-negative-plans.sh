#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

cd "$module_root"
terraform init -backend=false -input=false -test-directory=tests-negative >/dev/null

if terraform test -no-color -test-directory=tests-negative >"$log_file" 2>&1; then
  echo "Computed isolated route-table ID unexpectedly planned without explicit opt-in" >&2
  exit 1
fi

grep -Fq 'data "aws_route_table" "isolated_injected"' "$log_file"
grep -Fq 'Invalid for_each argument' "$log_file"

echo "Computed isolated route-table IDs fail closed without explicit opt-in"
