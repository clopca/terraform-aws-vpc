# Remediación tanda 4 — naming, tags y guía de migración

> **Fecha:** 2026-08-12
> **Rama:** `explore/v5-typed-contract`
> **Baseline:** `ea1b900`
> **Commits de implementación:** `f0db68e`, `dcaab57`
> **Estado:** ✅ scope de tanda 4 cerrado localmente; la reejecución AWS del fixture destruido queda como evidencia posterior, no como sustituto de los gates locales.

## Findings y resolución

| Finding | Resolución | Commit | Estado |
|---|---|---|---|
| A1 — `Name` fijo para subnet/RT/NAT/EIP/IGW | Formatos completos desacoplados de state: subnet `name_format` con `{vpc}/{group}/{az}`, RT hereda o usa `route_table_name_format`, NAT/EIP comparten formato con override por EIP, IGW/EIGW aceptan formato VPC. Los defaults conservan v5; la guía configura las fórmulas v4 exactas. | `f0db68e` | ✅ Cerrado |
| A2 — interacción con provider `default_tags` no documentada | README/RFC documentan `default_tags < var.tags < grupo/recurso < Name`, `tags_all`, precedencia de duplicados, fixes del provider >= 6.29 para los bugs históricos pre-5.0 y baseline obligatorio de defaults todavía sobre v4. No se oculta drift con `ignore_changes`. | `f0db68e` | ✅ Cerrado |
| A3 — cobertura y precedencia de tags | Auditoría contra el schema AWS 6.59 confirmó 15 tipos taggeables. Ninguno carecía totalmente de `tags`; IGW, EIP NAT y NAT Gateway carecían de una capa explícita de boundary/grupo. IGW/EIGW reciben mapas de boundary; EIP/NAT heredan tags del subnet host y admiten tags específicos. Todos conservan `merge(var.tags, ...)` y Name último. | `f0db68e` | ✅ Cerrado |
| A4 — faltaban asserts de Name override y tags | Nuevo plan test cubre subnet, route table, IGW, EIP y NAT Gateway; verifica formato completo y precedencia global/grupo/recurso/Name. El test de migración comprueba seis nombres v4 representativos. | `f0db68e`, `dcaab57` | ✅ Cerrado |
| B1 — 14 renames de Name no permitidos | Mapeo fórmula-v4 → formato-v5 añadido. El ejemplo usa `{group}-{az}`, `nat-{group}-{az}`, `{vpc}-igw` y `{vpc}`; elimina los updates de seis subnets, seis RTs, un EIP y un NAT del fixture. Se documenta como fallback aceptar sólo esos updates cosméticos enumerados. | `dcaab57` | ✅ Cerrado |
| B2 — siete creates `terraform_data` fuera de allowlist | Gate ampliado con las siete direcciones exactas observadas y regla estricta para otros subsets documentados. Son registros built-in de preconditions, sólo state, sin llamadas AWS. | `dcaab57` | ✅ Cerrado |
| B3 — `state rm` + import falla con EIP aún en clave v4 | Nuevo orden: plan/apply `-refresh-only` guardado para materializar primero los moves; verificar `nat/<az>`; después `state rm` + import consecutivos del log group. El refresh-only es transición de state, nunca el gate de aceptación. | `dcaab57` | ✅ Cerrado |
| B4 — ejemplo de 63 moves parecía universal | `moved.tf` queda anotado por feature. README/guía aclaran catálogo-unión de 63, selección real 26 y 37 fuentes ausentes, repetición por grupo privado y omisión de secciones no desplegadas. | `dcaab57` | ✅ Cerrado |

## Auditoría de tags

Taggeables cubiertos: VPC, IGW, subnet, route table, EIP, NAT Gateway, EIGW, TGW attachment, Core Network attachment, CloudWatch log group, IAM role, Flow Log, VPC Lattice association, BPA exclusion y DHCP options.

Recursos sin soporte `tags` por schema —routes, route-table associations, CIDR association, attachment accepter, BPA options, DHCP association y `terraform_data`— no pueden recibir tags del módulo ni `default_tags`.

## Evidencia

| Gate | Resultado |
|---|---|
| `terraform fmt -check -recursive v5` | PASS |
| `terraform validate -no-color` módulo + 4 ejemplos | PASS |
| `terraform test -no-color` | **50 passed, 0 failed** |
| Inventario | 12 ficheros, 50 runs, 63 bloques `assert`, 21 runs con `expect_failures` |
| Workaround macOS | `xattr -r -d com.apple.provenance` sobre `.terraform/providers` antes de validate/test |
| Reejecución AWS stateful | Pendiente: el fixture de remediación 3 fue destruido limpiamente; esta tanda corrige sus tres causas de gate, pero no inventa evidencia post-apply. |

## Decisiones

### ADR-R4-1 — Formato completo, no nombres por AZ

Un formato único cubre todos los AZs sin mapas duplicados y no participa en la dirección de state. `{group}` usa `name_prefix` o la clave estable. Un literal sin placeholders también permite un Name totalmente fijo.

### ADR-R4-2 — `default_tags` es una capa real

No se replica `default_tags` dentro del módulo ni se ignora `tags_all`. El provider hace la unión; el módulo controla sólo sus capas explícitas. Cambiar defaults es una mutación real y debe converger antes del cambio de módulo.

### ADR-R4-3 — Materializar moves antes del import

El plan refresh-only guardado existe sólo para escribir direcciones finales en state sin mutar AWS. Así el import evalúa el grafo v5 contra `nat/<az>` ya materializado. La prueba de convergencia sigue siendo un plan normal completo posterior.
