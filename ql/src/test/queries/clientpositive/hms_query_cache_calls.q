--! qt:dataset:
-- HIVE-30249 measurement workload: each statement targets one redundant compile-time HMS call.
-- Grep "HMS-RPC" in hive.log for the per-query RPC counts.
set hive.support.concurrency=true;
set hive.txn.manager=org.apache.hadoop.hive.ql.lockmgr.DbTxnManager;
set hive.optimize.metadata.query.cache.enabled=true;

create table hqc_dim (id int, name string, primary key (id) disable novalidate rely) stored as orc
  tblproperties ('transactional'='true');
create table hqc_fact (id int, dim_id int, amount int check (amount >= 0), note string default 'n/a')
  partitioned by (p string) stored as orc tblproperties ('transactional'='true');
alter table hqc_fact add constraint hqc_fk foreign key (dim_id) references hqc_dim(id) disable novalidate rely;
create table hqc_src (id int, dim_id int, amount int) stored as orc tblproperties ('transactional'='true');
create table hqc_ext (id int, v int) partitioned by (p string);

insert into hqc_dim values (1, 'a'), (2, 'b');
insert into hqc_src values (1, 1, 10), (2, 2, 20);
insert into hqc_fact partition (p='x') values (1, 1, 10, 'x');
insert into hqc_ext partition (p='x') values (1, 1);

create materialized view hqc_mv as select dim_id, sum(amount) s from hqc_fact group by dim_id;

-- Q1 constraints per Table copy: self-join + CTE referenced twice + subquery
explain cbo
with c as (select dim_id, amount from hqc_fact where p = 'x')
select d1.name, d2.name, sum(c1.amount)
from c c1 join c c2 on c1.dim_id = c2.dim_id
join hqc_dim d1 on d1.id = c1.dim_id join hqc_dim d2 on d2.id = c2.dim_id
where c1.dim_id in (select id from hqc_dim)
group by d1.name, d2.name;

-- Q2 MV registry: query eligible for rewriting
explain cbo select dim_id, sum(amount) from hqc_fact group by dim_id;

-- Q3 static partition target, IF NOT EXISTS (getPartitionWithAuthInfo)
explain insert overwrite table hqc_ext partition (p='x') if not exists select id, v from hqc_ext where p = 'x';

-- Q4 MERGE into a table with CHECK/DEFAULT constraints
explain merge into hqc_fact t using hqc_src s on t.id = s.id and t.p = 'x'
when matched and s.amount > 15 then update set amount = s.amount
when matched then delete
when not matched then insert values (s.id, s.dim_id, s.amount, default, 'x');

-- Q5 multi-insert into constrained table
explain from hqc_src
insert into hqc_fact partition (p='y') (id, dim_id, amount) select id, dim_id, amount
insert into hqc_fact partition (p='z') (id, dim_id, amount) select id, dim_id, amount;

-- Q6 CTE name that is not a table (negative getTable lookup)
explain with hqc_missing as (select id from hqc_dim) select * from hqc_missing m1 join hqc_missing m2 on m1.id = m2.id;

-- Q7 StatsOptimizer on partitioned tables
explain select count(*), min(id), max(id) from hqc_ext;
explain select count(*), min(amount), max(amount) from hqc_fact;
