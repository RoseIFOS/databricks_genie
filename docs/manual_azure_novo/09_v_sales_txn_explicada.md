# 09 — `v_sales_txn` explicada (a view plana da camada semântica)

> **O que é este arquivo:** a *view plana* (`4_semantic.v_sales_txn`) que alimenta a
> metric view `mv_comercial`. Ela pega os fatos comerciais (vendas + devoluções) no grão
> de **linha** e cola ao lado os atributos de cliente, geografia, produto e tempo — o
> "retângulo largo" pronto pro Genie fatiar. Nenhum cálculo de negócio complexo aqui: só
> **denormalização** (juntar tudo) e o **lookup do custo unitário**.

---

## 1. Desenho geral (leia isto primeiro)

```
v_sales_txn
├── CTE sales    ← fct_sales_details    + dims + lookup de custo   (transaction_type = 'sale')
├── CTE returns  ← fct_sales_returns    + dims                     (transaction_type = 'return')
└── SELECT sales  UNION ALL  SELECT returns
```

São **duas consultas com o mesmo formato de colunas**, empilhadas uma sobre a outra com
`UNION ALL`. A coluna `transaction_type` (`'sale'` / `'return'`) marca a origem de cada linha —
depois a metric view usa isso pra separar "Vendas" de "Devoluções".

> **Por que empilhar?** No Power BI, vendas e devoluções eram fatos separados ligados às
> mesmas dimensões. Aqui juntamos os dois num só fluxo, o que deixa medidas como
> `% Returns` (devolução ÷ venda) triviais de calcular na metric view.

---

## 2. CTE `sales` — bloco a bloco

```sql
'sale' AS transaction_type,
```
Marca fixa: toda linha desta CTE é uma venda.

```sql
sd.customer_key, sd.product_key, sd.region_key,        -- CHAVES
dc.customer_name, dc.business_type,                    -- atributos do cliente
dg.region_name, dg.country_name, dg.state_name,        -- geografia
dg.city_name, dg.continent,
dp.category_name, dp.subcategory_name, dp.product_name,-- produto
```
**Denormalização.** Traz as chaves + os textos que o usuário vai querer ver/filtrar
("mostre vendas por categoria em São Paulo"). Sem isso o Genie teria que adivinhar os
joins.

```sql
sd.order_date,
year(sd.order_date)  AS order_year,
month(sd.order_date) AS order_month,
```
Data + ano/mês já derivados. O ano/mês servem **duas coisas**: fatiar por tempo **e** casar
com o histórico de custo (que é mensal) no lookup abaixo.

```sql
sd.order_quantity                                        AS quantity,
sd.unit_price,
CAST(sd.order_quantity * sd.unit_price AS DECIMAL(18,4)) AS gross_amount,   -- Gross Sales
sd.discount_allocated                                    AS discount_amount,-- Discounts (rateado)
```
As **métricas de venda**, com o nome alinhado ao DAX do Power BI:
- `gross_amount` = quantidade × preço = **Gross Sales**.
- `discount_amount` = o desconto do pedido já **rateado à linha** (vem pronto do
  `fct_sales_details.discount_allocated`).

```sql
pch.unit_cost AS unit_cost   -- lookup do custo
```
O **custo unitário** vindo do histórico — a peça que permite calcular margem depois.

### O lookup de custo (a parte mais delicada)
```sql
LEFT JOIN hpn.`3_gold`.fct_product_cost_history pch
  ON  pch.product_key  = sd.product_key
  AND pch.year         = year(sd.order_date)
  AND pch.month_no     = month(sd.order_date)
  AND pch.country_code = dg.country_code
```
O custo não é fixo: varia por **produto × ano/mês × país**. Então, para cada linha de
venda, buscamos o custo daquele produto, no mês do pedido, no país do cliente. É um
`LEFT JOIN` (não `JOIN`) de propósito: se não houver custo cadastrado pra aquela
combinação, a venda **não some** — o `unit_cost` fica `NULL`.

> Isto espelha a coluna calculada `[Unit Cost]` do Power BI (um `LOOKUPVALUE`).

### Os JOINs de dimensão
`fct_sales_details → dim_customer → dim_geography` e `→ dim_product` são `JOIN` (inner):
assume-se que toda venda tem cliente/geografia/produto válidos. Se alguma chave estiver
órfã, a linha cai — vale conferir na paridade.

---

## 3. CTE `returns` — só as diferenças

Mesmas colunas, mesma ordem. O que muda:

| Ponto | `sales` | `returns` | Por quê |
|---|---|---|---|
| `transaction_type` | `'sale'` | `'return'` | marca a origem |
| region_key | `sd.region_key` (do fato) | `dg.region_key` (via cliente) | **devolução não tem região própria** → puxa da geografia do cliente |
| quantidade | `order_quantity` | `return_quantity` | grão do fato de devolução |
| `gross_amount` | qty × preço (venda) | qty × preço (**Returns**) | mesma fórmula, outro fato |
| `discount_amount` | rateado | `0` | devolução não tem desconto |
| `unit_cost` | lookup | `NULL` | não calculamos margem de devolução |

> Os `CAST(0 AS DECIMAL(18,4))` e `CAST(NULL AS DECIMAL(18,4))` existem pra **casar o
> tipo** das colunas com a CTE `sales` — o `UNION ALL` exige que cada coluna tenha o
> mesmo tipo dos dois lados.

---

## 4. O `UNION ALL`

```sql
SELECT * FROM sales
UNION ALL
SELECT * FROM returns;
```
`UNION ALL` empilha **sem remover duplicatas** (mais rápido e correto aqui — venda e
devolução são eventos distintos, nunca "duplicados"). Requisito: as duas CTEs precisam ter
**o mesmo número de colunas, na mesma ordem, com tipos compatíveis** — por isso o cuidado
com os `CAST` na CTE `returns`.

---

## 5. ⚠️ Pontos de atenção (validar na paridade)

1. **O lookup de custo pode multiplicar linhas.** O `LEFT JOIN` só é seguro se
   `fct_product_cost_history` tiver **no máximo 1 linha** por (produto, ano, mês, país). Se
   houver duplicata nesse grão, cada venda vira 2+ linhas e o `gross_amount` **infla**.
   → Antes de confiar, rode um `GROUP BY product_key, year, month_no, country_code
   HAVING COUNT(*) > 1` no histórico de custo. Se voltar linhas, o lookup precisa de
   dedup.

2. **`unit_cost` NULL quebra margem se não for tratado.** Vendas sem custo casado (e todas
   as devoluções) têm `unit_cost = NULL`. Ao calcular *Cost of Sales* / *Margem* na metric
   view, `quantity * unit_cost` vira `NULL` — então some/ignore com cuidado
   (`COALESCE`/filtro) pra não sumir com receita legítima. Decida a regra e documente.

3. **INNER JOIN nas dimensões descarta órfãos.** Se existir venda com `product_key` que
   não está em `dim_product`, ela **desaparece** da view. Confirme que os totais de
   `gross_amount` batem com o `SUM(gross_sales)` do `fct_sales_details` puro.

---

## 6. Resumo em uma frase

> `v_sales_txn` = (vendas + devoluções) no grão de linha, **denormalizadas** com
> cliente/geografia/produto/tempo e enriquecidas com **custo unitário**, empilhadas com
> `UNION ALL` e marcadas por `transaction_type` — pronta para a `mv_comercial` declarar as medidas
> por cima.
