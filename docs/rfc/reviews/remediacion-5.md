# Remediación tanda 5 — applies y documentación v5

> **Fecha:** 2026-08-13
> **Rama:** `explore/v5-typed-contract`
> **Baseline:** `390d670`
> **Commits de implementación:** `b2d5485`, `26a3973`, `8075896`
> **Estado:** ✅ hallazgos del apply real cerrados, documentación de usuario publicada y gates locales completos en verde.

## Findings y resolución

| Finding | Resolución | Commit | Estado |
|---|---|---|---|
| A1 — `resources.flow_log_roles` evaluaba el objeto `aws_iam_role` completo y el provider AWS 6.59 emitía cuatro warnings por `inline_policy` deprecado | Cada rol se proyecta explícitamente a `{ arn, id, name, unique_id }`; las políticas inline siguen disponibles por separado en `resources.flow_log_role_policies`. Un inventario de referencias `aws_iam_role.*` en `v5/outputs.tf` confirmó que no queda ningún otro output Tier 3 que exporte roles IAM completos. El test de shapes fija exactamente las cuatro claves y un ARN representativo. | `b2d5485` | ✅ Cerrado |
| A2 — `subnet_ipv6_cidrs_by_group_by_az` devolvía `""` para subnets sin IPv6 | El boundary Tier 1 normaliza `""` a `null`; la descripción del output, README, guía de outputs y ejemplos documentan el sentinel. Los tests fijan `null` tanto en la shape sin recursos opcionales como en las subnets IPv4-only del ejemplo `basic`. | `b2d5485`, `8075896` | ✅ Cerrado |
| B1 — ejemplos existentes sin estructura/documentación completa | `basic`, `enterprise`, `hub` y `migration-from-v4` separan `providers.tf`, `variables.tf` y `outputs.tf` de `main.tf`. Cada README explica features, arquitectura, prerequisitos, costes relevantes y comandos de ejecución o ensayo. | `26a3973` | ✅ Cerrado |
| B2 — faltaban ejemplos dedicados para EIP/NAT, IPAM y dual stack | Se añadieron `nat_byoip`, `ipam` y `dual_stack`, cada uno con estructura completa, README y plan test. Los siete ejemplos se validan en `ci-v5.yml`. | `26a3973` | ✅ Cerrado |
| B3 — guía de migración todavía orientada a RFC y sin guía de outputs v5 | Se publicó `v5/docs/UPGRADE-GUIDE-5.0.md` como runbook de usuario final; el RFC queda como evidencia interna y enlaza a la guía normativa. Se añadió `v5/docs/how-to-use-outputs.md` con los tres tiers, ejemplos de composición y contratos de `null`/colecciones vacías. | `8075896` | ✅ Cerrado |
| B4 — README generado debía reflejar los outputs finales | `v5/README.md` se regeneró con el binario oficial `terraform-docs v0.19.0` para Darwin arm64, descargado con checksum verificado. Una segunda regeneración exacta dejó el árbol sin diff. | `8075896` | ✅ Cerrado |

## Inventario de ejemplos

| Ejemplo | Features demostradas | Cobertura |
|---|---|---|
| `basic` | Tres AZs, subnets públicas/privadas/aisladas, dual stack parcial, NAT single-AZ, DNS64/NAT64, EIGW y Flow Logs CloudWatch | `terraform validate` + `basic_example`; fija `null` para database IPv4-only |
| `enterprise` | CIDR secundario estable, NAT por AZ, dual stack, capas aisladas, Flow Logs, Lattice y tags | `terraform validate` + `enterprise_example` |
| `hub` | TGW, Cloud WAN, IGW/EIP inyectados, Firehose externo, rutas múltiples y NAT privado de inspección | `terraform validate` + `hub_example` |
| `migration-from-v4` | Identidad de nombres v4, Tier 2 temporal, catálogo `moved`, remove/import de log group y transición IAM ordenada | `terraform validate` + tests de migración stateful existentes |
| `nat_byoip` | Los tres modos EIP: `create`, `byoip_pool` y `existing`, dos NAT por modo | `terraform validate` + `nat_byoip_example` |
| `ipam` | CIDR primario IPv4 por IPAM, secundarios IPAM/estático, subnets por pool e IPv6 IPAM | `terraform validate` + `ipam_example` |
| `dual_stack` | Subnets dual-stack e IPv6-native, DNS64/NAT64, IGW y EIGW | `terraform validate` + `dual_stack_example` |

