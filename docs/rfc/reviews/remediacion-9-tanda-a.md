# Remediación 9 — Tanda A antes del freeze

Fecha de cierre: 2026-08-13
Rama: `explore/v5-typed-contract`
Base: `8a23b0c29f29a84ae992dcb10bf66d838bfe71b6`

## Fuentes de la re-auditoría

Los cambios responden a evidencia concreta de los cuatro informes requeridos:

- R1 identifica la API CIDR posicional y prescribe mapas AZ→CIDR en
  `/Users/clopca/dev/aws/aws-ia-modules/analysis/vpc-deep/reviews/re-auditoria-R1-diseno.md:25-36`;
  también identifica el accepter CWAN acoplado al attachment creado y exige una
  colección `"vpc"` independiente con matriz 2×2 en el mismo informe `:38-50`.
- R2 demuestra que dos grupos con el mismo route table físico producen recursos
  duplicados en
  `/Users/clopca/dev/aws/aws-ia-modules/analysis/vpc-deep/reviews/re-auditoria-R2-tecnica.md:73-84`.
- R3 documenta el default inseguro de public IP en
  `/Users/clopca/dev/aws/aws-ia-modules/analysis/vpc-deep/reviews/re-auditoria-R3-competitiva.md:45-49`,
  la semántica incorrecta de `isolated` en `:99-103` y los handles default ausentes
  en `:107-111`.
- R4 demuestra el quick start no instalable en
  `/Users/clopca/dev/aws/aws-ia-modules/analysis/vpc-deep/reviews/re-auditoria-R4-dx.md:124-126`,
  el warning Tier 2 en `:138-142` y los diagnósticos sin clave culpable desde `:146`.

## A1 — public IP auto-assignment opt-in

`public_options.map_public_ip` y el fallback del motor ahora son `false`, alineados
con v4. `role="public"` define routing, no exposición automática de cada ENI. Los
ejemplos que necesitan auto-assignment lo solicitan explícitamente y la guía de
migración declara la paridad de defaults.

Prueba enfocada: **15 passed, 0 failed**. Commit:

- `ee3862546579f91825d02b5aa98da61ea42ac030` — `fix(v5): make public IP assignment opt-in`

## A2 — CIDRs explícitos keyed por AZ

ADR-R9-A2 elimina sin adapter los campos posicionales `ipv4.cidrs`/`ipv6.cidrs` y
publica `cidrs_by_az = map(string)`. La clave debe coincidir exactamente con cada AZ
configurada; el motor resuelve el CIDR por `az`, no por índice. Guía, runbook,
ejemplo `migration-from-v4`, once ejemplos y tests usan el nuevo contrato.

La regresión before/after inserta `us-east-1b` entre `us-east-1a` y `us-east-1c` y
prueba que los CIDRs existentes permanecen asociados a sus claves. El scan final de
`v5/`, RFC y migración encuentra **0** referencias activas a los campos posicionales.

Prueba enfocada: **25 passed, 0 failed**. Commits:

- `34ae1c334f35f88fd885395eb876a931fd157b14` — `refactor(v5): key explicit CIDRs by AZ`
- `9b57cc81466265ad328485e04000f6661aad119a` — `refactor(v5): remove obsolete AZ count local`

## A3 — identidad física de route tables inyectados

Inject mode exige `route_table_key` caller-owned además del ID efectivo. Grupos que
comparten tabla reutilizan la misma key y el mismo ID. Sus asociaciones de subnet se
mantienen por `<group>/<az>`, pero routing se une y cada ruta/asociación de endpoint
se crea una sola vez bajo `injected/<route_table_key>/...`. Se rechaza una key con
IDs distintos y un ID conocido bajo keys distintas; `for_each` nunca depende del ID.

Prueba enfocada: **17 passed, 0 failed**. Commit:

- `91a884dc93b059fbbfb935b85aefdd6b95181333` — `fix(v5): model shared route table identity`

## A4 — accepter Cloud WAN independiente

`local.core_network_accepter` usa la clave constante `"vpc"`, cardinalidad basada
sólo en `require_acceptance`, `accept_attachment` y `create_accepter`, y recibe
`local.core_network_attachment_id`, sea creado o inyectado. La suite fija las cuatro
combinaciones attachment/accepter create-create, create-inject, inject-create e
inject-inject.

Prueba enfocada: **10 passed, 0 failed**. Commit:

- `7f2ea8da03cc629ca4018294d9d2f02b21c4f888` — `fix(v5): decouple Cloud WAN accepter ownership`

## A5 — isolated sin Internet, con endpoints privados

