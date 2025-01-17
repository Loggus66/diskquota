-- table in 'diskquota not enabled database' should not be activetable
\! gpconfig -c diskquota.max_active_tables -v 2 > /dev/null
\! gpstop -arf > /dev/null

\c

CREATE DATABASE test_tablenum_limit_01;
CREATE DATABASE test_tablenum_limit_02;

\c test_tablenum_limit_01

CREATE TABLE a01(i int) DISTRIBUTED BY (i);
CREATE TABLE a02(i int) DISTRIBUTED BY (i);
CREATE TABLE a03(i int) DISTRIBUTED BY (i);

INSERT INTO a01 values(generate_series(0, 500));
INSERT INTO a02 values(generate_series(0, 500));
INSERT INTO a03 values(generate_series(0, 500));

\c test_tablenum_limit_02
CREATE EXTENSION diskquota;
CREATE SCHEMA s;
SELECT diskquota.set_schema_quota('s', '1 MB');

SELECT diskquota.wait_for_worker_new_epoch();

CREATE TABLE s.t1(i int) DISTRIBUTED BY (i); -- activetable = 1
INSERT INTO s.t1 SELECT generate_series(1, 100000); -- ok. diskquota soft limit does not check when first write

SELECT diskquota.wait_for_worker_new_epoch();

CREATE TABLE s.t2(i int) DISTRIBUTED BY (i); -- activetable = 2
INSERT INTO s.t2 SELECT generate_series(1, 10);  -- expect failed
CREATE TABLE s.t3(i int) DISTRIBUTED BY (i); -- activetable = 3 should not crash.
INSERT INTO s.t3 SELECT generate_series(1, 10);  -- expect failed

-- Q: why diskquota still works when activetable = 3?
-- A: the activetable limit by shmem size, calculate by hash_estimate_size()
--    the result will bigger than sizeof(DiskQuotaActiveTableEntry) * max_active_tables
--    the real capacity of this data structure based on the hash conflict probability.
--    so we can not predict when the data structure will be fill in fully.
--
--    this test case is useless, remove this if anyone dislike it.
--    but the hash capacity is smaller than 6, so the test case works for issue 51

DROP EXTENSION diskquota;

-- wait worker exit
\! sleep 1

\c contrib_regression
DROP DATABASE test_tablenum_limit_01;
DROP DATABASE test_tablenum_limit_02;

\! gpconfig -r diskquota.max_active_tables > /dev/null
\! gpstop -arf > /dev/null
