# Remediación tanda 5 — applies, ejemplos y documentación v5

> **Fecha:** 2026-08-13
> **Rama:** `explore/v5-typed-contract`
> **Baseline:** `390d670`
> **Commits de implementación:** `b2d5485`, `26a3973`, `8075896`, `4582076`
> **Estado:** ✅ hallazgos de applies cerrados, documentación de usuario publicada y todos los gates locales en verde.

## Findings y resolución

| Finding | Resolución | Commit | Estado |
|---|---|---|---|
| Tier 3 evaluaba `aws_iam_role.inline_policy` deprecado | `resources.flow_log_roles` proyecta sólo `arn`, `id`, `name` y `unique_id`; las políticas quedan separadas en `resources.flow_log_role_policies`. Un inventario de `aws_iam_role.*` confirmó que ningún otro output Tier 3 exporta roles IAM completos. El test de shapes fija exactamente las cuatro claves. | `b2d5485`, `8075896` | ✅ Cerrado |
| Tier 1 devolvía `""` para subnets sin IPv6 | `subnet_ipv6_cidrs_by_group_by_az` normaliza la ausencia a `null`. La descripción del output, README, guía de outputs y tests fijan el sentinel para subnets IPv4-only. | `b2d5485`, `8075896` | ✅ Cerrado |
| Ejemplos existentes sin estructura y guía completas | `basic`, `enterprise`, `hub` y `migration-from-v4` separan `providers.tf`, `variables.tf` y `outputs.tf` de `main.tf`; cada README explica features, arquitectura, prerequisitos y ejecución o ensayo. | `26a3973` | ✅ Cerrado |
| Faltaban ejemplos dedicados de NAT BYOIP, IPAM y dual stack | Añadidos `nat_byoip`, `ipam` y `dual_stack`, cada uno con estructura completa y plan test. La validación de CI enumera los siete ejemplos. | `26a3973` | ✅ Cerrado |
| Documentación pública v5 incompleta | Publicadas `v5/docs/UPGRADE-GUIDE-5.0.md` y `v5/docs/how-to-use-outputs.md`; README, header, RFC y skeleton de migración enlazan la fuente correcta y describen Tier 1/2/3. El RFC queda como evidencia interna. | `8075896` | ✅ Cerrado |
| README generado debía usar terraform-docs 0.19.0 | Regenerado con el binario oficial `terraform-docs v0.19.0` para Darwin arm64 y checksum verificado. | `8075896` | ✅ Cerrado |
| **Critical — asociación VPC Lattice no idempotente tras apply real** | El apply de `enterprise` creó 78 recursos, pero el plan repetido proponía reemplazar la asociación: AWS materializa `dns_options` con `VERIFIED_DOMAINS_ONLY` y un sentinel calculado `[*]`, mientras la configuración omitía el bloque. Se añadió contrato tipado, default alineado con AWS, validaciones y bloque dinámico. Los dominios permanecen `null` salvo modos specified, permitiendo absorber el sentinel sin drift. | `4582076` | ✅ Cerrado |
| Faltaban ejemplos explícitos de create-or-inject, enclave D6 y private NAT hacia TGW | Añadidos `existing_vpc`, `secure_isolated` y `private_nat` con estructura completa, catálogo público, validación CI y plan tests. Los ejemplos fijan respectivamente ownership externo computado, ausencia total de egress con BPA/DHCP y la cadena workload → private NAT → TGW para dominios 10/8 solapados. | commit de esta ampliación | ✅ Cerrado |
| Faltaba el patrón hub-and-spoke de inspección centralizada con egress | Añadido `inspection_egress`: tres AZs con NAT público, subnets de firewall, attachment TGW en appliance mode, retorno por managed prefix list y composición `centralized_inspection_with_egress` preparada desde outputs Tier 1. La dependencia `aws-ia/networkfirewall/aws` queda comentada para mantener CI autocontenido hasta que el caller seleccione y pine una release. | commit de esta ampliación | ✅ Cerrado |

## Inventario de ejemplos

