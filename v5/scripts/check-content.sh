#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if grep -RInE --exclude='.terraform.lock.hcl' --exclude='check-content.sh' 'air-gapped|master map|dynamodb:\*' "$repo_root/v5"; then
  echo "Banned security or non-inclusive example wording found" >&2
  exit 1
fi

grep -Fq 'dynamodb:GetItem' "$repo_root/v5/examples/basic/main.tf"
grep -Fq 'arn:aws:dynamodb:us-east-1:123456789012:table/application-data' "$repo_root/v5/examples/basic/main.tf"
