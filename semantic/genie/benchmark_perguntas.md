# Benchmark de perguntas — Genie Spaces (Fase 5)

> Roteiro para testar e iterar os Spaces depois de cadastrar instruções + trusted
> queries. Faça cada pergunta no chat do Space, marque ✅/❌ e anote o que ajustar.
> Meta: acertar ≥ 90% antes de liberar a v1. O que errar vira novo Example query,
> Field, ou ajuste nas General Instructions.
>
> **Como avaliar cada resposta:** (a) escolheu a measure/fonte certa? (b) número bate
> com o esperado? (c) formatou moeda/percentual/quantidade corretamente? (d) usou a
> fonte certa quando havia ambiguidade (metric view vs time intelligence vs RFM)?

---

## Space COMERCIAL

### Básico — measures diretas
| # | Pergunta | Espera-se |
|---|---|---|
| 1 | Qual o total de vendas líquidas? | measure `Net Sales`, USD |
| 2 | Qual o faturamento bruto? | reconhece "faturamento" → `Gross Sales` |
| 3 | Quanto foi de descontos? | `Discounts` |
| 4 | Qual o CMV total? | reconhece "CMV" → `Cost of Sales` |
| 5 | Qual a margem bruta? | `Gross Margin` (valor, USD) |
| 6 | Qual a margem bruta percentual? | `Gross Margin %` (1 casa, %) |
| 7 | Quantas unidades foram vendidas? | `Quantity` (inteiro, sem $) |
| 8 | Quantos clientes ativos temos? | `Customers Current` (inteiro) |

### Por dimensão
| # | Pergunta | Espera-se |
|---|---|---|
| 9 | Vendas líquidas por região | groupby `Regiao`, ordenado |
| 10 | Top 10 produtos por venda | top N, `Net Sales` |
| 11 | Margem bruta % por categoria | `Gross Margin %` por `Categoria` |
| 12 | Vendas por tipo de negócio | `TipoNegocio` |
| 13 | Vendas líquidas por país | `Pais` |
| 14 | Qual a taxa de devolução por região? | `% Returns` por `Regiao` |
| 15 | Vendas líquidas na região Sul | filtro por 1 região (param `:regiao`) |

### Tempo / tendência (deve usar v_sales_time_intelligence)
| # | Pergunta | Espera-se |
|---|---|---|
| 16 | Como as vendas evoluíram mês a mês? | `v_sales_time_intelligence`, `mom_pct` |
| 17 | Qual o crescimento ano a ano (YoY)? | `yoy_pct` |
| 18 | Qual foi o YoY mais recente? | último `year_month` |
| 19 | Vendas líquidas por ano | dimensão `Ano` da metric view (série simples) |
| 20 | Qual mês teve maior venda? | ordenar por `gross_sales` |

### RFM (deve usar dim_customer_rfm)
| # | Pergunta | Espera-se |
|---|---|---|
| 21 | Quantos clientes em cada segmento RFM? | groupby `segment` |
| 22 | Liste os clientes At Risk | join RFM→transações, nome (param `:segmento`) |
| 23 | Quem são os clientes Champions? | mesmo padrão, segmento Champions |
| 24 | Quantos clientes estão "Lost"? | count por segmento |

### Armadilhas (checar desambiguação)
| # | Pergunta | Espera-se |
|---|---|---|
| 25 | Quanto vendemos? (sem qualificar) | assume `Net Sales` e avisa a suposição |
| 26 | Qual o crescimento das vendas? | usa time intelligence, NÃO a metric view |
| 27 | Preço médio por categoria | `Avg Unit Price` |

---

## Space FINANCEIRO

### Básico — realizado vs orçado
| # | Pergunta | Espera-se |
|---|---|---|
| 1 | Qual o total realizado? | `Total Amount Actual`, USD |
| 2 | Qual o orçado? | `Total Amount Budget` |
| 3 | Qual o desvio orçamentário? | `Budget Deviation` |
| 4 | Qual o desvio percentual? | `Budget Deviation %` (1 casa) |

### Por dimensão da DRE
| # | Pergunta | Espera-se |
|---|---|---|
| 5 | Realizado vs orçado por linha da DRE | groupby `LinhaDRE`, 2 valores + desvio |
| 6 | Quais contas tiveram maior desvio? | ranking por `Budget Deviation` |
| 7 | Realizado por organização | `Organizacao` |
| 8 | Realizado por grupo de departamento | `DepartmentGroup` |
| 9 | Qual foi a receita líquida? | LinhaDRE = Net Sales (header 3) |
| 10 | Qual o custo das vendas (DRE)? | LinhaDRE Cost of Sales (header 4) |

### Tempo
| # | Pergunta | Espera-se |
|---|---|---|
| 11 | Como evoluiu o realizado por mês? | groupby `Ano`,`Mes` |
| 12 | Realizado vs orçado em 2025 | filtro por ano (param `:ano`) |

### Análise Vertical (% VA — deve usar v_income_statement)
| # | Pergunta | Espera-se |
|---|---|---|
| 13 | Qual a análise vertical da DRE? | trusted query % VA, denom = header 3 |
| 14 | Cada linha representa quanto da receita líquida? | % VA por linha |
| 15 | % VA por conta | % VA no grão de conta |
| 16 | Quanto o custo representa da receita líquida? | % VA da linha Cost of Sales |

### Armadilhas
| # | Pergunta | Espera-se |
|---|---|---|
| 17 | Qual o resultado do período? (sem cenário) | assume `actual` e avisa |
| 18 | O orçado de 2025 bate com o Power BI? | explica divergência esperada ~0,17% (não é bug) |

---

## Registro de iteração

Para cada ❌, anote aqui: pergunta → o que o Genie fez de errado → correção aplicada
(novo Example query / Field / ajuste nas instructions) → reteste.

| Pergunta | Erro observado | Correção | Reteste |
|---|---|---|---|
| | | | |