| Ejemplo | Features principales | Cobertura |
|---|---|---|
| `basic` | Tres AZs, dual stack parcial, NAT single-AZ, DNS64/NAT64, EIGW y Flow Logs | Validate + plan test; fija `null` para database IPv4-only |
| `enterprise` | CIDR secundario, NAT por AZ, dual stack, Lattice, Flow Logs y tags | Validate + plan test |
| `hub` | TGW, Cloud WAN, recursos inyectados, Firehose y NAT privado | Validate + plan test |
| `migration-from-v4` | Nombres v4, aliases Tier 2, catálogo `moved`, log-group remove/import e IAM ordenado | Validate + tests stateful existentes |
| `nat_byoip` | EIP `create`, `byoip_pool` y `existing` con topología equivalente | Validate + plan test |
| `ipam` | VPC IPv4/IPv6 por IPAM, secundarios IPAM/estático y subnets por pool | Validate + plan test |
| `dual_stack` | Subnets dual-stack e IPv6-native, DNS64/NAT64, IGW y EIGW | Validate + plan test |
| `existing_vpc` | VPC/IGW/route table/EIPs externos inyectados; subnets y NAT bajo ownership del módulo | Validate + plan test |
| `secure_isolated` | BPA bidireccional, DHCP custom y sólo roles `isolated`, sin gateways ni rutas de egress | Validate + plan test |
| `private_nat` | Private NAT por AZ sobre CIDR de traducción y rutas específicas a un TGW externo | Validate + plan test |
| `inspection_egress` | Hub-and-spoke: TGW appliance mode → Network Firewall → NAT/IGW, retorno por prefix list | Validate + plan test |

## Inventario de documentación

- `v5/README.md`: contrato, quick start, tiers, catálogo de ejemplos, migración y referencia generada.
- `v5/docs/UPGRADE-GUIDE-5.0.md`: runbook v4 → v5, state moves, CloudWatch remove/import y transición IAM sin gap.
- `v5/docs/how-to-use-outputs.md`: Tier 1/2/3, consumo por grupo/rol/AZ y sentinels opcionales.
- `docs/rfc/v5-migration.md`: rationale, ADRs y evidencia interna; enlaza la guía normativa de usuario.
- Once README de ejemplo: features, arquitectura, prerequisitos y comandos.

## Decisiones de diseño

### ADR-R5-1 — Configurar el default AWS, no ignorar drift

`private_dns_enabled` sigue siendo opt-in y ForceNew. Cuando se habilita, el módulo declara el default real `VERIFIED_DOMAINS_ONLY`; los dos modos specified exigen 1-10 dominios válidos. Se rechazó `lifecycle.ignore_changes` porque ocultaría cambios deliberados y drift. El test `v5/tests/lattice.tftest.hcl` fija default, specified domains y combinación inválida.

### ADR-R5-2 — Proyectar el rol IAM en vez de filtrar warnings

El output evita evaluar el objeto completo en lugar de suprimir la deprecación. Conserva cuatro handles útiles y expone las políticas en una colección propia. Tier 3 sigue siendo inestable, pero deja de acoplar el plan al atributo provider `inline_policy`.

### ADR-R5-3 — `null` es el sentinel Tier 1 para ausencia de familia IP

Los maps conservan todas las claves grupo/AZ para cruzarse con IDs y route tables. La ausencia de IPv6 se representa con `null`, no eliminando la clave ni propagando una cadena vacía del provider.

### ADR-R5-4 — Ejemplos validables sin fingir recursos externos

Los IDs IPAM/BYOIP/EIP son placeholders con forma válida para validate y plan mock; los README exigen sustituirlos antes de apply. `nat_byoip` mantiene la topología constante entre modos, `ipam` separa pools VPC/subnet y asociaciones, y `dual_stack` concentra los caminos IPv6. `existing_vpc` demuestra IDs computed sin inferir ownership; `secure_isolated` advierte del singleton regional BPA; `private_nat` exige un TGW externo y separa rutas workload→NAT de NAT→TGW; `inspection_egress` mantiene la dependencia de Network Firewall comentada pero materializa y testea sus inputs exactos desde Tier 1.

## Evidencia y gates

El plan repetido del apply real de `enterprise` registró `1 to add, 1 to destroy` por eliminación del bloque `dns_options` devuelto por AWS. El schema seleccionado fue `hashicorp/aws 6.59.0`; provider y API confirman el carácter ForceNew, las cuatro preferences y los límites de specified domains.

| Gate | Resultado |
|---|---|
| `terraform fmt -check -recursive v5` | PASS |
| `tflint --chdir=v5 --init` | PASS |
| `tflint --chdir=v5 --recursive` | PASS, 0 findings |
| `terraform init -backend=false -lockfile=readonly` | PASS en módulo y once ejemplos |
| `terraform validate -no-color` | PASS en módulo y once ejemplos |
| `terraform test -no-color` | **60 passed, 0 failed** |
| Test focal Lattice | **3 passed, 0 failed** |
| Plan tests del catálogo (migración usa fixture stateful) | **10 passed, 0 failed** |
| Regeneración `terraform-docs v0.19.0` | PASS, checksum verificado |
| Auditoría de exports `aws_iam_role` | PASS; sólo proyección explícita en `resources.flow_log_roles` |
| Workaround macOS | `xattr -dr com.apple.provenance` aplicado a cada `.terraform/providers` antes de validate/test |
