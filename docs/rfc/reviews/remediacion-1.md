# Remediación tanda 1 — Criticals de auditoría final + Highs acoplados

> **Fecha:** 2026-08-12  
> **Rama:** `explore/v5-typed-contract`  
> **Baseline auditado:** `9bc0abca02cf0bf551565b67f867847675bd8cb0`  
> **Commits de resolución:** `db758f7`, `0a1f424`  
> **Estado:** ✅ scope de tanda 1 cerrado; gate global de Fase 6 pendiente por findings fuera de scope.

## Findings

| Finding | Resolución | Commit | Estado |
|---|---|---|---|
| C-IPv6 / R1-C1 / R2-C-02 | VPC con Amazon `/56`, IPv6 IPAM por netmask o CIDR exacto, y discovery en VPC inyectada. Subnets con `/64` explícito, IPAM o cálculo determinista desde VPC; stride de seis AZs y `ipv6.cidr_index`; `ipv6_native`; rutas EIGW `::/0` y NAT64 `64:ff9b::/96`. Outputs Tier 1 IPv6 y asserts sobre atributos planificados. | `db758f7` | ✅ Cerrado |
| C-AZ-COUNT / R2-C-01 | Se conserva `count` como modo de desarrollo: `sort` del data source, slice exacto de N y precondition si no existen suficientes AZs. Test con discovery desordenado y cardinalidad mayor que N. | `db758f7` | ✅ Cerrado |
| R2-H-01 — hub CIDRs solapados | Pines `/28` movidos a slots 64/65, fuera de los rangos explícitos; el ejemplo ahora materializa IPv6 real en sus cinco grupos. | `db758f7` | ✅ Cerrado |
| Lección mocks / R2-H-04 | Tests nuevos inspeccionan `assign_generated_ipv6_cidr_block`, cada `aws_subnet.ipv6_cidr_block`, campos IPAM, `ipv6_native`, rutas EIGW/NAT64 y el slice AZ. Los ejemplos exponen y asertan CIDRs IPv6 no vacíos. | `db758f7` | ✅ Cerrado |
| R2-H-02 — IDs computed rompen count/for_each | Selectores plan-known para VPC, IGW, route tables, NAT, Flow Logs y Lattice. Fixture con `terraform_data.*.output` demuestra first-plan composition, incluido IPv6 IPAM computed. | `0a1f424` | ✅ Cerrado |
| R1-H3 — `isolated` permitía DNS64/NAT64 | La validación de `subnets` rechaza `routing.dns64` para `role="isolated"`; test negativo dedicado. | `0a1f424` | ✅ Cerrado |
| R1-H4 — `internet_gateway=false` creaba IGW | `needs_igw` consume routing resuelto, no el role crudo. El false explícito elimina IGW/ruta; un NAT público creado conserva su requisito independiente de IGW. | `0a1f424` | ✅ Cerrado |

## ADRs

### ADR-R1-1 — Mantener `availability_zones.count`

Se implementa el modo publicado en vez de retirarlo: selección alfabética exacta,
validación de capacidad y advertencia development-only. Los nombres explícitos son
el contrato recomendado para producción.

### ADR-R1-2 — Ownership explícito y plan-known

Los flags declarativos deciden cardinalidad; IDs/ARNs sólo son values y pueden ser
computed. Se acepta el ajuste breaking antes de publicar v5 porque inferir modo con
`id == null` no es componible en Terraform.

### ADR-R1-3 — IPv6 comparte el modelo de estabilidad IPv4

El cálculo automático reserva seis `/64` por grupo y admite pinning absoluto. Los
modos explícito e IPAM tienen precedencia; `auto_assign` calcula sólo cuando no hay
otra fuente y activa asignación de direcciones al crear ENIs.

### ADR-R1-4 — Routing resuelto gobierna gateways

El role público aporta un default, no una obligación. Un false explícito suprime
IGW/ruta; DNS64 es routing de egress y queda prohibido en `isolated`.

## Evidencia

```text
terraform fmt -check -recursive v5:        PASS
v5 init -backend=false / validate:         PASS
v5/examples/basic init / validate:         PASS
v5/examples/enterprise init / validate:    PASS
v5/examples/hub init / validate:           PASS
v5/examples/migration-from-v4 init/validate: PASS
terraform test:                            35 passed, 0 failed
macOS provider workaround:                 xattr provenance removed
```

La suite conserva warnings conocidos del provider al exponer objetos completos
deprecated en Tier 2/3; no afectan el resultado de esta tanda y siguen registrados
en las auditorías R1/R2.
