# Lista de Exercícios 1 — Sistema de E-commerce

Respostas comentadas em PostgreSQL. O arquivo executável está em `respostas.sql`; o schema e a
carga de dados, em `schema.sql`.

## Como rodar

```bash
# Postgres local
psql -U postgres -d meubanco -f schema.sql
psql -U postgres -d meubanco -f respostas.sql

# ou, sem instalar nada, via Docker
docker run --rm -d --name lista1 -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:17
psql -h localhost -U postgres -f schema.sql
psql -h localhost -U postgres -f respostas.sql
docker rm -f lista1
```

## Aviso sobre a ordem de execução

Os exercícios **3, 4 e 5 modificam os dados**. Se você rodar a lista inteira de cima para baixo e
depois reexecutar os exercícios 1, 2, 12 ou 14, os resultados serão diferentes dos "esperados"
listados aqui. Cada exercício abaixo marca com **(base original)** ou **(após 3 e 4)** qual cenário
está sendo descrito.

Para testar sem sujar a base, envolva o bloco 3–5 em `BEGIN; ... ROLLBACK;` (já marcado no `.sql`).

---

## 1. Produtos com preço superior a R$ 1000

```sql
SELECT id, name, price, stock
  FROM products
 WHERE price > 1000
 ORDER BY price DESC;
```

Filtro simples com `WHERE`. O `ORDER BY` não é exigido pelo enunciado, mas torna a saída legível.

**Esperado (base original):** 4 linhas — Macbook Pro M5 (19999,00), Notebook Dell Inspiron
(4500,00), Monitor 27" Dell (1899,00), Cadeira Ergonômica (1299,00).

---

## 2. Produtos ordenados pelo preço, do maior para o menor

```sql
SELECT id, name, price, stock
  FROM products
 ORDER BY price DESC;
```

`ORDER BY ... DESC`. Sem `WHERE`, retorna a tabela inteira.

**Esperado (base original):** 9 linhas, na ordem 9 → 1 → 4 → 7 → 6 → 8 → 3 → 5 → 2.

---

## 3. Aumentar em 10% o preço dos produtos `Dell`

```sql
UPDATE products
   SET price = price * 1.10
 WHERE name ILIKE '%Dell%';
```

Pontos de atenção:

- **Não existe coluna de marca** no schema. O casamento é feito pelo texto de `name`, o que é
  frágil: um produto chamado "Suporte para notebook Dell/HP" também seria pego. Num modelo bem
  normalizado haveria uma tabela `brands` e `products.brand_id`.
- `ILIKE` é o `LIKE` case-insensitive do PostgreSQL. Com `LIKE '%Dell%'` puro, um registro escrito
  "DELL" escaparia do filtro.
- `SET price = price * 1.10` referencia o valor **antigo** da própria linha — é a forma correta de
  fazer um reajuste percentual, sem precisar ler o valor antes.
- **Nunca esqueça o `WHERE`** num `UPDATE`: sem ele, todos os 9 produtos seriam reajustados.
- `price` é `numeric(10,2)`, então o resultado é arredondado para 2 casas automaticamente.

**Esperado:** 2 linhas afetadas — id 1 vai de 4500,00 para **4950,00**; id 4 vai de 1899,00 para
**2088,90**.

---

## 4. Excluir todos os produtos do tipo `Macbook`

```sql
DELETE FROM products
 WHERE name ILIKE '%Macbook%';
```

Este `DELETE` **só funciona porque o Macbook nunca foi vendido**. A FK
`orders_products.product_id → products.id` não tem `ON DELETE CASCADE`, então apagar um produto que
apareça em algum item de pedido levantaria:

```
ERROR:  update or delete on table "products" violates foreign key constraint
        "orders_products_product_id_fkey" on table "orders_products"
```

