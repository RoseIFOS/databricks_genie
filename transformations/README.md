# transformations/ — camadas de transformação da Lakeflow Declarative Pipeline

SQL declarativo (o antigo DLT) que constrói o medallion **a partir do Bronze**.
A ingestão (landing → `1_bronze`) fica em notebooks metadata-driven, **não** aqui.

```
transformations/
  silver/   1:1 com a origem — cast, trim, snake_case, dedup, auditoria, expectations
  gold/     (a fazer) star schema, regra de negócio, comentários por coluna p/ Genie
```

**Convenção Silver** (ver também [MEDALLION_CHECKLIST.md](../MEDALLION_CHECKLIST.md)):
- 1 arquivo por tabela, numerado na ordem do checklist.
- `CREATE OR REFRESH MATERIALIZED VIEW` (Bronze é OVERWRITE → MV recomputa; não STREAMING).
- Chaves `<x>key` → `<x>_key`; `TRIM()` em texto; `CAST` explícito.
- Colunas técnicas com prefixo `_`: `_source_id`, `_silver_loaded_at`.
- Dedup: `QUALIFY ROW_NUMBER() OVER (PARTITION BY <chave> ORDER BY id DESC) = 1`.
- Expectations mínimas (chave não nula etc.); comentário só de tabela (por coluna = Gold).
