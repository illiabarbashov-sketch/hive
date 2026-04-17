set hive.explain.user=false;
set hive.auto.convert.join=false;
set hive.merge.join.skew.threshold=2;
set hive.merge.join.skew.abort=false;
set hive.merge.join.skew.check.interval=1;

-- SORT_QUERY_RESULTS

CREATE TABLE merge_skew_warn_a (key int, value string);
CREATE TABLE merge_skew_warn_b (key int, value string);

INSERT INTO TABLE merge_skew_warn_a VALUES (1, 'a1'), (1, 'a2'), (1, 'a3'), (1, 'a4'),
(2, 'b1'), (3, 'c1');
INSERT INTO TABLE merge_skew_warn_b VALUES (1, 'x1'), (2, 'y1'), (3, 'z1');

EXPLAIN
SELECT a.key, a.value, b.value
FROM merge_skew_warn_a a JOIN merge_skew_warn_b b ON a.key = b.key;

SELECT a.key, a.value, b.value
FROM merge_skew_warn_a a JOIN merge_skew_warn_b b ON a.key = b.key;

SELECT count(*) FROM merge_skew_warn_a a JOIN merge_skew_warn_b b ON a.key = b.key;

-- no warning run
set hive.merge.join.skew.threshold=-1;

SELECT count(*) FROM merge_skew_warn_a a JOIN merge_skew_warn_b b ON a.key = b.key;

-- interval test: threshold=2, interval=3 -- skew key (key=1 has 4 rows) must still be detected
-- even though it may not be evaluated on every row
set hive.merge.join.skew.threshold=2;
set hive.merge.join.skew.check.interval=3;

SELECT count(*) FROM merge_skew_warn_a a JOIN merge_skew_warn_b b ON a.key = b.key;

-- unique-mapping test: 1-to-1 join between tables with unique keys should never trip threshold
-- even with a low threshold of 2. Each key appears only once, so no skew.
set hive.merge.join.skew.abort=true;

CREATE TABLE merge_skew_warn_unique_a (key int, value string);
CREATE TABLE merge_skew_warn_unique_b (key int, value string);

INSERT INTO TABLE merge_skew_warn_unique_a VALUES (1, 'u1'), (2, 'u2'), (3, 'u3');
INSERT INTO TABLE merge_skew_warn_unique_b VALUES (1, 'v1'), (2, 'v2'), (3, 'v3');

set hive.merge.join.skew.threshold=2;
set hive.merge.join.skew.check.interval=1;

-- must complete without abort: every key appears exactly once on both sides
SELECT count(*) FROM merge_skew_warn_unique_a a JOIN merge_skew_warn_unique_b b ON a.key = b.key;

DROP TABLE merge_skew_warn_unique_a;
DROP TABLE merge_skew_warn_unique_b;

DROP TABLE merge_skew_warn_a;
DROP TABLE merge_skew_warn_b;

