# Plan de construcción v5 — terraform-aws-vpc (rama explore/v5-typed-contract)

> Método: cada fase la implementa un agente builder y la auditan DOS revisores
> independientes expertos en Terraform antes de pasar a la siguiente:
> - **R1 (primitives/diseño)**: ¿la abstracción es la correcta? ¿create-or-inject en
>   toda la frontera? ¿claves de state estables ante cualquier mutación de config?
>   ¿algo aquí generará deuda técnica o breaking changes futuros?
> - **R2 (calidad Terraform)**: idempotencia, for_each vs count, dependencias
>   implícitas, validaciones plan-time, compatibilidad provider, estilo, docs.
> Gate: la fase no se cierra hasta que ambos revisores no tengan findings Critical/High
> abiertos. Findings y resoluciones se registran en docs/rfc/reviews/fase-N.md.

## Fases

| Fase | Contenido | Estado |
|---|---|---|
| 0 | RFC + prototipo del contrato (validado) | ✅ ea2b21d |
| 1 | Núcleo: aws_vpc + addressing + motor de subnets tipado + CIDRs deterministas + claves "name/az" | ✅ afe42fb |
| 1-gate | Cierre findings R1+R2: C1 multi-public, C2 pinning, C3 list routing, H1-H4 docs+inject+outputs, R2-C1/C2/C3 provider+preconditions | ✅ (este commit) |
| 2 | NAT (create-or-inject EIP+NAT GW), IGW/EIGW impl, routing co-localizado (DNS64/NAT64, private NAT) | pendiente |
| 3 | Attachments TGW y Cloud WAN (sin replace destructivo by-design), flow logs, Lattice | pendiente |
| 4 | Outputs Tier 1/2/3 + moved blocks generados + herramienta/guía de migración v4→v5 | pendiente |
| 5 | Tests: unit plan-only del motor de subnets + asserts + 3 examples + terraform-docs | pendiente |
| 6 | Auditoría final integral + gap-check contra RFC y contra demanda del backlog | pendiente |

## Reglas fijas del builder

1. Todo `object()` + `optional()` + `validation` — prohibido `type = any`.
2. Prohibido `count` para colecciones; claves for_each = `"name/az"` siempre.
3. CIDRs: explícitos como camino recomendado; cálculo determinista con pinning documentado.
4. Ningún recurso de frontera sin patrón create-or-inject.
5. `terraform fmt` + `init -backend=false` + `validate` en verde antes de cada commit.
6. Sin dependencias de módulos externos con deprecations activas.
7. Commits pequeños y descriptivos por fase; no push (rama local hasta decisión con Pablo).
8. Provider floor >= 5.69 (por security_group_referencing — R2-C1).
9. Cross-variable invariants via preconditions en recursos, no solo en variables (R2-H1).

## Registro de revisiones

- [docs/rfc/reviews/fase-1.md](reviews/fase-1.md) — R1+R2 findings, resolución, tabla completa.
- docs/rfc/reviews/fase-2.md … fase-6.md — pendientes.

## Cambios del contrato introducidos en Gate 1

- `routing.transit_gateway` / `core_network`: `string` → `list(string)` [R1-C3]
- Public role: N grupos permitidos (singleton eliminado) [R1-C1]
- `ipv4.cidr_index`: nuevo campo para CIDR pinning [R1-C2]
- `vpc.igw_id`: inject-or-create para IGW [R1-H2]
- `nat_gateway.existing_ids`: inject-or-create para NAT GW [R1-H2]
- `allocation_ids`: default null (no `{}`) [R2-H2]
- Outputs renombrados: `*_by_role` → `*_by_group` + nuevo `*_by_semantic_role` [R1-H3]
- Provider floor: `>= 5.69` [R2-C1]
- Preconditions: cidrs↔AZs, nat_gateway.az∈AZs [R2-C2, R2-C3]
