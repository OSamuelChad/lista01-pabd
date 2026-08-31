-- =====================================================================
-- LISTA DE EXERCÍCIOS 1 — Sistema de E-commerce
-- Respostas (PostgreSQL)
--
-- Pré-requisito: rodar schema.sql antes deste arquivo.
--
-- ATENÇÃO À ORDEM: os exercícios 3, 4 e 5 alteram os dados (UPDATE/DELETE)
-- e, portanto, mudam o resultado dos exercícios 1, 2, 12 e 14 se você
-- reexecutá-los depois. Se quiser testar sem sujar a base, envolva o
-- bloco 3-5 em BEGIN; ... ROLLBACK; (ver marcações abaixo).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Liste os produtos com preço superior a R$ 1000.
-- ---------------------------------------------------------------------
SELECT id,
       name,
       price,
       stock
  FROM products
 WHERE price > 1000
 ORDER BY price DESC;


-- ---------------------------------------------------------------------
-- 2. Liste os produtos ordenados pelo preço, do maior para o menor.
-- ---------------------------------------------------------------------
SELECT id,
       name,
       price,
       stock
  FROM products
 ORDER BY price DESC;


-- =====================================================================
-- BLOCO DESTRUTIVO (exercícios 3, 4 e 5)
-- Descomente o BEGIN abaixo e o ROLLBACK ao final para testar sem
-- persistir as alterações.
-- =====================================================================
-- BEGIN;


-- ---------------------------------------------------------------------
-- 3. Aumente o preço de todos os produtos da `Dell` em 10%.
--
--    Não existe coluna de marca no schema, então o filtro é por nome.
--    ILIKE = LIKE case-insensitive (específico do PostgreSQL).
--    Atinge: 'Notebook Dell Inspiron' e 'Monitor 27" Dell'.
-- ---------------------------------------------------------------------
UPDATE products
   SET price = price * 1.10
 WHERE name ILIKE '%Dell%';

-- Conferência:
SELECT id, name, price FROM products WHERE name ILIKE '%Dell%';


-- ---------------------------------------------------------------------
-- 4. Exclua todos os produtos que sejam do tipo `Macbook`.
--
--    Só é possível porque o Macbook (id 9) não aparece em
--    orders_products. Se aparecesse, a FK product_id bloquearia o DELETE
--    (orders_products NÃO tem ON DELETE CASCADE em product_id).
-- ---------------------------------------------------------------------
DELETE FROM products
 WHERE name ILIKE '%Macbook%';


-- ---------------------------------------------------------------------
-- 5. Exclua UM produto que não possua pedidos associados.
--
--    ATENÇÃO: com os dados do seed, os produtos 1..8 aparecem todos em
--    orders_products. O ÚNICO produto órfão é o id 9 (Macbook) — que é
--    justamente o que o exercício 4 apaga. Ou seja: se você rodar o 4
--    antes do 5, este DELETE afeta 0 linhas (não dá erro, só não apaga
--    nada). Para ver o efeito, rode este exercício ANTES do 4, ou
--    insira um produto de teste:
--        INSERT INTO products (name, price, stock)
--             VALUES ('Produto sem pedidos', 10.00, 1);
--
--    O subselect escolhe o menor id órfão, tornando o DELETE
--    determinístico (o enunciado pede "um" produto, no singular).
-- ---------------------------------------------------------------------
DELETE FROM products
 WHERE id = (
       SELECT p.id
         FROM products p
        WHERE NOT EXISTS (
              SELECT 1
                FROM orders_products op
               WHERE op.product_id = p.id
        )
        ORDER BY p.id
        LIMIT 1
 );

-- Variante: excluir TODOS os produtos sem pedidos de uma vez.
-- DELETE FROM products p
--  WHERE NOT EXISTS (
--        SELECT 1 FROM orders_products op WHERE op.product_id = p.id
--  );


-- ROLLBACK;   -- descomente junto com o BEGIN acima
-- =====================================================================
-- FIM DO BLOCO DESTRUTIVO
-- =====================================================================


-- ---------------------------------------------------------------------
-- 6. Liste todos os pedidos realizados nos últimos 30 dias.
--
--    order_date é timestamptz, então comparar direto com o resultado de
--    now() - interval preserva a hora. Não usar BETWEEN com date solto.
-- ---------------------------------------------------------------------
SELECT id,
       user_id,
       order_date,
       status,
       total
  FROM orders
 WHERE order_date >= now() - interval '30 days'
 ORDER BY order_date DESC;


-- ---------------------------------------------------------------------
-- 7. Liste os pedidos e os respectivos nomes de usuário.
--
--    INNER JOIN basta: orders.user_id é NOT NULL e tem FK para users,
--    logo todo pedido tem dono.
-- ---------------------------------------------------------------------
SELECT o.id         AS pedido_id,
       u.name       AS usuario,
       o.order_date AS data_pedido,
       o.status,
       o.total
  FROM orders o
  JOIN users u ON u.id = o.user_id
 ORDER BY o.id;


-- ---------------------------------------------------------------------
-- 8. Liste todos os usuários e seus pedidos, inclusive usuários sem
--    pedidos.
--
--    LEFT JOIN: usuários sem pedido aparecem com as colunas de orders
--    em NULL (caso de 'Felipe Silva').
-- ---------------------------------------------------------------------
SELECT u.id         AS usuario_id,
       u.name       AS usuario,
       u.email,
       o.id         AS pedido_id,
       o.order_date AS data_pedido,
       o.status,
       o.total
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
 ORDER BY u.id, o.id;


