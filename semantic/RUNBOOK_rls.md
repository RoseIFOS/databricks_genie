# RUNBOOK — Aplicação do RLS + Grants (Fase 4)

> **Quando executar:** por último, **depois** de testar uma v1 do Genie sem RLS.
> Fonte: [`03_rls.sql`](03_rls.sql). Tudo roda no **SQL Editor** (SQL Warehouse), catálogo `hpn`.
>
> **Por que por último:** o row filter e a máscara *trancam* o acesso. Testar o Genie
> sem eles primeiro isola problemas (modelo/medidas) da camada de segurança.

---

## ⚠️ Antes de começar — pré-requisitos (senão você se tranca pra fora)

- [ ] Os grupos de conta existem: **`grp_admin`**, `grp_comercial`, `grp_financeiro`
      (Databricks → Settings → Identity and access → Groups).
- [ ] **Você é membro de `grp_admin`.** Sem isso, ao aplicar o row filter você vê
      **zero** linhas de geografia e o comercial fica vazio pra você.
- [ ] O mapa `map_rls_region` está populado com quem vê qual região.

---

## Passo 1 — Criar mapa, funções e (se os grupos existirem) grants  ⏱️ 2 min

No SQL Editor, rode o [`03_rls.sql`](03_rls.sql) **até o fim da seção 4** (mapa +
`rls_region` + `mask_revenue` + grants). Os `ALTER` da seção 5 estão comentados — não
executam nada ainda.

- [ ] `map_rls_region`, `rls_region`, `mask_revenue` criados.
- [ ] Grants rodaram (só se os grupos já existirem; senão, pule e volte aqui depois).

---

## Passo 2 — Popular o mapa regional  ⏱️ 2 min

```sql
-- region tem que casar EXATAMENTE com dim_geography.region_name
SELECT DISTINCT region_name FROM hpn.`3_gold`.dim_geography ORDER BY 1;  -- ver os valores válidos

INSERT INTO hpn.`4_semantic`.map_rls_region VALUES
  ('vendedor.norte@bix.com', 'North'),
  ('vendedor.sul@bix.com',   'South');
-- Admins NÃO precisam entrar no mapa (a função já os libera via is_account_group_member).
```
- [ ] Mapa reflete a realidade de quem vê o quê.

---

## Passo 3 — Sanity check ANTES de aplicar (não trava nada)  ⏱️ 2 min

Confirme que a função responde certo pro seu usuário:
```sql
SELECT current_user()                         AS eu,
       is_account_group_member('grp_admin')   AS sou_admin,          -- deve ser TRUE p/ você
       hpn.`4_semantic`.rls_region('North')   AS vejo_north;         -- TRUE se admin ou mapeado
```
- [ ] `sou_admin = true` (se não, **pare** e resolva o grupo antes de aplicar).

---

## Passo 4 — APLICAR o filtro e a máscara  ⚠️ (trancam o acesso)  ⏱️ 1 min

Descomente/rode a **seção 5** do `03_rls.sql`:
```sql
ALTER TABLE hpn.`3_gold`.dim_geography
  SET ROW FILTER hpn.`4_semantic`.rls_region ON (region_name);

ALTER TABLE hpn.`3_gold`.dim_customer
  ALTER COLUMN annual_revenue SET MASK hpn.`4_semantic`.mask_revenue;
```
- [ ] Aplicado sem erro.

---

## Passo 5 — Validar o comportamento  ⏱️ 5 min

Como **admin** (você): tudo continua visível.
```sql
SELECT COUNT(DISTINCT region_name) FROM hpn.`3_gold`.dim_geography;  -- todas as regiões
SELECT MEASURE(`Gross Sales`) FROM hpn.`4_semantic`.mv_comercial;    -- total cheio
```
- [ ] Admin vê tudo; `annual_revenue` legível.

Como **usuário restrito** (peça a alguém do `grp_comercial` mapeado a uma região, ou
crie um usuário de teste): só a região dele aparece e `annual_revenue` vem NULL.
- [ ] Não-admin vê só a própria região.

---

## Rollback — se precisar destravar

```sql
ALTER TABLE hpn.`3_gold`.dim_geography DROP ROW FILTER;
ALTER TABLE hpn.`3_gold`.dim_customer ALTER COLUMN annual_revenue DROP MASK;
```

---

### Ordem resumida
```
0. Pré-req: grupos existem + você no grp_admin + mapa populado
1. 03_rls.sql (até seção 4)     → mapa + funções + grants
2. INSERT no map_rls_region     → quem vê o quê
3. Sanity check (rls_region)    → NÃO trava
4. ALTER ... ROW FILTER / MASK  → ⚠️ trancam (só com grp_admin ok)
5. Validar admin vs restrito
```