Isso é o comportamento **desejado**: apagar o produto apagaria silenciosamente o histórico de
vendas. Em sistemas reais, o padrão é *soft delete* — uma coluna `active boolean` ou `deleted_at`
— em vez de remover a linha.

Compare com `orders_products.order_id`, que **tem** `ON DELETE CASCADE`: apagar um pedido apaga
seus itens junto, porque um item não faz sentido sem o pedido dono.

**Esperado:** 1 linha afetada (id 9).

---

## 5. Excluir um produto que não possua pedidos associados

```sql
DELETE FROM products
 WHERE id = (
       SELECT p.id
         FROM products p
        WHERE NOT EXISTS (
              SELECT 1 FROM orders_products op WHERE op.product_id = p.id
        )
        ORDER BY p.id
        LIMIT 1
 );
```

O enunciado pede **um** produto (singular), então o subselect com `ORDER BY ... LIMIT 1` escolhe um
alvo determinístico — sempre o menor id órfão. Sem o `ORDER BY`, o `LIMIT 1` pegaria uma linha
arbitrária, e o resultado poderia variar entre execuções.

`NOT EXISTS` é a construção idiomática para "não tem nenhum filho". Ela é preferível a
`NOT IN (SELECT product_id FROM orders_products)` porque `NOT IN` tem uma armadilha: se a subquery
retornar **um único `NULL`**, o resultado inteiro vira vazio (lógica ternária do SQL).

> **Pegadinha desta lista:** nos dados do seed, os produtos 1 a 8 aparecem todos em
> `orders_products`. O **único** produto órfão é o id 9 — o Macbook, que o exercício 4 acabou de
> apagar. Se você rodar 4 antes de 5, este `DELETE` afeta **0 linhas** (não dá erro, só não apaga
> nada). Para ver o efeito, rode o 5 antes do 4, ou insira um alvo:
> ```sql
> INSERT INTO products (name, price, stock) VALUES ('Produto sem pedidos', 10.00, 1);
> ```

Variante que apaga todos os órfãos de uma vez:

```sql
DELETE FROM products p
 WHERE NOT EXISTS (
       SELECT 1 FROM orders_products op WHERE op.product_id = p.id
 );
```

---

## 6. Pedidos realizados nos últimos 30 dias

```sql
SELECT id, user_id, order_date, status, total
  FROM orders
 WHERE order_date >= now() - interval '30 days'
 ORDER BY order_date DESC;
```

- `order_date` é `timestamptz`, e `now()` também. Comparar os dois diretamente preserva a hora e
  respeita o fuso da sessão.
- Evite `BETWEEN '2026-08-01' AND '2026-08-31'` com datas soltas: `'2026-08-31'` vira
  `2026-08-31 00:00:00`, e todos os pedidos feitos ao longo do dia 31 ficariam de fora.
- Se a tabela fosse grande, `order_date >= constante` é **sargable** — consegue usar um índice em
  `order_date`. Já `WHERE now() - order_date <= interval '30 days'` (função aplicada na coluna)
  força varredura completa. Prefira sempre deixar a coluna sozinha de um lado do operador.

**Esperado:** 6 linhas — pedidos 1, 2, 3, 4, 5 e 6 (2, 5, 10, 15, 20 e 25 dias atrás). Os pedidos
7 a 10 (40 a 90 dias) ficam de fora.

---

## 7. Pedidos e os respectivos nomes de usuário

```sql
SELECT o.id AS pedido_id, u.name AS usuario, o.order_date, o.status, o.total
  FROM orders o
  JOIN users u ON u.id = o.user_id
 ORDER BY o.id;
```

`INNER JOIN` (o `JOIN` sozinho já é INNER) é suficiente aqui: `orders.user_id` é `NOT NULL` **e**
tem FK para `users`, então todo pedido obrigatoriamente tem um dono existente. Um `LEFT JOIN` neste
caso não mudaria nada além de sugerir uma incerteza que o schema já resolveu.

