#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "$*" >&2
  exit 1
}

# Retain security, inclusivity, and captured-environment hygiene guards.
if grep -RInE --exclude='.terraform.lock.hcl' --exclude='check-content.sh' --exclude-dir='.git' --exclude-dir='.terraform' \
  'air-gapped|master map|dynamodb:\*' "$repo_root"; then
  fail "Banned security or non-inclusive wording found"
fi

if grep -RInE --exclude-dir='.git' --exclude-dir='.terraform' --exclude='check-content.sh' \
  '3\.21\.81\.83|172\.2\.0\.(192|208|224)|2a05:d01c:bc3|2600:1f18:4200|079f76df39be519c9|0ae0e24ffe193f2a1|076e272ecaff6fce0|063181ad924968f92|04a86315c4839b519|0b9b71f291529d9fe|0fde39f9550f4abb5' \
  "$repo_root"; then
  fail "Captured environment address or resource ID found"
fi

grep -Fq 'dynamodb:GetItem' "$repo_root/examples/basic/main.tf"
grep -Fq 'arn:aws:dynamodb:us-east-1:123456789012:table/application-data' "$repo_root/examples/basic/main.tf"

# Landing page structure and ordering.
grep -Fxq '# AWS VPC Terraform module' "$repo_root/.header.md"
grep -Fxq '# AWS VPC Terraform module' "$repo_root/README.md"
grep -Fq '[![Terraform Registry]' "$repo_root/.header.md"
grep -Fq '[5.0 upgrade guide](docs/UPGRADE-GUIDE-5.0.md)' "$repo_root/.header.md"
grep -Fq 'source  = "aws-ia/vpc/aws"' "$repo_root/.header.md"
grep -Fxq '## Documentation' "$repo_root/.header.md"
grep -Fxq '## Examples' "$repo_root/.header.md"
grep -Fxq '## Documentation' "$repo_root/README.md"
grep -Fxq '## Examples' "$repo_root/README.md"

python3 - "$repo_root" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1])
header = (root / ".header.md").read_text()
readme = (root / "README.md").read_text()
examples = [
    "basic", "enterprise", "hub", "nat_byoip", "ipam", "dual_stack",
    "existing_vpc", "secure_isolated", "private_nat", "inspection_egress",
    "migration-from-v4",
]

for text, name in [(header, ".header.md"), (readme, "README.md")]:
    assert text.index("## Documentation") < text.index("## Examples"), f"{name}: Documentation must precede Examples"
    section = text.split("## Examples", 1)[1].split("\n## ", 1)[0]
    links = re.findall(r"\[`([^`]+)`\]\(examples/(?:\\_)?([^)]*)\)", section)
    linked_names = [label for label, _ in links]
    assert linked_names == examples, f"{name}: expected the 11-row example table, got {linked_names}"
    assert "| Example | What it demonstrates | Choose it when | External prerequisites and cost |" in section

variables = re.findall(r'^variable "([^"]+)"', (root / "variables.tf").read_text(), re.M)
index = (root / "docs/README.md").read_text()
input_rows = re.findall(r'^\| `([^`]+)` \|', index, re.M)
assert len(variables) == 13, variables
assert input_rows == variables, (input_rows, variables)

required_docs = [
    "docs/README.md",
    "docs/addressing.md",
    "docs/subnets-and-routing.md",
    "docs/nat-gateway.md",
    "docs/attachments.md",
    "docs/security-and-operations.md",
    "docs/outputs.md",
    "docs/UPGRADE-GUIDE-5.0.md",
    "docs/migration-v4-reference.md",
]
for relative in required_docs:
    assert (root / relative).is_file(), f"missing {relative}"
assert not (root / "docs/rfc").exists(), "docs/rfc must not be published"
assert not (root / "docs/how-to-use-outputs.md").exists(), "old outputs guide path remains"

upgrade = (root / "docs/UPGRADE-GUIDE-5.0.md").read_text()
for heading in [
    "## Contents",
    "### A. Baseline Terraform and the AWS provider while still on v4",
    "### B. Capture v4 identity and ordering",
    "### C. Translate configuration and state",
    "### D. Complete-plan gate",
    "### E. Ordered IAM permissions cutover and cleanup",
    "### F. Post-apply verification",
    "## Stop and rollback",
]:
    assert heading in upgrade, f"upgrade guide missing {heading}"
assert "migration-v4-reference.md" in upgrade
assert "## Variables" not in upgrade and "## Outputs" not in upgrade

reference = (root / "docs/migration-v4-reference.md").read_text()
for heading in [
    "## Contents",
    "## v4 Name formula mapping",
    "## Input crosswalk",
    "## Output crosswalk",
    "## State address rules",
    "## Cases that cannot use `moved`",
]:
    assert heading in reference, f"migration reference missing {heading}"