## Inventario de documentación

- `v5/README.md`: contrato, quick start, tiers, ejemplos, migración y referencia generada.
- `v5/docs/UPGRADE-GUIDE-5.0.md`: runbook de producción v4 → v5, incluidos state moves, CloudWatch remove/import, gate de plan completo y transición IAM sin gap.
- `v5/docs/how-to-use-outputs.md`: selección Tier 1/2/3, consumo por grupo/rol/AZ, sentinels opcionales y escape hatch.
- `docs/rfc/v5-migration.md`: rationale, ADRs y evidencia interna; delega la ejecución de usuario a la guía publicada.
- README por cada uno de los siete ejemplos: features, arquitectura, prerequisitos y ejecución.

## Gates

Toolchain local: Terraform `1.15.8`, TFLint `0.63.1`, AWS provider bloqueado en `6.59.0` y terraform-docs exacto `0.19.0`. Antes de validate/test se eliminó `com.apple.provenance` de los directorios locales de providers cuando estaba presente.

| Gate | Resultado |
|---|---|
| `terraform fmt -check -recursive v5` | PASS |
| `tflint --chdir=v5 --init` | PASS |
| `tflint --chdir=v5 --recursive` con `v5/.tflint.hcl` | PASS |
| `terraform validate -no-color` en el módulo | PASS |
| `terraform validate -no-color` en `basic`, `enterprise`, `hub`, `migration-from-v4`, `nat_byoip`, `ipam` y `dual_stack` | **7/7 PASS** |
| `terraform test -no-color` | **53 passed, 0 failed** |
| Regeneración `terraform-docs v0.19.0` | PASS; árbol sin diff posterior |
| Auditoría de exports `aws_iam_role` | PASS; sólo proyección explícita en `resources.flow_log_roles` |

## Decisiones de diseño

### ADR-R5-1 — Proyectar el rol IAM en vez de filtrar warnings

El output no suprime ni acepta la deprecación: evita evaluar el objeto completo. Se conservan los cuatro handles útiles para composición y la política tiene su propia colección. Tier 3 sigue siendo inestable, pero deja de acoplar a consumidores y planes al atributo provider `inline_policy`.

### ADR-R5-2 — `null` es el sentinel Tier 1 para ausencia de familia IP

Los maps conservan todas las claves de grupo/AZ para que puedan cruzarse estructuralmente con IDs y route tables. La ausencia de IPv6 se representa con `null`, no eliminando la clave ni usando cadena vacía. Esto diferencia ausencia de un CIDR válido y evita propagar detalles del provider al contrato estable.

### ADR-R5-3 — Ejemplos dedicados validables sin fingir recursos externos

Los IDs de IPAM/BYOIP/EIP son placeholders con forma válida para plan mock y `terraform validate`; los README exigen sustituirlos antes de apply. El ejemplo `nat_byoip` mantiene topología idéntica entre modos para aislar la decisión de ownership de EIPs; `ipam` separa pools VPC/subnet y asociaciones secundarias; `dual_stack` concentra todos los caminos IPv6.

### ADR-R5-4 — La guía de usuario gobierna el procedimiento; el RFC conserva evidencia

El runbook final vive junto al módulo versionado y está escrito para operadores. El RFC no se elimina porque conserva ADRs, detalles del fixture y justificación histórica, pero enlaza explícitamente a la guía normativa para evitar dos procedimientos competidores.