**Esperado:** 10 linhas, uma por pedido.

---

## 8. Todos os usuários e seus pedidos, inclusive usuários sem pedidos

```sql
SELECT u.id AS usuario_id, u.name AS usuario, u.email,
       o.id AS pedido_id, o.order_date, o.status, o.total
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
 ORDER BY u.id, o.id;
```

É o exercício clássico de `LEFT JOIN`: **a tabela da esquerda é preservada por inteiro**. Usuários
sem pedido aparecem uma vez, com todas as colunas de `orders` preenchidas com `NULL`.

Cuidado com o lugar do filtro: se você acrescentasse `WHERE o.status = 'delivered'`, o `LEFT JOIN`
seria degradado para um `INNER JOIN` na prática, porque `NULL = 'delivered'` é falso e as linhas
sem pedido sumiriam. Filtros sobre a tabela da direita vão dentro do `ON`:

```sql
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'delivered'
```

**Esperado:** 11 linhas — as 10 combinações usuário/pedido, mais Felipe Silva com pedido `NULL`.

---

## 9. Usuários (id, nome, email) que realizaram pelo menos um pedido

```sql
SELECT u.id, u.name, u.email
  FROM users u
 WHERE EXISTS (
       SELECT 1 FROM orders o WHERE o.user_id = u.id
 )
 ORDER BY u.id;
```

`EXISTS` expressa exatamente "pelo menos um" — é um **semi-join**: o planejador para na primeira
linha correspondente e nunca duplica o usuário.

A alternativa com `JOIN` precisa de `DISTINCT`, senão Ana apareceria duas vezes (ela tem 2 pedidos):

```sql
SELECT DISTINCT u.id, u.name, u.email
  FROM users u
  JOIN orders o ON o.user_id = u.id
 ORDER BY u.id;
```

Sempre que você escreve `DISTINCT` para consertar um `JOIN`, vale perguntar se `EXISTS` não seria
mais honesto — o `DISTINCT` custa uma ordenação ou hash sobre o resultado inteiro.

**Esperado:** 5 linhas — Ana, Bruno, Carla, Diego, Elisa. Felipe fica de fora.

---

## 10. Produtos que nunca foram vendidos

```sql
SELECT p.id, p.name, p.price, p.stock
  FROM products p
  LEFT JOIN orders_products op ON op.product_id = p.id
 WHERE op.id IS NULL
 ORDER BY p.id;
```

Padrão **anti-join**: `LEFT JOIN` + `WHERE <coluna da direita> IS NULL`. Faça o teste `IS NULL`
sempre sobre uma coluna `NOT NULL` da tabela da direita (aqui `op.id`, que é PK) — se você testasse
uma coluna que aceita nulos, não daria para distinguir "não casou" de "casou com valor nulo".

Equivalente com `NOT EXISTS` (mesmo plano no PostgreSQL, mais legível):

```sql
SELECT p.id, p.name, p.price, p.stock
  FROM products p
 WHERE NOT EXISTS (
       SELECT 1 FROM orders_products op WHERE op.product_id = p.id
 )
 ORDER BY p.id;
```

**Esperado (base original):** 1 linha — Notebook Apple Macbook Pro M5. **Após o exercício 4:**
nenhuma linha.

---

## 11. Usuários que nunca realizaram pedidos

```sql
SELECT u.id, u.name, u.email
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
 WHERE o.id IS NULL
 ORDER BY u.id;
```

Mesmo anti-join do exercício 10, aplicado a `users`/`orders`. É o complemento exato do exercício 9:
9 e 11 juntos devolvem os 6 usuários, sem sobreposição.

**Esperado:** 1 linha — Felipe Silva.

---

## 12. Produtos com preço acima da média, em ordem decrescente

```sql
SELECT id, name, price
  FROM products
 WHERE price > (SELECT AVG(price) FROM products)
 ORDER BY price DESC;
```

