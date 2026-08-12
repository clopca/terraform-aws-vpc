# Remediación 6 — cutover declarativo de Flow Logs

> **Fecha:** 2026-08-13
> **Rama:** `explore/v5-typed-contract`
> **Finding de origen:** `/Users/clopca/dev/aws/aws-ia-modules/analysis/vpc-deep/reviews/remediacion-5-migracion.md`
> **Estado:** ✅ fix estructural implementado y gates completos en verde.

## Finding

La segunda re-prueba stateful volvió a fallar en el mismo cutover. El plan parcial que pretendía materializar `moved` blocks evaluó la configuración v5 completa antes del import posterior e indexó `aws_cloudwatch_log_group.flow_logs["default"].arn` cuando esa instancia aún no existía en state. El procedimiento tenía una dependencia circular y no alcanzaba el gate normal.

## ADR-R6-M1 — una sola transición declarativa y un solo gate normal

**Decisión:** sustituir el paso parcial y la pareja `state rm`/CLI import por configuración raíz declarativa: los `moved` blocks seleccionados, un `removed { destroy = false }` para el log group antiguo y un `import` para `module.vpc.aws_cloudwatch_log_group.flow_logs["default"]`. Un único plan normal muestra conjuntamente moves, forget e import y es el gate de aceptación.

**Detalle de versión:** `import` existe desde Terraform 1.5, pero el forget no destructivo declarativo requiere `removed`, disponible desde 1.7. El módulo conserva su floor >= 1.5; sólo el runner del cutover ownership-preserving exige >= 1.7. Terraform < 1.5 no puede ejecutar v5.

**Evidencia del provider AWS 6.59.0:** `aws_cloudwatch_log_group.name` y `.name_prefix` son `Optional + Computed + ForceNew` y conflictivos sólo en configuración. El import usa el nombre físico como ID. `resourceGroupRead` llama a `resourceGroupFlatten`, que escribe `name` desde AWS y también un `name_prefix` derivado; por tanto es falso que import deje el prefijo null. Como v5 declara el `name` exacto y omite `name_prefix`, el valor derivado queda computed y no fuerza replacement. Un move directo tras refresh limpio de provider 6.x puede converger; se prefiere remove/import porque hace explícito el cambio de ownership y refresca el destino final independientemente del snapshot nested legado.

**Plan B create-or-inject:** si un logging stack externo ya posee el grupo, `create_destination = false` más `destination_arn` conserva el destino y deja al VPC module sólo el Flow Log. No elimina la necesidad de olvidar sin destroy la dirección v4; por eso el runner de una transición declarativa sigue requiriendo Terraform >= 1.7.

## Decisión sobre `flow_logs.tf`

No se añadió `try()`/`lookup()` al acceso del ARN. La cardinalidad de `cloudwatch_destinations_to_create` y la del recurso `aws_cloudwatch_log_group.flow_logs` comparten la misma clave por contrato; silenciar una ausencia real devolvería null a la policy y al Flow Log, desplazando el fallo a un punto menos preciso y ocultando una violación interna. Con el import declarativo, la instancia destino forma parte del mismo grafo del plan normal y el índice es válido. La robustez se obtiene corrigiendo el ownership graph, no debilitando el invariante.

## Cambios

- `docs/rfc/v5-migration.md` y `v5/docs/UPGRADE-GUIDE-5.0.md`: runbook sin plan parcial ni cirugía CLI; mismo plan normal como gate.
- `v5/examples/migration-from-v4`: variable para el nombre físico, bloques root comentados por la limitación de import en child modules, diagrama y explicación del provider.
- `v5/variables.tf`: nota de migración alineada con la transición declarativa.
- El test stateful de moves se conserva: Terraform no permite import blocks dentro del child module cargado por `terraform test`; el ejemplo explica esa limitación y la sintaxis root se valida directamente.

## Gates

| Gate | Resultado |
|---|---|
| `terraform fmt -check -recursive v5` | PASS |
| `tflint --chdir=v5 --init` | PASS |
| `tflint --chdir=v5 --recursive` | PASS, 0 findings |
| módulo + once ejemplos: `terraform validate` | PASS |
| `terraform test -no-color` | **60 passed, 0 failed** |
| Smoke Terraform Core: `removed { destroy=false }` + `import` en un plan | PASS: `1 to import`, `0 to destroy` |
| `git diff --check` | PASS |
