# 08 — Camada Semântica & Metric Views no Databricks

> **Contexto:** Fase 3 do projeto (BI Conversacional com Databricks Genie). Depois da
> medallion pronta (Silver + Gold), a camada semântica é onde o Genie ganha ou perde
> qualidade. Esta nota explica o *conceito* antes do código — é a primeira vez montando
> metric views, então o objetivo aqui é entender o "porquê".

---

## 1. O que é a "camada semântica" e por que ela existe

As tabelas **gold** (`fct_sales_details`, `dim_customer`, etc.) guardam **dados**, mas
não guardam **regras de negócio**. Por exemplo:

- **Venda líquida** = venda bruta − desconto rateado. Isso é uma *fórmula*, não uma
  coluna solta.
- **Margem bruta %** = (venda líquida − custo) / venda líquida.
- **"Faturamento"** e **"Gross Sales"** são a mesma coisa pro time comercial (sinônimos).

No **Power BI**, onde é que essas regras moram hoje? Nas **medidas DAX** do modelo
semântico (`Gross Sales`, `Net Sales`, `Gross Margin %`...). O relatório não recalcula
isso toda vez — ele chama a medida.

A camada semântica no Databricks cumpre **exatamente esse papel**: é o lugar onde as
medidas e dimensões viram objetos **oficiais e reutilizáveis**, pra que o **Genie**
responda "qual foi a margem bruta?" usando a *sua* fórmula certificada — e não uma que
ele inventou na hora.

> 🔑 **Regra de ouro:** sem essa camada, o Genie *chuta* os cálculos.
> Com ela, ele usa os *seus*.

---

## 2. O que é uma Metric View

Pensa nela como o **"modelo semântico do Power BI", mas escrito em YAML e versionado no
Git**. Ela declara duas coisas:

| Conceito na Metric View | O que é | Equivalente no Power BI |
|---|---|---|
| **dimensions** | Por onde você fatia (Ano, Cliente, Região, Categoria) | Colunas que viram eixos/filtros |
| **measures** | O que você soma/calcula (Gross Sales, Net Sales, Margem %) | **As medidas DAX** |

A diferença pra uma tabela normal: numa metric view você **nunca** escreve `SUM(...)` na
consulta — você pede a medida `Gross Sales` e ela **já sabe agregar**. Igual ao Power BI:
você arrasta a medida, não escreve o `SUM`.

---

## 3. Por que DOIS arquivos

```
semantic/10_v_sales_txn.sql    ← uma VIEW SQL normal (a "tabela plana")
semantic/11_mv_comercial.yaml  ← a METRIC VIEW (dimensões + medidas) em cima dela
```

- **`10_v_sales_txn.sql`** é uma *view* comum que **junta** o fato de vendas com as
  dimensões (`dim_customer`, `dim_product`, `dim_calendar`, `dim_region`) num único
  retângulo largo — cada linha = um item de pedido já com nome do cliente, categoria do
  produto, ano e região ao lado. É só o **JOIN pré-montado**, sem cálculo de negócio.

- **`11_mv_comercial.yaml`** é a metric view que aponta pra essa view e diz: "estas
  colunas são dimensões, estas fórmulas são medidas".

> **Dá pra fazer os joins dentro do próprio YAML** (a metric view suporta `joins`).
> Fazer a view SQL primeiro é uma **escolha de design**: deixa o join num lugar só,
> testável em SQL puro, e a metric view mais simples/limpa. As duas abordagens são
> válidas — a de **view separada costuma ser mais fácil de depurar na primeira vez**.

---

## 4. As duas formas de criar (UI vs DDL) — por que existem duas

Metric View é um recurso relativamente novo; dependendo da versão do workspace, o comando
`CREATE VIEW ... WITH METRICS` (DDL) pode ou não existir.

- **UI (caminho garantido):** Catalog Explorer → `4_semantic` → *Create* → *Metric View*
  → cola o YAML → nome `mv_comercial`.
- **DDL (se a versão suportar):** o mesmo YAML embrulhado num comando SQL — útil pra
  versionar/automatizar depois (Asset Bundle, Fase 10).

> Mesmo conteúdo, dois jeitos de aplicar. Comece pela **UI** pra garantir que funciona;
> migre pro DDL quando for automatizar o deploy.

---

## 5. Verificação de paridade (não pular!)

Depois de criar cada medida, **compare o número com o Power BI** antes de liberar pro
Genie. Ex.: rodar "Gross Sales por ano" na metric view e conferir se bate com o mesmo
gráfico no relatório atual. Medidas DAX complexas (RFM, subtotais de DRE) exigem tradução
cuidadosa — é o maior risco da Fase 3.

---

## 6. Glossário rápido

- **Metric View** — objeto do Unity Catalog que declara dimensões + medidas (a camada
  semântica moderna do Databricks).
- **Dimension** — atributo para fatiar/agrupar (ex.: Ano, Região).
- **Measure** — cálculo agregado (ex.: `SUM(order_quantity * unit_price)`).
- **`MEASURE()`** — função usada para compor medidas a partir de outras (ex.: Margem % a
  partir de Net Sales e Cost).
- **View plana / "wide table"** — o JOIN fato × dimensões pré-montado que alimenta a
  metric view.
- **Paridade** — conferência número-a-número entre a medida nova e a medida DAX original.

---

### Próximos passos (quando o conceito estiver claro)

1. `semantic/10_v_sales_txn.sql` — a view plana (explicada linha a linha).
2. `semantic/11_mv_comercial.yaml` — a metric view comercial (dimensões + medidas).
3. Aplicar via UI → testar paridade vs Power BI → iterar.
