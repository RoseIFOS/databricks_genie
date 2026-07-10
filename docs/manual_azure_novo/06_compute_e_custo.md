# 06 — Compute serverless & FinOps

> Substitui: *"Criar um cluster"* + *"Criar token de acesso"* (PAT) de
> *"Criando Recursos na Azure"*.

## Fim do all-purpose cluster + PAT

O manual antigo pedia para criar um **all-purpose cluster** e um **Personal
Access Token (PAT)** para o ADF conectar. Dois problemas modernos:
- All-purpose cluster fica ligado gastando DBU; dimensioná-lo é manual.
- PAT é **credencial de longa duração** que pode vazar (e o antigo chegou a
  imprimir secret no notebook).

## O que usar agora

| Uso | Compute recomendado |
|---|---|
| Genie / BI / SQL Editor | **SQL Warehouse serverless** (auto-stop) |
| Pipeline declarativo (cap. 04) | **Serverless** do pipeline |
| Jobs / notebooks ad-hoc | **Serverless job compute** |
| ADF → Databricks | **Managed identity** (não PAT) |

Serverless liga sob demanda e desliga sozinho — melhor para custo e sem cluster
para gerenciar. Onde precisar de cluster clássico, habilite **auto-stop** curto.

## FinOps desde o dia 1 (Fase 9 do plano)
- **Tags obrigatórias** (cost center, ambiente, domínio) em warehouses, jobs e pipelines.
- Dashboard sobre **`system.billing.usage`** (DBU por warehouse/job/serving).
- **Budgets** + alertas por cost center.
- Auto-stop nos warehouses; right-sizing dos endpoints.

## Observabilidade (Fase 9)
- **`system.query.history`** e Query History p/ analisar consultas do Genie/app.
- **Lakehouse Monitoring** nas tabelas gold (drift/qualidade).
- **MLflow Tracing** no app e nos modelos.

## Autenticação sem PAT (resumo)
- ADF → Databricks: **managed identity**.
- Databricks → ADLS: **Access Connector** (cap. 02).
- App/Genie → dados: identidade do usuário (**OBO**) para herdar a RLS do UC
  (ver [`app/genie_client.py`](../../app/genie_client.py)).
- Secrets de terceiros: **secret scopes** (Key Vault-backed), nunca em código.

## Checklist de saída
- [ ] SQL Warehouse serverless com auto-stop.
- [ ] Pipelines/jobs em serverless.
- [ ] Nenhum PAT; ADF por managed identity.
- [ ] Tags de custo + budget + monitoramento ligados.
