# 10 — `mv_comercial` explicada (a metric view comercial)

> **O que é este arquivo:** a *metric view* (`4_semantic.mv_comercial`) — a camada
> semântica de fato. Ela fica **em cima da view plana `v_sales_txn`** e declara, em YAML,
> as **dimensões** (por onde fatiar) e as **medidas** (o que calcular). É o objeto que o
> Genie consome; equivale ao modelo semântico + medidas DAX do Power BI, mas versionado.

---

## 1. Cabeçalho

```yaml
version: 0.1
source: hpn.`4_semantic`.v_sales_txn
```
- `version` — versão do *formato* do YAML da metric view (não é a versão do seu modelo).
- `source` — a tabela/view que alimenta tudo. Aqui aponta pra **view plana** que já uniu
  vendas + devoluções + dimensões + custo. Toda `expr` abaixo se refere a colunas **dessa**
  view.

---

## 2. `dimensions` — por onde fatiar

```yaml
- name: Ano
  expr: order_year
```
Cada dimensão é um par **nome de negócio → coluna da view**:
- `name` — o rótulo que o usuário/Genie vê ("Ano", "Cliente", "Categoria"). É **linguagem
  de negócio**, em PT-BR.
- `expr` — a coluna real na `v_sales_txn` (`order_year`, `customer_name`, ...).

**Não há agregação em dimensão** — ela só define os eixos/filtros possíveis. As suas 11
dimensões cobrem tempo (Data/Ano/Mes), cliente (Cliente/TipoNegocio), geografia
(Regiao/Pais/Cidade) e produto (Categoria/Subcategoria/Produto).

> É o equivalente às colunas que você arrastaria pra um eixo/segmentação no Power BI.

---

## 3. `measures` — o que calcular

Cada medida é um par **nome de negócio → fórmula agregada**. Aqui mora a regra de negócio.

### O padrão `CASE WHEN txn_type = 'sale' ...` (entenda isto primeiro)
A view plana tem **vendas E devoluções empilhadas** (`UNION ALL`). Logo, um `SUM(gross_amount)`
cru **misturaria** os dois. Por isso quase toda medida filtra o tipo:

```yaml
- name: Gross Sales
  expr: SUM(CASE WHEN txn_type = 'sale' THEN gross_amount END)
```
Lê-se: "some `gross_amount`, mas só das linhas de **venda**". O `CASE` sem `ELSE` devolve
`NULL` para devoluções, e **`SUM` ignora `NULL`** — então sobra só a venda. `Returns` faz o
espelho com `= 'return'`.

### Medidas base (uma agregação direta cada)
| Medida | Fórmula (resumo) | DAX equivalente |
|---|---|---|
| **Gross Sales** | `SUM(gross_amount)` só vendas | `SUMX(qty*price)` |
| **Returns** | `SUM(gross_amount)` só devoluções | `SUMX(returns)` |
| **Discounts** | `SUM(discount_amount)` | `SUM(Discount Amount)` |
| **Cost of Sales** | `SUM(quantity*unit_cost)` só vendas | `SUMX(qty*[Unit Cost])` |
| **Quantity** | `SUM(quantity)` só vendas | `SUM(OrderQuantity)` |
| **Customers Current** | `COUNT(DISTINCT customer_key)` só vendas | `DISTINCTCOUNT(CustomerKey)` |

### Medidas compostas — e por que se **repetem** (o ponto que confunde)
No Power BI, `Net Sales = [Gross Sales] − [Discounts] − [Returns]` — uma medida
**referencia** a outra. **Metric view (v0.1) NÃO permite** uma measure chamar outra. Então
cada composta precisa **reescrever a fórmula inteira inline**:

```yaml
- name: Net Sales
  expr: >
    SUM(CASE WHEN txn_type = 'sale' THEN gross_amount END)   -- Gross Sales
    - SUM(discount_amount)                                   -- - Discounts
    - SUM(CASE WHEN txn_type = 'return' THEN gross_amount END)-- - Returns
```
É por isso que `Net Sales`, `Gross Margin`, `Gross Margin %` e `Net Margin %` parecem
"copiar e colar" os mesmos blocos: **não há como reaproveitar** `[Gross Sales]` como no DAX.

> **O `>` do YAML** ("folded scalar") só junta as várias linhas numa expressão só, pra
> ficar legível. É formatação, não lógica.

### Percentuais e o `NULLIF` (proteção contra ÷ 0)
```yaml
- name: "% Returns"
  expr: >
    SUM(... 'return' ...) / NULLIF(SUM(... 'sale' ...), 0)
```
`NULLIF(x, 0)` devolve `NULL` se o denominador for 0 → a divisão vira `NULL` em vez de
**estourar erro**. É o equivalente exato do `DIVIDE()` do DAX (que também blinda o ÷ 0).

> `"% Returns"` está entre **aspas** porque começa com `%` — em YAML, nomes com caracteres
> especiais precisam ser citados.

### Médias (não-aditivas)
`Avg Unit Price` e `Avg Unit Cost` usam `AVG(...)` só das vendas. Atenção: é média
**simples** por linha de pedido (igual ao `AVERAGE()` do DAX) — **não** é ponderada por
quantidade. Se o negócio esperar preço médio ponderado, a fórmula seria
`SUM(gross_amount)/SUM(quantity)` — confirme qual definição o Power BI usa.

---

## 4. ⚠️ Pontos de atenção

1. **Consistência do nome da coluna de tipo.** Você decidiu renomear `txn_type` →
   `transaction_type` na view. Se fizer isso, **todas as `expr` deste YAML** que citam
   `txn_type` precisam mudar junto — senão a metric view quebra (coluna inexistente).
   (Este arquivo ainda mostra `txn_type` porque é o que você colou.)

2. **Fórmula repetida = manutenção em vários lugares.** Como as compostas reescrevem
   `Gross Sales` inline, mudar a definição de venda bruta exige alterar **todas** as
   medidas que a usam (Net Sales, as duas margens, % Returns). Não há fonte única. Ao
   editar, use "localizar e substituir" com cuidado.

3. **`unit_cost` NULL subestima `Cost of Sales`.** Vendas sem custo casado no lookup têm
   `unit_cost = NULL` → `quantity * unit_cost` = `NULL` → o `SUM` **ignora** essa linha.
   Resultado: `Cost of Sales` fica menor e `Gross Margin` **maior** do que o real. Decida a
   regra (excluir esses itens? custo default?) e valide na paridade.

4. **Paridade obrigatória.** Rode cada medida por ano e compare com o Power BI **antes** de
   liberar pro Genie — especialmente as margens, que dependem do lookup de custo.

---

## 5. Resumo em uma frase

> `mv_comercial` = 11 dimensões (eixos de negócio) + ~13 medidas (regras de cálculo)
> declaradas sobre a `v_sales_txn`; o filtro `CASE WHEN txn_type` separa venda de devolução,
> as compostas repetem a fórmula porque metric view não referencia measure, e `NULLIF`
> blinda as divisões — o pacote que o Genie usa como "verdade" do comercial.