outputs = (root / "docs/outputs.md").read_text()
for heading in ["## Tier 1: stable composition", "## Tier 2: migrate v4 consumers, then remove them", "## Tier 3: use the escape hatch deliberately"]:
    assert heading in outputs, f"outputs guide missing {heading}"

# Resolve local Markdown links and parse every copyable HCL fence.
tracked = subprocess.run(
    ["git", "-C", str(root), "ls-files", "*.md", "**/*.md", ".header.md"],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()
failures = []
hcl_count = 0
for relative in tracked:
    path = root / relative
    if not path.exists():
        continue
    text = path.read_text()
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
        if re.match(r"^(?:https?://|mailto:|#)", target):
            continue
        clean = target.split("#", 1)[0].replace("\\_", "_")
        if clean and not (path.parent / clean).resolve().exists():
            failures.append(f"{relative}: broken link {target}")
    for index, block in enumerate(re.findall(r"^[ \t]*```hcl[ \t]*\n(.*?)^[ \t]*```[ \t]*$", text, re.M | re.S), 1):
        hcl_count += 1
        result = subprocess.run(["terraform", "fmt", "-"], input=block, text=True, capture_output=True)
        if result.returncode != 0:
            failures.append(f"{relative} HCL fence {index}: {result.stderr.strip()}")
if failures:
    raise SystemExit("\n".join(failures))

# Every scenario guide has the published template and a two-sentence opening.
for readme_path in sorted((root / "examples").glob("*/README.md")):
    text = readme_path.read_text()
    for heading in ["## What this demonstrates", "## Relevant configuration", "## Prerequisites and cost"]:
        assert heading in text, f"{readme_path}: missing {heading}"
    assert "(./main.tf)" in text, f"{readme_path}: missing main.tf link"
    lines = text.splitlines()
    opening = []
    for line in lines[2:]:
        if not line.strip():
            break
        opening.append(line)
    assert len(re.findall(r"[.!?](?:\s|$)", " ".join(opening))) == 2, f"{readme_path}: opening must contain two sentences"
    if readme_path.parent.name == "migration-from-v4":
        assert "## Rehearse safely" in text and "## Run" not in text
    else:
        assert "## Run" in text

print(f"Validated published docs: inputs={len(input_rows)}, examples={len(examples)}, HCL fences={hcl_count}")
PY

# Every README must be free of Mermaid diagrams.
if grep -RIn --include='README.md' '```mermaid' "$repo_root"; then
  fail "Mermaid remains in a README"
fi

# Public files must not expose internal labels, process vocabulary, or local paths.
if git -C "$repo_root" grep -nEiI \
  '\[(R[0-9]+-)?[CHMLF][-_]?[0-9]+[^]]*\]|\[Finding[ :#-]*[0-9]+[^]]*\]|remedia(cion|tion)-[0-9]+|rehearsal #[0-9]+|Builder: Agent|/Users/clopca/|/tmp/|docs/rfc|how-to-use-outputs|internal migration RFC|\bADR\b|\bRFC\b|\bproposal\b|\bprototype\b|\bfixture\b' \
  -- .header.md README.md CHANGELOG.md docs outputs.tf ':(glob)examples/*/README.md' 'examples/migration-from-v4/moved.tf'; then
  fail "Internal label, process wording, obsolete path, or local path found"
fi

# Plan/apply/destroy examples must preserve their required variable files.
for spec in \
  'hub:hub.tfvars' \
  'ipam:ipam.tfvars' \
  'nat_byoip:nat-byoip.tfvars' \
  'inspection_egress:inspection.tfvars' \
  'private_nat:private-nat.tfvars'; do
  example="${spec%%:*}"
  var_file="${spec#*:}"
  guide="$repo_root/examples/$example/README.md"
  grep -Fq "terraform plan -out=tfplan -var-file=$var_file" "$guide"
  grep -Fq 'terraform apply tfplan' "$guide"
  grep -Fq "terraform destroy -var-file=$var_file" "$guide"
done

# Active examples must use the plural TGW attachment contract.
active_readmes=("$repo_root"/examples/*/README.md)
for guide in "${active_readmes[@]}"; do
  [[ "$guide" == *'/migration-from-v4/README.md' ]] && continue
  if grep -En 'transit_gateway_options|^[[:space:]]*transit_gateway(_ipv6)?[[:space:]]*=' "$guide"; then
    fail "Active example recommends a deprecated TGW adapter: $guide"
  fi
done

# Regenerate in an isolated directory and compare without mutating the worktree.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/vpc-docs-check.XXXXXX")"
trap 'rm -R -- "$scratch"' EXIT
cp "$repo_root/.header.md" "$repo_root/.terraform-docs.yaml" "$scratch/"
cp "$repo_root"/*.tf "$scratch/"
terraform-docs "$scratch" >/dev/null
cmp -s "$repo_root/README.md" "$scratch/README.md" || fail "README.md is not regenerated from .header.md and the current Terraform contract"

echo "Published documentation content checks passed"
