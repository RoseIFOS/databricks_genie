# 05 — Orquestração com Lakeflow Jobs

> Substitui: rodar notebook na mão (célula a célula) e o disparo solto do ADF.

No manual antigo não havia orquestração de verdade: você rodava os notebooks
`1.Bronze / 2.Silver / 3.Gold` manualmente. Agora **Lakeflow Jobs** (o antigo
Workflows) encadeia tudo, com schedule, retries e alertas.

## O fluxo orquestrado

```
[ADF landing OU Lakeflow Connect]  →  trigger  →  Lakeflow Job:
     task 1: pipeline declarativo (bronze → silver → gold)
     task 2: (Fase 6) job de forecast/ML  [depende da task 1]
     on failure → alerta por e-mail
```

## Montando o Job (UI)
**Workflows/Jobs → Create job**:
1. **Task 1** — tipo *Pipeline*, aponte para o pipeline declarativo do cap. 04.
2. **Task 2** (opcional) — tipo *Notebook/Python*, o `ml/forecast_sales.py` do
   projeto, com **dependência** na task 1 (só roda se o DW atualizou).
3. **Compute**: serverless (cap. 06).
4. **Schedule**: ex. diário às 05:00 (o forecast do projeto já assume isso).
5. **Notifications**: e-mail em falha → `roseane.silva@bix-tech.com`.

## Encadeando com a ingestão
- **Caminho ADF (cap. 03-A):** no fim do pipeline ADF, adicione uma atividade
  que dispara o Job Databricks (via managed identity, sem PAT). Landing pronta →
  Job roda.
- **Caminho Lakeflow Connect (cap. 03-B):** o pipeline de ingestão pode ser a
  primeira task do próprio Job, tudo dentro do Databricks.

## Versionamento (liga com a Fase 10)
Este Job **já está descrito como Asset Bundle** no projeto:
[`resources/ml_forecast_job.yml`](../../resources/ml_forecast_job.yml) +
[`databricks.yml`](../../databricks.yml). Ou seja, dev → prd é reproduzível via
`databricks bundle deploy -t dev|prd`. Veja o
[GUIA_ASSET_BUNDLE.md](../../GUIA_ASSET_BUNDLE.md).

## Checklist de saída
- [ ] Job encadeando pipeline (+ ML opcional) com dependências.
- [ ] Trigger a partir da ingestão, sem PAT.
- [ ] Schedule + alerta de falha configurados.
- [ ] Job versionado no Asset Bundle.
