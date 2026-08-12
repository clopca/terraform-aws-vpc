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
| 1-gate | Cierre findings R1+R2: C1 multi-public, C2 pinning, C3 list routing, H1-H4 docs+inject+outputs, R2-C1/C2/C3 provider+preconditions | ✅ e434caf |
| 2 | NAT (create-or-inject EIP+NAT GW), IGW/EIGW impl, routing co-localizado (DNS64/NAT64, private NAT) | ✅ 89eba29 |
| 2-gate | Cierre R1+R2: claves CIDR estables, placement NAT explícito, RT injection, NAT64, coverage y docs de unknowns | ✅ 97c89ee |
| 3 | Attachments TGW y Cloud WAN (sin replace destructivo by-design), flow logs, Lattice | ✅ implementada |
| 3-gate | Cierre R1+R2: dependencias attachment/accepter, floor 6.32, IAM hardened, destinos de datos externos y ADRs | ✅ `a9be661` |

### Entrega fase 3

- TGW y Cloud WAN usan una dirección singleton estable (`["vpc"]`) y referencias
  escalares. Las rutas esperan sólo al attachment correspondiente y, en Cloud WAN,
  al accepter opcional. No hay serialización global.
- Cloud WAN construye el ARN del VPC sin propagar el objeto completo de
  `data.aws_vpc`. El ARN escalar elimina el unknown espurio; no se ignora `vpc_arn`,
  por lo que un cambio real de identidad conserva el replace correcto.
- Flow Logs crean o inyectan CloudWatch y su rol. La policy separa
  `DescribeLogGroups`, el trust usa `SourceAccount`/`SourceArn`, y S3/Firehose son
  destinos externos inyectados para mantener fuera del módulo retención, KMS y
  lifecycle de datos.
- VPC Lattice usa set de hasta cinco security groups y DNS privado opt-in.
- El provider floor real es `>= 6.29` por los atributos IPAM de `aws_subnet`.
- Tier 1 incorpora IDs de attachments/flow logs/Lattice y ARNs de destinos/roles.
- Los tres ejemplos ejercitan la sintaxis de fase 3; los tests de apply/races
  permanecen en la fase 5 según ADR del gate.
| 4 | Outputs Tier 1/2/3 + moved blocks generados + herramienta/guía de migración v4→v5 | ✅ `9a4bb9c` |
| 4-gate | Cierre R1+R2: floor 6.29 consistente, Flow Logs replacement-safe, plan completo con allowlist y verificación post-apply, orden AZ documentado | ✅ `9834664` + `724c964` |
| 5 | Tests: unit plan-only del motor de subnets + asserts de shape Tier 1/Tier 2 + fixture stateful de migración + 3 examples + terraform-docs | ✅ `a5fb279` + `2db15d7` |
| 6 | Auditoría final integral + gap-check contra RFC y contra demanda del backlog | 🟡 auditada; remediaciones 1 y 2 cerradas, evidencia AWS/migración integral pendiente |

### Entrega fase 4

- Tier 1 publica handles directos de VPC/AZ, subnet IDs/CIDRs por grupo, rol
  semántico y AZ, route tables con las mismas vistas, NAT IDs/IPs/EIP allocation
  IDs, attachments, Flow Logs y Lattice.
- Tier 2 reproduce los 15 outputs v4 con sus claves externas exactas: privadas
  `"<grupo>/<az>"`, reservadas por AZ, route tables con los cuatro tipos y objetos
  completos. Los tres aliases del prototipo siguen deprecated hasta v6.
- Tier 3 expone objetos completos en `resources` y declara explícitamente que no
  tiene garantía semver.
- `v5-migration.md` contiene la matriz completa de inputs/outputs, un gate de
  `terraform plan` normal con allowlist y verificación posterior, y ADR-F4-1 para
  Flow Logs. `migration-from-v4/moved.tf` mantiene 63 movimientos activos; el log
  group v4 se preserva mediante nombre físico exacto + remove/import porque
  `name_prefix` -> `name` es ForceNew.