O `(SELECT AVG(price) FROM products)` é uma **subquery escalar não correlacionada**: não referencia
a query externa, então é executada **uma única vez** e o resultado é comparado linha a linha.

Não dá para escrever `WHERE price > AVG(price)` — funções de agregação não são permitidas no
`WHERE`, que é avaliado antes da agregação. O `WHERE` filtra linhas individuais; o `HAVING` filtra
grupos já agregados.

Para exibir a média ao lado de cada produto, use uma window function:

```sql
SELECT id, name, price, ROUND(AVG(price) OVER (), 2) AS media
  FROM products
 ORDER BY price DESC;
```

**Esperado (base original):** média ≈ **3261,63**; 2 linhas acima dela — Macbook (19999,00) e
Notebook Dell (4500,00).

**Esperado (após 3 e 4):** o Macbook, que era o outlier puxando a média para cima, sumiu. A nova
média cai para **1249,45** e passam a aparecer 3 linhas — Notebook Dell (4950,00), Monitor Dell
(2088,90) e Cadeira Ergonômica (1299,00). Um bom lembrete de como a média é sensível a valores
extremos.

---

## 13. Quantidade de pedidos por usuário

```sql
SELECT u.id AS usuario_id, u.name AS usuario, COUNT(o.id) AS qtd_pedidos
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
 GROUP BY u.id, u.name
 ORDER BY qtd_pedidos DESC, u.name;
```

Duas decisões importantes:

1. **`LEFT JOIN`, não `INNER`** — para que Felipe apareça no relatório com zero.
2. **`COUNT(o.id)`, não `COUNT(*)`** — `COUNT(*)` conta *linhas*, inclusive a linha fantasma que o
   `LEFT JOIN` cria para Felipe, e devolveria **1** em vez de 0. `COUNT(coluna)` ignora `NULL`s.
   Este é o erro mais comum em relatórios com `LEFT JOIN`.

Sobre o `GROUP BY u.id, u.name`: como `u.id` é chave primária, o PostgreSQL aceitaria apenas
`GROUP BY u.id` (dependência funcional). Listar as duas colunas é mais portável entre SGBDs.

**Esperado:** Ana, Bruno, Carla, Diego e Elisa com 2 pedidos cada; Felipe Silva com 0.

---

## 14. Os três produtos mais vendidos

```sql
SELECT p.id,
       p.name,
       SUM(op.quantity)                 AS unidades_vendidas,
       SUM(op.quantity * op.unit_price) AS receita_total
  FROM orders_products op
  JOIN products p ON p.id = op.product_id
 GROUP BY p.id, p.name
 ORDER BY unidades_vendidas DESC, receita_total DESC
 LIMIT 3;
```

- **"Mais vendido" = `SUM(op.quantity)`**, não `COUNT(*)`. `COUNT(*)` contaria em quantos pedidos
  distintos o produto apareceu, tratando "1 pedido de 50 unidades" como menos vendido que "2
  pedidos de 1 unidade". Neste seed todas as quantidades são 1, então os dois dariam o mesmo
  resultado — mas a query estaria errada por acaso, não por acerto.
- O `INNER JOIN` com `products` é o correto: produtos sem venda nenhuma não devem competir por uma
  vaga no top 3.
- O desempate por `receita_total` importa: três produtos empatam em 2 unidades, e sem o segundo
  critério a escolha do terceiro colocado seria arbitrária (o SQL não garante ordem em empates).
- Repare que a receita usa `op.unit_price`, o **preço histórico congelado no momento da venda**, e
  não `p.price`. Por isso o reajuste do exercício 3 não altera este relatório — que é exatamente o
  motivo de `orders_products` ter uma coluna `unit_price` própria.

**Esperado:**

| # | Produto | Unidades | Receita |
|---|---------|----------|---------|
| 1 | Teclado Mecânico Logitech | 3 | 1049,70 |
| 2 | Notebook Dell Inspiron | 2 | 9000,00 |
| 3 | Webcam HD Logitech | 2 | 518,00 |

