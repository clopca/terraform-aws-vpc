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
| 1 | Núcleo: aws_vpc + addressing (IPAM/estático/BYOIP-pool) + motor de subnets tipado con CIDRs deterministas y claves "name/az" | ✅ afe42fb |
| 2 | NAT (create-or-inject EIP), IGW/EIGW, routing co-localizado por subnet (incl. DNS64/NAT64, private NAT) | pendiente |
| 3 | Attachments TGW y Cloud WAN (sin replace destructivo by-design), flow logs (sin deps con deprecations), Lattice | pendiente |
| 4 | Outputs Tier 1/2/3 + moved blocks generados + herramienta/guía de migración v4→v5 (objetivo 0-diff) | pendiente |
| 5 | Tests: unit plan-only del motor de subnets + asserts por ejemplo + 3 examples (basic, enterprise BYOIP+IPAM, hub TGW/CWAN) + terraform-docs | pendiente |
| 6 | Auditoría final integral (los 2 revisores sobre el módulo completo) + gap-check contra RFC y contra demanda del backlog | pendiente |

## Reglas fijas del builder

1. Todo `object()` + `optional()` + `validation` — prohibido `type = any`.
2. Prohibido `count` para colecciones; claves for_each = `"name/az"` siempre.
3. CIDRs: explícitos como camino recomendado; cálculo determinista documentado si se usa netmask. Nunca posicional.
4. Ningún recurso de frontera sin patrón create-or-inject.
5. `terraform fmt` + `init -backend=false` + `validate` en verde antes de cada commit.
6. Sin dependencias de módulos externos con deprecations activas (flow logs con recursos nativos).
7. Commits pequeños y descriptivos por fase; no push (rama local hasta decisión con Pablo).

## Registro de revisiones

- docs/rfc/reviews/fase-1.md … fase-6.md — findings R1/R2, severidad, resolución y commit que lo cierra.