- El role IAM conserva el `name_prefix`; la policy inline se crea en un apply
  dirigido antes de retirar el attachment/policy gestionado antiguo, evitando una
  ventana sin permisos. La guía conserva el orden observable de `module.vpc.azs`.
- Validaciones nuevas cierran cardinalidad IPv6, unicidad de pinning, gramática de
  claves, CIDRs/destinos, opciones por rol, addressing IPv4 de VPC y cobertura
  exacta de claves NAT/EIP por AZ. Los prefix-list IDs ya se materializan en
  `destination_prefix_list_id`.
- Los asserts ejecutables de shape para los 15 aliases Tier 2 y handles Tier 1, y
  la fixture stateful de moved/import, permanecen explícitamente en Fase 5
  (R1-M1/R2 recomendación de cobertura); no bloquean el gate documental de Fase 4.
- Gate R1+R2 de fase 4 cerrado: 0 Critical/High abiertos.

### Entrega fase 5

- Suite nativa: **28 runs, 51 comprobaciones** — motor CIDR 9/18 asserts,
  shapes Tier 1/Tier 2 2/11 asserts, validaciones negativas 11/11
  `expect_failures`, ejemplos 3/6 asserts y migración 3/5 asserts.
- Los 27 runs de módulo/ejemplos/migración son `plan` con `mock_provider`; el
  único `apply` usa también el provider mock y sólo siembra el state efímero v4
  para verificar que subnet, route table y association conservan ID tras sus
  `moved` representativos. La suite completa pasa con las variables de
  credenciales AWS eliminadas del entorno.
- El ejemplo completo de migración, incluidos sus 63 `moved`, se parsea y
  planifica. El remove/import del log group mantiene su gate operativo en
  `v5-migration.md`; los imports declarativos no pueden cargarse como módulos
  alternativos de `terraform test`, por lo que no se simula un import remoto.
- El motor CIDR reserva seis posiciones AZ por grupo, empaqueta netmasks mixtas
  sin solape, mantiene estables los CIDRs al añadir AZ y rechaza pins absolutos
  solapados entre netmasks.
- `v5/.terraform-docs.yaml`, `.header.md` y el `README.md` generado documentan
  uso, ejemplos, garantías Tier 1/2/3, estabilidad de direcciones y migración.
- `terraform test`: 28 passed, 0 failed; `fmt -check`, `validate` del módulo y
  de los cuatro ejemplos: PASS. Gate R1+R2 de fase 5 queda pendiente.

## Remediación tanda 1 — Criticals + Highs acoplados

Commits locales: `db758f7` (IPv6/AZ/examples/tests) y `0a1f424`
(selectores plan-known y coherencia de routing).

- IPv6 end-to-end: VPC Amazon/IPAM/CIDR, `/64` determinista y pinneable,
  subnet IPAM, IPv6-native, EIGW y DNS64/NAT64.
- `availability_zones.count`: orden alfabético y slice exacto; names explícitos
  siguen siendo la recomendación productiva (ADR-R1-1).
- IDs computed: ownership/cardinalidad sale de flags de configuración; fixture
  upstream cubre VPC, IGW, route table, IPv6 IPAM, Flow Logs y Lattice.
- Hub sin solapes; `isolated` rechaza DNS64; `internet_gateway=false` es
  autoritativo salvo el requisito independiente de un NAT público creado.
- Gate ejecutado: fmt, init/validate del módulo y cuatro ejemplos, y
  `terraform test` **35 passed, 0 failed**.

El gate global de Fase 6 no se marca cerrado: los findings fuera del scope de esta
tanda permanecen sujetos a remediaciones posteriores.

## Remediación tanda 2 — D6 + IPAM secondary + fronteras + quality gates

Commits locales: `3f96aba` (contrato/recursos/tests) y `606fc47`
(TFLint/CI/ejemplos).

- D6: VPC Block Public Access regional y DHCP options con contratos tipados,
  create-or-inject, exclusiones estables y outputs Tier 1.
