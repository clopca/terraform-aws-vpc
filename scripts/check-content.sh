#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if grep -RInE --exclude='.terraform.lock.hcl' --exclude='check-content.sh' --exclude-dir='.git' --exclude-dir='.terraform' 'air-gapped|master map|dynamodb:\*' "$repo_root"; then
  echo "Banned security or non-inclusive example wording found" >&2
  exit 1
fi


if grep -RInE --exclude-dir='.git' --exclude-dir='.terraform' --exclude='check-content.sh' \
  '3\.21\.81\.83|172\.2\.0\.(192|208|224)|2a05:d01c:bc3|2600:1f18:4200|079f76df39be519c9|0ae0e24ffe193f2a1|076e272ecaff6fce0|063181ad924968f92|04a86315c4839b519|0b9b71f291529d9fe|0fde39f9550f4abb5' \
  "$repo_root"; then
  echo "Non-documentation IP address or captured resource ID found" >&2
  exit 1
fi
grep -Fq 'dynamodb:GetItem' "$repo_root/examples/basic/main.tf"
grep -Fq 'arn:aws:dynamodb:us-east-1:123456789012:table/application-data' "$repo_root/examples/basic/main.tf"

grep -Fq '`subnets[*].route_table_key` is also immutable Terraform' "$repo_root/.header.md"
grep -Fq 'module.vpc.aws_vpc_endpoint_route_table_association.gateway["injected/edge-old/gateway-endpoint/s3"]' "$repo_root/.header.md"

grep -Fq 'version = ">= 6.29, < 7.0"' "$repo_root/.header.md"
grep -Fq '**Cost warning:** applying this quick start creates a public NAT Gateway' "$repo_root/.header.md"
grep -Fq '## 6. Future work / deferred scope' "$repo_root/docs/rfc/v5-contract.md"
if grep -Fq 'Phase 5 gate pending' "$repo_root/docs/rfc/v5-contract.md" || grep -Fq 'Future Work (TODO)' "$repo_root/docs/rfc/v5-contract.md"; then
  echo "Stale RFC status wording found" >&2
  exit 1
fi

grep -Fq 'nat_gateways = map(object({' "$repo_root/.header.md"
grep -Fq 'ids = list(string) # exclusive alternative to names/count' "$repo_root/.header.md"
grep -Fq 'Both families support N entries' "$repo_root/.header.md"
grep -Fq 'VPC IPv6 is `/44` through `/60` in `/4` increments' "$repo_root/.header.md"
grep -Fq '`ipv6.secondary_cidr_key` is required' "$repo_root/.header.md"
grep -Fq '`vpc_ipv6_cidr_blocks` and' "$repo_root/.header.md"
if grep -RIn --exclude='check-content.sh' --exclude-dir='.git' --exclude-dir='.terraform' 'Complete dual-stack and IPv6-native topology' "$repo_root"; then
  echo "Overbroad IPv6 completeness claim found" >&2
  exit 1
fi

grep -Fq 'core_network_options.dns_support = optional(bool, false)' "$repo_root/.header.md"
grep -Fq 'core_network_options.security_group_referencing_support = optional(bool, true)' "$repo_root/.header.md"
grep -Fq 'core_network_options.routing_policy_label = optional(string)' "$repo_root/.header.md"
grep -Fq 'nat_gateway.eip.ipam_pool_id = optional(string)' "$repo_root/.header.md"

# Upstream-facing files must not expose internal review labels, local paths, or
# private build-process vocabulary.
if git -C "$repo_root" grep -nEiI \
  '\[(R[0-9]+-)?[CHMLF][-_]?[0-9]+[^]]*\]|\[Finding[ :#-]*[0-9]+[^]]*\]|remedia(cion|tion)-[0-9]+|rehearsal #[0-9]+|Builder: Agent|/Users/clopca/|/tmp/|internal migration RFC' \
  -- . ':(exclude)scripts/check-content.sh'; then
  echo "Internal review label, process wording, or local path found" >&2
  exit 1
fi

grep -Fq '# AWS VPC Module' "$repo_root/README.md"
grep -Fq '[5.0 upgrade guide](docs/UPGRADE-GUIDE-5.0.md)' "$repo_root/README.md"
grep -Fq 'source  = "aws-ia/vpc/aws"' "$repo_root/README.md"
grep -Fq '`subnets[*].routing.nat_gateway_key`' "$repo_root/.header.md"
grep -Fq '`addressing.secondary[*].ipv6.network_border_group`' "$repo_root/.header.md"
grep -Fq 'the single placement dimension for Regional Availability Zones' "$repo_root/.header.md"
grep -Fq 'vpc_ipv6_cidr_blocks' "$repo_root/examples/dual_stack/outputs.tf"
grep -Fq 'transit_gateway_attachment_ids["vpc"]' "$repo_root/docs/UPGRADE-GUIDE-5.0.md"
grep -Fq 'transit_gateway_attachment_ids["vpc"]' "$repo_root/docs/rfc/v5-migration.md"
for runbook in hub ipam nat_byoip; do
  case "$runbook" in
    hub) var_file=hub.tfvars ;;
    ipam) var_file=ipam.tfvars ;;
    nat_byoip) var_file=nat-byoip.tfvars ;;
  esac
  grep -Fq "terraform plan -out=tfplan -var-file=$var_file" "$repo_root/examples/$runbook/README.md"
  grep -Fq 'terraform apply tfplan' "$repo_root/examples/$runbook/README.md"
  grep -Fq "terraform destroy -var-file=$var_file" "$repo_root/examples/$runbook/README.md"
done

if grep -REn 'transit_gateway_options|^[[:space:]]*transit_gateway[[:space:]]*=' \
  "$repo_root/examples/private_nat" "$repo_root/examples/inspection_egress"; then
  echo "Active non-migration example recommends a deprecated TGW adapter" >&2
  exit 1
fi

grep -A2 -F 'fragment below omits required module inputs' "$repo_root/docs/how-to-use-outputs.md" | grep -Fq '```text'
grep -A2 -F 'fragment of `subnets.<group>.routing`' "$repo_root/examples/inspection_egress/README.md" | grep -Fq '```text'

python3 - "$repo_root" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1])
tracked = subprocess.run(
    ["git", "-C", str(root), "ls-files", ".header.md", "*.md", "**/*.md"],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()

failures = []
count = 0
for relative in tracked:
    text = (root / relative).read_text()
    for index, block in enumerate(re.findall(r"^[ \t]*```hcl[ \t]*\n(.*?)^[ \t]*```[ \t]*$", text, re.MULTILINE | re.DOTALL), 1):
        count += 1
        result = subprocess.run(
            ["terraform", "fmt", "-"],
            input=block,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            failures.append(f"{relative} fence {index}: {result.stderr.strip()}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
print(f"Validated {count} copyable HCL fences")
PY