O Mouse Logitech MX também vendeu 2 unidades, mas perde o desempate por receita (179,80).

---

## 15. Relatório: usuários, quantidade de pedidos e valor total comprado

```sql
SELECT u.id AS usuario_id,
       u.name AS usuario,
       u.email,
       COUNT(o.id)               AS qtd_pedidos,
       COALESCE(SUM(o.total), 0) AS valor_total_comprado
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
 GROUP BY u.id, u.name, u.email
 ORDER BY valor_total_comprado DESC, u.name;
```

**O erro clássico deste exercício é juntar `orders_products` aqui.** Se você escrever

```sql
-- ERRADO
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
LEFT JOIN orders_products op ON op.order_id = o.id
```

cada pedido é replicado por item, e `SUM(o.total)` soma o mesmo total várias vezes. O pedido 3 da
Carla tem 3 itens, então o total dela apareceria **triplicado**. Isso se chama *fan-out*: um `JOIN`
1:N multiplica linhas antes da agregação. Regra prática — **agregue apenas sobre a granularidade
que você está somando**. Como `orders.total` já é um valor por pedido, `orders` basta.

Se precisar de métricas de dois níveis (nº de pedidos **e** nº de itens), agregue cada uma em sua
própria subquery/CTE e junte os resultados, em vez de empilhar `JOIN`s.

Outros detalhes:

- `COALESCE(SUM(...), 0)` — `SUM` de um conjunto vazio devolve `NULL`, não zero. Sem o `COALESCE`,
  Felipe apareceria com `NULL` no lugar de `0,00`.
- Pedidos **cancelados entram na soma** nesta versão. Se o relatório for de faturamento real, filtre
  com `FILTER`, que aplica a condição por agregado sem precisar de subquery:

```sql
SELECT u.id, u.name, u.email,
       COUNT(o.id) FILTER (WHERE o.status <> 'canceled')               AS qtd_pedidos,
       COALESCE(SUM(o.total) FILTER (WHERE o.status <> 'canceled'), 0) AS valor_total
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
 GROUP BY u.id, u.name, u.email
 ORDER BY valor_total DESC, u.name;
```

**Esperado (versão principal):**

| Usuário | Pedidos | Total comprado |
|---------|---------|----------------|
| Ana Souza | 2 | 5888,90 |
| Elisa Prado | 2 | 4759,00 |
| Bruno Lima | 2 | 2248,90 |
| Carla Alves | 2 | 1118,80 |
| Diego Santos | 2 | 808,90 |
| Felipe Silva | 0 | 0,00 |

Na variante com `FILTER`, Carla cai para 1 pedido e 618,90 — o pedido 8, de 499,90, está cancelado.

---

## Resumo das construções

| # | Construção principal |
|---|---|
| 1 | `WHERE` com comparação numérica |
| 2 | `ORDER BY ... DESC` |
| 3 | `UPDATE ... SET col = col * fator` + `ILIKE` |
| 4 | `DELETE` com restrição de FK |
| 5 | `DELETE` com subquery escalar + `NOT EXISTS` |
| 6 | Aritmética de `timestamptz` com `interval` |
| 7 | `INNER JOIN` |
| 8 | `LEFT JOIN` (preserva a tabela da esquerda) |
| 9 | Semi-join com `EXISTS` |
| 10 | Anti-join (`LEFT JOIN` + `IS NULL`) |
| 11 | Anti-join (complemento do nº 9) |
| 12 | Subquery escalar não correlacionada com `AVG` |
| 13 | `GROUP BY` + `COUNT(coluna)` sobre `LEFT JOIN` |
| 14 | `GROUP BY` + `SUM` + `ORDER BY ... LIMIT` |
| 15 | Relatório agregado evitando fan-out de `JOIN` |