-- ---------------------------------------------------------------------
-- 9. Liste todos os usuários (id, nome e email) que realizaram pelo
--    menos um pedido.
--
--    EXISTS é a forma mais direta: não gera duplicatas e para na
--    primeira linha encontrada (semi-join).
-- ---------------------------------------------------------------------
SELECT u.id,
       u.name,
       u.email
  FROM users u
 WHERE EXISTS (
       SELECT 1
         FROM orders o
        WHERE o.user_id = u.id
 )
 ORDER BY u.id;

-- Alternativa equivalente com JOIN + DISTINCT:
-- SELECT DISTINCT u.id, u.name, u.email
--   FROM users u
--   JOIN orders o ON o.user_id = u.id
--  ORDER BY u.id;


-- ---------------------------------------------------------------------
-- 10. Liste produtos que nunca foram vendidos.
--
--     Anti-join: LEFT JOIN + IS NULL. NOT EXISTS produz o mesmo plano
--     no PostgreSQL e é mais legível.
-- ---------------------------------------------------------------------
SELECT p.id,
       p.name,
       p.price,
       p.stock
  FROM products p
  LEFT JOIN orders_products op ON op.product_id = p.id
 WHERE op.id IS NULL
 ORDER BY p.id;

-- Alternativa com NOT EXISTS:
-- SELECT p.id, p.name, p.price, p.stock
--   FROM products p
--  WHERE NOT EXISTS (
--        SELECT 1 FROM orders_products op WHERE op.product_id = p.id
--  )
--  ORDER BY p.id;


-- ---------------------------------------------------------------------
-- 11. Liste usuários que nunca realizaram pedidos.
-- ---------------------------------------------------------------------
SELECT u.id,
       u.name,
       u.email
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
 WHERE o.id IS NULL
 ORDER BY u.id;

-- Alternativa com NOT EXISTS:
-- SELECT u.id, u.name, u.email
--   FROM users u
--  WHERE NOT EXISTS (
--        SELECT 1 FROM orders o WHERE o.user_id = u.id
--  )
--  ORDER BY u.id;


-- ---------------------------------------------------------------------
-- 12. Liste os produtos com preço acima da média, em ordem decrescente.
--
--     Subquery escalar: AVG(price) é calculado uma única vez sobre a
--     tabela inteira e comparado linha a linha.
-- ---------------------------------------------------------------------
SELECT id,
       name,
       price
  FROM products
 WHERE price > (SELECT AVG(price) FROM products)
 ORDER BY price DESC;

-- Para ver a média junto de cada linha (window function):
-- SELECT id, name, price, ROUND(AVG(price) OVER (), 2) AS media
--   FROM products
--  ORDER BY price DESC;


-- ---------------------------------------------------------------------
-- 13. Liste a quantidade de pedidos realizados por cada usuário.
--
--     COUNT(o.id) e não COUNT(*): com LEFT JOIN, COUNT(*) contaria a
--     linha "fantasma" do usuário sem pedidos e devolveria 1 em vez de 0.
-- ---------------------------------------------------------------------
SELECT u.id           AS usuario_id,
       u.name         AS usuario,
       COUNT(o.id)    AS qtd_pedidos
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
 GROUP BY u.id, u.name
 ORDER BY qtd_pedidos DESC, u.name;


-- ---------------------------------------------------------------------
-- 14. Listar os três produtos mais vendidos.
--
--     "Mais vendido" = maior soma de quantidade. Como no seed toda
--     quantity é 1, o desempate por receita mantém o resultado estável.
-- ---------------------------------------------------------------------
SELECT p.id,
       p.name,
       SUM(op.quantity)                    AS unidades_vendidas,
       SUM(op.quantity * op.unit_price)    AS receita_total
  FROM orders_products op
  JOIN products p ON p.id = op.product_id
 GROUP BY p.id, p.name
 ORDER BY unidades_vendidas DESC, receita_total DESC
 LIMIT 3;


-- ---------------------------------------------------------------------
-- 15. Relatório: usuários, quantidade de pedidos e valor total comprado.
--
--     Agregar SOMENTE sobre orders. Se você juntar orders_products aqui,
--     SUM(o.total) é multiplicado pelo número de itens do pedido e o
--     relatório fica inflado — erro clássico de fan-out em JOIN.
--
--     Pedidos cancelados entram na contagem. Para excluí-los, use o
--     FILTER comentado abaixo.
-- ---------------------------------------------------------------------
SELECT u.id                             AS usuario_id,
       u.name                           AS usuario,
       u.email,
       COUNT(o.id)                      AS qtd_pedidos,
       COALESCE(SUM(o.total), 0)        AS valor_total_comprado
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
 GROUP BY u.id, u.name, u.email
 ORDER BY valor_total_comprado DESC, u.name;

-- Variante desconsiderando pedidos cancelados:
-- SELECT u.id AS usuario_id,
--        u.name AS usuario,
--        u.email,
--        COUNT(o.id) FILTER (WHERE o.status <> 'canceled')            AS qtd_pedidos,
--        COALESCE(SUM(o.total) FILTER (WHERE o.status <> 'canceled'), 0) AS valor_total_comprado
--   FROM users u
--   LEFT JOIN orders o ON o.user_id = u.id
--  GROUP BY u.id, u.name, u.email
--  ORDER BY valor_total_comprado DESC, u.name;
