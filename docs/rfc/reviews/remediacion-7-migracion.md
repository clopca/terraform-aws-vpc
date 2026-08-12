# Remediación 7 — cierre del runbook de migración v4 → v5

> **Fecha:** 2026-08-13
> **Rama:** `explore/v5-typed-contract`
> **Informe de origen:** `/Users/clopca/dev/aws/aws-ia-modules/analysis/vpc-deep/reviews/remediacion-6-migracion.md`
> **Plan observado:** `/tmp/v4-fixture-3-work/v5-migration.txt`
> **Estado:** ✅ tres findings corregidos; gates locales completos en verde. La fixture AWS de la prueba #3 fue destruida por el ejecutor, por lo que la confirmación stateful posterior corresponde a la siguiente re-prueba.

## Evidencia de partida

La prueba stateful #3 validó la base del diseño: provider AWS 6.59.0 limpio sobre v4, import del log group correcto, 26 moves aplicables sin drift residual, ocho creates exactamente en la allowlist y cero replacements. No aplicó el plan porque encontró tres defectos estrechos:

1. `removed.from` publicado con índices `[0]` en segmentos `module.*`, rechazado por Terraform Core.
2. Destrucción prematura del managed policy v4 y su attachment antes de verificar la policy inline v5.
3. Updates inevitables de `tags.Name` en el Flow Log y el log group.

El plan original terminaba en `1 to import, 8 to add, 3 to change, 2 to destroy`.

## F1 — dirección `removed.from` válida

Terraform Core acepta direcciones de módulos, no instancias de módulos, dentro de `removed.from`. La forma publicada se sustituyó por:

```hcl
removed {
  from = module.vpc.module.flow_logs.module.cloudwatch_log_group.aws_cloudwatch_log_group.main

  lifecycle {
    destroy = false
  }
}
```

Los índices siguen siendo correctos para `terraform state show` y para el `moved` del IAM role; sólo se omiten en los segmentos `module.*` de `removed.from`.

Se añadió `v5/tests/fixtures/migration-root-handoff`, que contiene las tres direcciones anidadas reales. El gate ejecuta `terraform validate` directamente sobre esa raíz y `tests/migration.tftest.hcl` la vuelve a cargar en un plan nativo. Esta prueba habría rechazado la sintaxis anterior con `Module instance keys not allowed`.

## F2 — barrera de permisos con cero destroys

### Decisión

El mismo plan normal contiene tres forgets no destructivos:

- CloudWatch log group v4;
- managed IAM policy v4;
- role-policy attachment v4.

El log group se importa en la dirección v5; la policy y el attachment quedan temporalmente fuera de state pero activos en AWS. El plan puede crear `module.vpc.aws_iam_role_policy.flow_logs["default"]` sin retirar permisos antiguos. Después del apply se verifica la policy inline y la llegada de eventos nuevos; sólo entonces se limpian los dos objetos legados:

```shell
export V4_FLOW_LOG_ROLE_NAME='replace-with-generated-role-name'
export V4_FLOW_LOG_POLICY_ARN='arn:aws:iam::123456789012:policy/replace-with-generated-policy-name'

aws iam get-role-policy \
  --role-name "$V4_FLOW_LOG_ROLE_NAME" \
  --policy-name publish-vpc-flow-logs
aws iam list-entities-for-policy \
  --policy-arn "$V4_FLOW_LOG_POLICY_ARN"
aws iam detach-role-policy \
  --role-name "$V4_FLOW_LOG_ROLE_NAME" \
  --policy-arn "$V4_FLOW_LOG_POLICY_ARN"
aws iam delete-policy \
  --policy-arn "$V4_FLOW_LOG_POLICY_ARN"
```

Los valores completos se capturan antes del cutover. Los prefixes v4 por defecto son `<vpc>-cw-access-role-` y `<vpc>-cw-access-policy-`.

### Trade-off y alternativa rechazada

La barrera operativa no es expresable en el grafo de Terraform: la destrucción no puede depender de comprobar que AWS publicó eventos posteriores al apply. El diseño acepta dos objetos IAM huérfanos temporalmente para obtener cero destroys en el plan y cero ventana sin permisos.

Se rechazó reproducir policy y attachment como recursos temporales en el caller root. Esa alternativa exige duplicar todos sus argumentos/provider ownership, transferir state adicional y retirarlos en otro cambio, pero sigue sin codificar la verificación de entrega; aumenta drift y complejidad sin preservar mejor la barrera.

## F3 — `Name` configurable y compatible con v4

El contrato incorpora:

- `flow_logs[*].name_format`, default `{vpc}-{key}-flow-logs`, para el Flow Log;
- `flow_logs[*].cloudwatch_options.name_format`, default `null`, que hereda el formato del Flow Log;
- placeholders permitidos `{vpc}` y `{key}`;
- `""` como sentinel explícito para omitir `Name` y eliminar cualquier `Name` de `var.tags` o `flow_logs[*].tags` en ese recurso. Los `default_tags` del provider siguen siendo responsabilidad del provider.

La migración v4 exacta configura:

```hcl
flow_logs = {
  default = {
    name_format = "{vpc}" # Flow Log v4: Name = var.name

    cloudwatch_options = {
      name        = var.v4_flow_log_group_name
      name_format = "" # log group generado por v4: sin Name
    }
  }
}
```

Los tests fijan el default, el override independiente, la omisión incluso ante un `Name` global/caller y el rechazo de placeholders desconocidos. El ejemplo de migración expone y aserta `flow_log = "migration-example"` y `log_group_has_name = false`.

## Updates IAM aceptables en el gate

La guía enumera como esperados, para un role v4 creado por el módulo y con ID/nombre físico conservados:

- `assume_role_policy`: eliminación del `Sid` legado y adición de `aws:SourceAccount=<account-id>` más `aws:SourceArn=arn:<partition>:ec2:<region>:<account-id>:vpc-flow-log/*`; es un hardening deseable contra confused deputy.
- `description`: `Cloudwatch permissions role for <vpc> with vpc-flow-logs` → `Allows VPC Flow Logs to publish <vpc>/default logs`.

Con los formatos de migración no se acepta update de `Name` en Flow Log ni log group.

## Commits atómicos

- `c00db13 fix(v5): make flow log migration zero-destroy`
- `5a24796 feat(v5): make flow log Name tags configurable`

## Gates

| Gate | Resultado |
|---|---|
| `terraform fmt -check -recursive v5` | PASS |
| `tflint --chdir=v5 --init` | PASS |
| `tflint --chdir=v5 --recursive` | PASS, 0 findings |
| módulo + once ejemplos: init/validate | PASS, 12/12 configuraciones |
| root handoff fixture: init/validate | PASS, 1/1 |
| `terraform test -no-color` | **69 passed, 0 failed** |
| README regenerado con terraform-docs 0.19.0 | PASS |
| `git diff --check` | PASS |

## Criterio para la próxima re-prueba stateful

El primer plan v5 normal debe mostrar: un import, los moves aplicables, tres forgets no destructivos, los creates exactos de inline policy/`terraform_data`, cero destroys, cero replacements y cero updates de `Name` en Flow Log/log group. Los únicos updates IAM esperados son el trust hardening y la description enumerados arriba. Tras apply y verificación de eventos nuevos se ejecuta la limpieza IAM explícita y se exige `terraform plan -detailed-exitcode` con código 0.
