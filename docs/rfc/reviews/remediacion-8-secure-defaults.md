# Remediación 8 — Secure defaults

Fecha de cierre: 2026-05-01
Rama: `explore/v5-typed-contract`
Base del lote: `85a26aa` (`docs(v5): record migration remediation 7`)

## Resultado

El lote implementa tres controles opt-in sin alterar el plan de migración v4 cuando
se omiten: adopción y endurecimiento de recursos VPC predeterminados, endpoints
Gateway tipados para S3/DynamoDB y NACL tipadas por grupo de subred. No se modificó
`v5/docs/UPGRADE-GUIDE-5.0.md`, `docs/rfc/v5-migration.md` ni ningún runbook de
migración.

## Bloque 1 — recursos VPC predeterminados

`default_resources` adopta, no reemplaza, el security group, NACL y route table que
AWS crea con la VPC. Los tres selectores son `false` por defecto y cada colección usa
la clave estable `"default"`. Al optar, el módulo elimina reglas SG, reglas allow de
la NACL predeterminada, rutas no locales y propagación del route table principal;
además aplica nombres y tags con precedencia determinista.

La NACL predeterminada se resuelve con `data.aws_network_acls` filtrado por
`default=true`; el route table principal con `data.aws_route_table` y
`association.main=true`. Los IDs adoptados se exponen en `default_resource_ids` y
los objetos completos en `resources.default_resources`.

Prueba transversal de migración: `tests/migration.tftest.hcl` verifica cero recursos
gestionados e IDs nulos al omitir `default_resources`. El gate enfocado del bloque
cerró con **16 passed, 0 failed**: 2 defaults + 4 migración + 10 ejemplos.

Commit:

- `ae5d896ed125fd76b0f2283dfdb25f7405e4ec23` — `feat(v5): harden default VPC resources`

## Bloque 2 — endpoints Gateway S3/DynamoDB

`gateway_endpoints` es un mapa con clave estable del caller y `service` explícito
(`s3` o `dynamodb`). Esto permite validar en plan que exista como máximo un endpoint
por servicio sin sacrificar identidad de estado. Create mode crea
`aws_vpc_endpoint`; inject mode exige `create=false` e `endpoint_id`, y no acepta
política porque el módulo no posee ese endpoint. La política opcional de create mode
debe ser JSON válido.

El routing se declara junto al grupo de subred mediante
`s3_gateway_endpoint`/`dynamodb_gateway_endpoint`. Las asociaciones usan
`<group>/<az-or-injected>/gateway-endpoint/<service>`; un route table compartido e
inyectado recibe una sola asociación. La clave del endpoint creado sigue siendo la
clave del caller. El ejemplo `basic` crea ambos servicios y documenta que sus rutas
evitan el cargo de procesamiento por GB del NAT Gateway para tráfico S3/DynamoDB.

El gate enfocado del bloque cerró con **14 passed, 0 failed**: 4 contratos de
endpoint + 10 ejemplos.

Commit:

- `87afb5995266a9064e162767ac1f53042a52244b` — `feat(v5): add gateway VPC endpoints`

## Bloque 3 — NACL por grupo de subred

Cada grupo puede omitir `network_acl`, crear una NACL o inyectar su ID. Inject mode
no posee identidad, Name ni tags de la NACL, pero sí gestiona las reglas declaradas
y asociaciones. La ausencia del bloque produce cero NACL, reglas y asociaciones y
conserva el comportamiento de la NACL predeterminada de AWS.

Las reglas ingress/egress son mapas cuya clave es el número AWS canónico
`1..32766`. Las direcciones pueden reutilizar el mismo número sin colisión. Direcciones
de estado:

- NACL: `<group>`;
- regla: `<group>/<ingress|egress>/<rule-number>`;
- asociación: `<group>/<az>`.

Las validaciones cubren ownership create/inject, formato de nombre, número de regla,
protocolo, acción allow/deny, exactamente una familia CIDR, puertos enteros ordenados
`0..65535` e ICMP type/code. `icmpv6` se normaliza al protocolo AWS `58`.

El ejemplo `secure_isolated` crea NACL separadas para `control` y `enclave`: permite
TCP/443 control→enclave y modela explícitamente el retorno stateless por puertos
efímeros. La documentación recomienda no usar NACL cuando security groups stateful
sean suficientes o no se puedan probar ambas direcciones.

El gate enfocado del bloque cerró con **15 passed, 0 failed**: 5 contratos NACL + 10
ejemplos.

Commit:

- `824e13481cc2dd4a21e87a2522f5c3deab0a7900` — `feat(v5): add typed subnet network ACLs`

## Evidencia de gates completos

Headroom previo: **AMPLE**, 14.6 GB disponibles, 14 cores, carga 0.33/core.

Versiones:

- Terraform `1.15.8`;
- TFLint `0.63.1`;
- terraform-docs `0.19.0` (`af31cc6`, darwin/arm64).

README se regeneró con terraform-docs 0.19.0 tras cada bloque. Gates finales:

| Gate | Resultado |
|---|---|
| `terraform fmt -check -recursive v5` | PASS |
| `tflint --chdir=v5 --init` | PASS |
| `tflint --chdir=v5 --recursive` | PASS |
| módulo `terraform init -backend=false` + `validate` | 2/2 PASS |
| 11 ejemplos `init -backend=false` + `validate` | 22/22 PASS |
| `terraform -chdir=v5 test -no-color` | **80 passed, 0 failed** |
| `git diff --check` | PASS |

Los 17 archivos de test pasaron: availability zones, CIDR engine, computed inputs,
default resources, 10 ejemplos, gateway endpoints, injection, IPv6, Lattice,
migración, naming/tags, NACL, output shapes, Regional NAT, secondary IPAM,
validaciones y VPC features. La suite emitió dos bloques del warning ya existente
del provider sobre `ipv6_association_id`; no produjo fallos.

Son **29 comandos de gate aprobados**: formato (1), TFLint (2), módulo (2), 11
ejemplos init/validate (22), suite completa (1) y diff check (1).

## Alcance de la evidencia

Todas las pruebas funcionales fueron `terraform plan` con mock provider. Los gates
de ejemplos fueron init/validate. No se ejecutó apply ni se consultó/modificó una
cuenta AWS real; por tanto, este registro no afirma validación live en AWS.

No se ejecutó `git push`. Al cerrar los tres bloques, la rama no tenía upstream.
