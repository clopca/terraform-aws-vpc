# Remediación tanda 2 — D6, IPAM secondary, fronteras y quality gates

> **Fecha:** 2026-08-12
> **Rama:** `explore/v5-typed-contract`
> **Baseline auditado:** `9bc0abca02cf0bf551565b67f867847675bd8cb0`
> **Commits de implementación:** `3f96aba`, `606fc47`
> **Dependencias ya cerradas en tanda 1:** `db758f7`, `0a1f424`; registro `173c9db`
> **Estado:** ✅ scope de tanda 2 cerrado; el gate global de Fase 6 conserva fuera de scope la evidencia AWS real y la migración integral.

## Findings y resolución

| Finding | Resolución | Commit | Estado |
|---|---|---|---|
| R1-H2 — D6 omitía VPC Block Public Access y DHCP options | Añadidos contratos tipados para BPA regional, exclusiones estables por mapa y DHCP options. Opciones, exclusiones y DHCP implementan create-or-inject; la asociación DHCP conserva el VPC como target. Outputs Tier 1 publican los IDs creados o inyectados. | `3f96aba` | ✅ Cerrado |
| R1-H1 / R2-M-04 — secondary CIDRs posicionales; issues #146/#142 | `addressing.ipv4.secondary` pasa de lista indexada a mapa con claves caller-owned. Cada entrada aplica XOR create/inject y static/IPAM; IPAM exige netmask. `subnets[*].ipv4.secondary_cidr_key` declara la asociación requerida y `aws_subnet.main` depende de las asociaciones creadas, eliminando el primer apply con `-target`. | `3f96aba` | ✅ Cerrado |
| R1-H5 / R2-H-03 — create-or-inject incompleto | Añadidos modos explícitos e IDs para EIGW, subnets, TGW attachment, Cloud WAN attachment/accepter, Flow Log, VPC Lattice y secondary associations. Las colecciones conservan claves declarativas y los outputs Tier 1 devuelven handles creados o inyectados. | `3f96aba` | ✅ Cerrado |
| R2-M-02 — locals sin uso | Eliminados `local.subnet_names_sorted` y `local.subnets_with_ipam`; TFLint no reporta declaraciones sin uso. | `3f96aba` | ✅ Cerrado |
| R2-M-01 — TFLint no ejecutable | Configuración v5 migrada a `call_module_type`, TFLint fijado a `0.63.1` y ruleset AWS a `0.48.0`. El workflow inicializa plugins y ejecuta `tflint --chdir=v5 --recursive`. | `606fc47` | ✅ Cerrado |
| R1-H8 — ejemplos con placeholders estructurales y ausencia de CI | `basic` y `enterprise` ya crean sus dependencias; `hub` conserva inyección intencional con IDs/ARNs de formato válido para demostrar fronteras externas. Añadido CI macOS con Terraform `1.15.8`, fmt, TFLint, validate del módulo y cuatro ejemplos, y suite completa. | `606fc47` | ✅ Cerrado para el scope local/CI; apply sandbox sigue fuera de scope |
| R2-H-04 — tests no cazaban los fixes | Plan assertions cubren atributos BPA/DHCP, claves y argumentos IPAM/static secondary, subnet→association, y omisión de recursos en inyección. `expect_failures` cubre modos incompatibles, selector secondary desconocido e IDs inyectados ausentes. | `3f96aba` | ✅ Cerrado |
| Tanda 1 — IPv6, AZ count, IDs computed, aislamiento e IGW override | Se mantiene la trazabilidad de la primera tanda: implementación `db758f7` + `0a1f424`; registro de cierre `173c9db`. | `db758f7`, `0a1f424`, `173c9db` | ✅ Cerrado |

## Evidencia final

| Gate | Resultado |
|---|---|
| `terraform fmt -check -recursive v5` | PASS |
| `tflint --chdir=v5 --init` | PASS |
| `tflint --chdir=v5 --recursive` | PASS, 0 findings |
| `terraform init -backend=false -lockfile=readonly` | PASS en módulo y cuatro ejemplos |
| `terraform validate -no-color` | PASS en módulo y cuatro ejemplos |
| `terraform test -no-color` | **49 passed, 0 failed** |
| Inventario de tests | 11 ficheros, 49 runs, 60 bloques `assert`, 21 runs con `expect_failures` |
| Workaround macOS | `xattr -r -d com.apple.provenance` aplicado a `.terraform/providers` antes de validate/test |

La suite sigue usando provider mocks y no sustituye un apply AWS. Los warnings de
atributos deprecated al exponer objetos completos Tier 2/3 permanecen registrados
como deuda pre-v6; no invalidan estos gates.

## Decisiones

### ADR-R2-1 — La clave secondary pertenece al caller

El nombre del mapa es la identidad de state y no se deriva de posición ni CIDR. La
subnet referencia esa misma clave. Renombrarla requiere un `moved` explícito; insertar
o reordenar entradas no altera direcciones existentes.

### ADR-R2-2 — Dependencia explícita, no serialización manual

Las subnets creadas dependen de la colección de asociaciones secondary y el selector
individual se valida por clave. Esto conserva un único `terraform apply` normal y
retira el workaround histórico `-target` de #146/#142.

### ADR-R2-3 — Toda frontera declara ownership

Un booleano plan-known decide create/inject; IDs y ARNs son values y pueden venir de
outputs computed. No se infiere cardinalidad desde `id == null`. Los destinos de datos
S3/Firehose siguen siendo caller-owned por ADR-F3-1, pero el Flow Log que los consume
sí puede crearse o inyectarse.

## Fuera del scope de esta tanda

- Apply AWS real de dual-stack/DNS64, secondary IPAM, TGW/Cloud WAN y destroy.
- Demostración integral de migración v4→v5 sobre state real con cero replacements.
- Sustituir las listas AZ→CIDR explícitas por mapas si se aprueba un breaking change
  adicional antes de publicar v5.
- Eliminar los aliases de objetos completos y sus warnings corresponde a v6.