ADR-R9-A5 redefine `isolated` como ausencia de IGW, NAT/NAT64, EIGW, TGW y Cloud
WAN. S3 y DynamoDB Gateway Endpoints se permiten porque no proporcionan routing
general a Internet. Una regresión crea ambos endpoints en un grupo isolated y
verifica dos asociaciones y cero gateways de egress.

Prueba enfocada: **20 passed, 0 failed**. Commit:

- `8ffded7cbe6631e5d9cfa82db7b025ea1cee8229` — `fix(v5): allow gateway endpoints in isolated subnets`

## A6 — handles Tier 1 de recursos default

Tier 1 añade `default_security_group_id`, `default_network_acl_id`,
`default_route_table_id` y `main_route_table_id`; `default_resource_ids` queda
siempre poblado. VPCs creadas usan atributos computed de `aws_vpc`; VPCs inyectadas
usan lookups acotados. Observar IDs no crea ningún `aws_default_*` y los tres
selectores de adopción siguen en `false`.

Prueba enfocada: **17 passed, 0 failed**. Commit:

- `d2a1e5179ea937a830fda9bc1dfc979583f9f170` — `feat(v5): expose default VPC resource IDs`

## A7 — consumo externo y findings Medium de R4

Usage usa
`git::https://github.com/clopca/terraform-aws-vpc.git//v5?ref=explore/v5-typed-contract`,
declara provider `>=6.29` y explica el futuro source Registry. Copiado a un proyecto
vacío, `terraform init -backend=false` terminó con
`Terraform has been successfully initialized!`.

R4-M03 queda cerrado: los mensajes de role, netmask, pinning y create/inject incluyen
la key y valor culpable; `existing_ids` informa grupo, AZs esperadas y recibidas. El
diagnóstico CIDR duplicado señalado por E09 desapareció al reemplazar cardinalidad
posicional por una única validación exacta de keys.

R4-M02 se difiere explícitamente: `vpc_attributes` debe conservar el objeto provider
completo para compatibilidad v4 durante v5. Proyectarlo eliminaría atributos y sería
breaking. La suite registra tres bloques del único warning conocido
`data.aws_vpc.existing[0].ipv6_association_id`; cualquier warning distinto es deuda
nueva. Tier 2 se elimina en v6.

Prueba enfocada: **21 passed, 0 failed**. Commit:

- `688e06cf02332127afae1aa32b8cccf43303a90d` — `docs(v5): make quick start externally consumable`

## Reserva transversal para grupo C

El RFC y README reservan crecimiento aditivo dentro de objetos existentes, sin
aceptar inputs no-op en 5.0:

- `subnets[*].dns_on_launch` para A/AAAA y hostname type;
- opciones CWAN de DNS, SG referencing y routing-policy label;
- EIP desde pool público IPAM dentro de `nat_gateway.eip`.

Añadir atributos `optional` dentro de esos objetos es el camino compatible 5.x; no
se crea aún ningún recurso ni pass-through.

## Gates completos

Headroom previo: **AMPLE**, 14.7 GB disponibles, 14 cores, carga 0.55/core.

Versiones:

- Terraform `1.15.8`;
- TFLint `0.63.1`;
- terraform-docs `0.19.0` (`af31cc6`, darwin/arm64).

| Gate | Resultado |
|---|---|
| `terraform fmt -check -recursive v5` | PASS |
| `tflint --chdir=v5 --init` | PASS |
| `tflint --chdir=v5 --recursive` | PASS, 0 findings |
| módulo init + validate | 2/2 PASS |
| 11 ejemplos init + validate | 22/22 PASS |
| quick start externo `terraform init -backend=false` | PASS |
| suite completa `terraform test -no-color` | **91 passed, 0 failed** |
| `git diff --check` | PASS |

Pasaron los 19 archivos `.tftest.hcl`:

- `availability_zones`, `cidr_engine`, `computed_inputs`;
- `core_network_accepter`, `default_resources`, `examples`;
- `gateway_endpoints`, `injection`, `ipv6`, `lattice`, `migration`;
- `naming_tags`, `network_acls`, `output_shapes`, `regional_nat`;
- `route_table_identity`, `secondary_ipam`, `validations`, `vpc_features`.

Son 29 comandos del gate principal más el init externo. README fue regenerado con
terraform-docs 0.19.0 después de cada cambio de contrato.

## Alcance

Las pruebas funcionales usan plan/apply mock; no hubo apply ni consulta a una cuenta
AWS real. No se ejecutó `git push`. Este lote no resuelve los gates live/stateful de
release señalados por R1/R2; su alcance son los siete fixes de contrato pre-freeze.
