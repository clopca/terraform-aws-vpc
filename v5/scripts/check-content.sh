#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if grep -RInE --exclude='.terraform.lock.hcl' --exclude='check-content.sh' 'air-gapped|master map|dynamodb:\*' "$repo_root/v5"; then
  echo "Banned security or non-inclusive example wording found" >&2
  exit 1
fi


if grep -RInE --exclude-dir='.git' --exclude-dir='.terraform' --exclude='check-content.sh' \
  '3\.21\.81\.83|172\.2\.0\.(192|208|224)|2a05:d01c:bc3|2600:1f18:4200|079f76df39be519c9|0ae0e24ffe193f2a1|076e272ecaff6fce0|063181ad924968f92|04a86315c4839b519|0b9b71f291529d9fe|0fde39f9550f4abb5' \
  "$repo_root"; then
  echo "Non-documentation IP address or captured resource ID found" >&2
  exit 1
fi
grep -Fq 'dynamodb:GetItem' "$repo_root/v5/examples/basic/main.tf"
grep -Fq 'arn:aws:dynamodb:us-east-1:123456789012:table/application-data' "$repo_root/v5/examples/basic/main.tf"

grep -Fq '`subnets[*].route_table_key` is also immutable Terraform' "$repo_root/v5/.header.md"
grep -Fq 'module.vpc.aws_vpc_endpoint_route_table_association.gateway["injected/edge-old/gateway-endpoint/s3"]' "$repo_root/v5/.header.md"
