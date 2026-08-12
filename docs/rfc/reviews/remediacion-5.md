# Remediación tanda 5 — ejemplos, contrato de outputs e idempotencia de VPC Lattice

> **Fecha:** 2026-08-13
> **Rama:** `explore/v5-typed-contract`
> **Commits de implementación:** `b2d5485`, `26a3973`, `8075896`, `4582076`
> **Estado:** ✅ scope de tanda 5 cerrado; todos los gates locales pasan.

## Findings y resolución

| Finding | Resolución | Commit | Estado |
|---|---|---|---|
| Outputs Tier 1 devolvían `""` para IPv6 ausente y Tier 3 evaluaba `aws_iam_role.inline_policy` deprecated | El output IPv6 normaliza la ausencia a `null`; `resources.flow_log_roles` proyecta únicamente `arn`, `id`, `name` y `unique_id`. Tests de shape fijan ambos contratos y la guía de outputs documenta sentinels y niveles de estabilidad. | `b2d5485`, `8075896` | ✅ Cerrado |
| Faltaban ejemplos completos dedicados a NAT BYOIP, IPAM y dual stack | Añadidos `nat_byoip`, `ipam` y `dual_stack`, cada uno con `README.md`, `main.tf`, `variables.tf`, `outputs.tf` y `providers.tf`. Los ejemplos preexistentes `basic`, `enterprise` y `hub` ya tenían los cuatro companions solicitados. La matriz de `.github/workflows/ci-v5.yml` ya enumera los siete ejemplos (`basic`, `enterprise`, `hub`, `migration-from-v4`, `nat_byoip`, `ipam`, `dual_stack`), por lo que no requirió cambios. | `26a3973` | ✅ Cerrado |
| Documentación pública v5 incompleta | Publicadas la guía operativa `v5/docs/UPGRADE-GUIDE-5.0.md` y la guía `v5/docs/how-to-use-outputs.md`; README, header, RFCs y skeleton de migración enlazan la fuente correcta y describen Tier 1/2/3. | `8075896` | ✅ Cerrado |
| **Critical — asociación VPC Lattice no idempotente tras apply real** | El apply de `enterprise` creó 78 recursos, pero el plan repetido proponía reemplazar `aws_vpclattice_service_network_vpc_association.this["vpc"]`: AWS materializa `dns_options` con `private_dns_preference = "VERIFIED_DOMAINS_ONLY"` y `private_dns_specified_domains = ["*"]`, mientras la configuración omitía el bloque. Provider AWS 6.59 marca `dns_options` y la preference como ForceNew. Se añadió un contrato tipado `dns_options`, default opinionado `VERIFIED_DOMAINS_ONLY`, validación de combinaciones y límites AWS, y un bloque dinámico que fija la preference cuando private DNS está habilitado. El dominio calculado queda `null` en configuración salvo modos specified, permitiendo que el provider absorba el sentinel de AWS sin drift. | `4582076` | ✅ Cerrado |

## ADR-R5-1 — Configurar el default AWS, no ignorar drift

Se eligió la primitiva tipada. `private_dns_enabled` sigue siendo opt-in y ForceNew;
cuando está habilitado, el módulo declara `dns_options.private_dns_preference` con
el default real `VERIFIED_DOMAINS_ONLY`. Los modos
`VERIFIED_DOMAINS_AND_SPECIFIED_DOMAINS` y `SPECIFIED_DOMAINS_ONLY` exigen entre 1
y 10 dominios no vacíos de hasta 255 caracteres; los otros modos prohíben esa
lista conforme a la API de VPC Lattice.

Se rechazó `lifecycle.ignore_changes`: ocultaría cambios intencionados de preference
y drift del servicio, repitiendo la clase de riesgo de #162 en vez de resolver su
causa. El test `v5/tests/lattice.tftest.hcl` fija el default enviado, la propagación
de specified domains y el rechazo de una combinación inválida.

## Evidencia

La causa original queda registrada en
`/tmp/v5-applies/enterprise/v5/examples/enterprise/terraform-idempotence.log`:
`1 to add, 1 to destroy` por eliminación del bloque `dns_options` devuelto por AWS.
El schema local seleccionado fue `hashicorp/aws 6.59.0`; la documentación del
provider confirma que el bloque y sus campos son ForceNew, y la API oficial de AWS
confirma las cuatro preferences y que specified domains sólo aplican a los dos
modos correspondientes.

| Gate | Resultado |
|---|---|
| `terraform fmt -check -recursive v5` | PASS |
| `tflint --chdir=v5 --init` | PASS |
| `tflint --chdir=v5 --recursive` | PASS, 0 findings |
| `terraform init -backend=false -lockfile=readonly` | PASS en módulo y siete ejemplos |
| `terraform validate -no-color` | PASS en módulo y siete ejemplos |
| `terraform test -no-color` | **56 passed, 0 failed** |
| Test focal Lattice | **3 passed, 0 failed** |
| Workaround macOS | `xattr -dr com.apple.provenance` aplicado a cada `.terraform/providers` antes de validate/test |