- Secondary CIDRs: mapa con claves caller-owned, XOR static/IPAM/inject, selector
  `secondary_cidr_key` y dependencia subnet→association; cierre funcional de
  #146/#142 sin `-target`.
- Fronteras: EIGW, subnet, TGW attachment, Cloud WAN attachment/accepter, Flow
  Log, Lattice y secondary associations tienen create-or-inject explícito.
- Quality gates: TFLint 0.63.1 + AWS ruleset 0.48.0, dos locals muertos
  eliminados, ejemplos sin placeholders estructurales y workflow CI v5 fijado.
- Gate ejecutado: fmt, TFLint, init/validate del módulo y cuatro ejemplos, y
  `terraform test` **49 passed, 0 failed** (60 asserts; 21 negative runs).

El gate global conserva fuera de scope el apply AWS real y la demostración
integral de migración v4→v5 sobre state real.

## Reglas fijas del builder

1. Todo `object()` + `optional()` + `validation` — prohibido `type = any`.
2. Prohibido `count` para colecciones; claves for_each = `"name/az"` siempre.
3. CIDRs: explícitos como camino recomendado; cálculo determinista con pinning documentado.
4. Ningún recurso de frontera sin patrón create-or-inject.
5. `terraform fmt` + `init -backend=false` + `validate` en verde antes de cada commit.
6. Sin dependencias de módulos externos con deprecations activas.
7. Commits pequeños y descriptivos por fase; no push (rama local hasta decisión con Pablo).
8. Provider floor >= 6.29 (por `aws_subnet.ipv4_ipam_pool_id` y `ipv4_netmask_length` — R2-H2).
9. Cross-variable invariants via preconditions en recursos, no solo en variables (R2-H1).

## Registro de revisiones

- [docs/rfc/reviews/fase-1.md](reviews/fase-1.md) — R1+R2 findings, resolución, tabla completa.
- [docs/rfc/reviews/fase-2.md](reviews/fase-2.md) — R1+R2 gate cerrado en `97c89ee`.
- [docs/rfc/reviews/fase-3.md](reviews/fase-3.md) — R1+R2 gate cerrado.
- [docs/rfc/reviews/fase-4.md](reviews/fase-4.md) — R1+R2 gate cerrado en `9834664` + `724c964`.
- docs/rfc/reviews/fase-5.md … fase-6.md — pendientes.
- [docs/rfc/reviews/remediacion-1.md](reviews/remediacion-1.md) — cierre de Criticals y Highs acoplados de la primera tanda post-auditoría.
- [docs/rfc/reviews/remediacion-2.md](reviews/remediacion-2.md) — cierre de D6, IPAM secondary, fronteras y quality gates de la segunda tanda.

## Cambios del contrato introducidos en Gate 1

- `routing.transit_gateway` / `core_network`: `string` → `list(string)` [R1-C3]
- Public role: N grupos permitidos (singleton eliminado) [R1-C1]
- `ipv4.cidr_index`: nuevo campo para CIDR pinning [R1-C2]
- `vpc.igw_id`: inject-or-create para IGW [R1-H2]
- `nat_gateway.existing_ids`: inject-or-create para NAT GW [R1-H2]
- `allocation_ids`: default null (no `{}`) [R2-H2]
- Outputs renombrados: `*_by_role` → `*_by_group` + nuevo `*_by_semantic_role` [R1-H3]
- Provider floor: `>= 6.29` [R2-H2]; 5.69 queda supersedido por el schema IPAM de subnet.
- Preconditions: cidrs↔AZs, nat_gateway.az∈AZs [R2-C2, R2-C3]
- IPv6: VPC Amazon/IPAM/CIDR; subnet explícita/IPAM/calculada, `native_only` y `ipv6.cidr_index`.
- Ownership plan-known: `vpc.create`, `vpc.igw_create`, `manage_route_table`,
  `nat_gateway.create`, flags de Flow Logs y `vpc_lattice.enabled`.
- Count AZ: slice alfabético exacto y validación de capacidad del discovery.
