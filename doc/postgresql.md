# PostgreSQL for Squid Analytics

PostgreSQL используется как хранилище аналитики Squid.

```text
Squid
  ↓
access.log
  ↓
Vector
  ↓
PostgreSQL
  ↓
Grafana
```

## 1. Создание базы

Подключиться к PostgreSQL от имени администратора:

```bash
sudo -u postgres psql
```

Создать базу:

```sql
CREATE DATABASE squid;
```

Переключиться на неё:

```sql
\c squid
```

## 2. Пользователь для Vector

Создать отдельного пользователя, от имени которого Vector будет записывать события:

```sql
CREATE USER squid_vector
WITH PASSWORD '<VECTOR_DB_PASSWORD>';
```

Выдать доступ к базе и схеме:

```sql
GRANT CONNECT ON DATABASE squid TO squid_vector;
GRANT USAGE ON SCHEMA public TO squid_vector;
```

## 3. Таблица access log

```sql
CREATE TABLE squid_access_log (
    occurred_at     timestamptz NOT NULL,
    client_ip       inet,
    username        text,
    method          text,
    url             text,
    http_status     integer,
    squid_status    text,
    bytes_sent      bigint,
    duration_ms     bigint,
    hierarchy_type  text,
    upstream_ip     text,
    inserted_at     timestamptz NOT NULL
);
```

Важно:

- отдельного `id` нет — Vector вставляет строки напрямую;
- `inserted_at` передаётся из Vector через `now()`;
- `upstream_ip` имеет тип `text`, потому что Squid `%<A` может содержать не только IP, но и hostname.

Пример:

```text
ocsp.digicert.cn
packages.chocolatey.org
```

Поэтому тип `inet` для `upstream_ip` использовать нельзя.

Выдать Vector права на запись:

```sql
GRANT INSERT ON TABLE squid_access_log TO squid_vector;
```

Для диагностики можно также разрешить чтение:

```sql
GRANT SELECT ON TABLE squid_access_log TO squid_vector;
```

## 4. Пользователь для Grafana

Grafana должна работать через отдельного read-only пользователя:

```sql
CREATE USER squid_grafana
WITH PASSWORD '<GRAFANA_DB_PASSWORD>';
```

Права:

```sql
GRANT CONNECT ON DATABASE squid TO squid_grafana;
GRANT USAGE ON SCHEMA public TO squid_grafana;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO squid_grafana;
```

Чтобы Grafana автоматически получала `SELECT` на новые таблицы:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO squid_grafana;
```

## 5. Проверка записей

Последние события:

```sql
SELECT *
FROM squid_access_log
ORDER BY occurred_at DESC
LIMIT 20;
```

Количество записей:

```sql
SELECT COUNT(*)
FROM squid_access_log;
```

## 6. Трафик по пользователям

```sql
SELECT
    username,
    COUNT(*) AS requests,
    pg_size_pretty(SUM(bytes_sent)) AS downloaded,
    SUM(bytes_sent) AS downloaded_bytes
FROM squid_access_log
WHERE username IS NOT NULL
  AND username <> '-'
GROUP BY username
ORDER BY downloaded_bytes DESC;
```

Для одного пользователя:

```sql
SELECT
    username,
    COUNT(*) AS requests,
    pg_size_pretty(SUM(bytes_sent)) AS downloaded,
    SUM(bytes_sent) AS downloaded_bytes
FROM squid_access_log
WHERE username = 'ivanov'
GROUP BY username;
```

За текущий день:

```sql
SELECT
    username,
    COUNT(*) AS requests,
    pg_size_pretty(SUM(bytes_sent)) AS downloaded
FROM squid_access_log
WHERE occurred_at >= CURRENT_DATE
GROUP BY username
ORDER BY SUM(bytes_sent) DESC;
```

## 7. Grafana datasource

Тип datasource:

```text
PostgreSQL
```

Основные параметры:

```text
Host: <POSTGRES_HOST>:5432
Database: squid
User: squid_grafana
Password: <GRAFANA_DB_PASSWORD>
SSL mode: <disable/require>
TimescaleDB: off
```

## 8. Тестовый запрос для Grafana

```sql
SELECT
    $__timeGroupAlias(occurred_at, $__interval),
    SUM(bytes_sent) AS bytes
FROM squid_access_log
WHERE $__timeFilter(occurred_at)
GROUP BY 1
ORDER BY 1;
```

## 9. Текущая схема

```text
Database: squid

squid_access_log
├── occurred_at      timestamptz
├── client_ip        inet
├── username         text
├── method           text
├── url              text
├── http_status      integer
├── squid_status     text
├── bytes_sent       bigint
├── duration_ms      bigint
├── hierarchy_type   text
├── upstream_ip      text
└── inserted_at      timestamptz
```

## 10. Примечания

Формат Squid `access.log`, из которого Vector заполняет таблицу:

```conf
logformat analytics %ts.%03tu|%>a|%un|%rm|%ru|%>Hs|%Ss|%<st|%tr|%Sh/%<A
access_log daemon:/var/log/squid/access.log analytics
```

Поля соответствуют:

```text
1. occurred_at
2. client_ip
3. username
4. method
5. url
6. http_status
7. squid_status
8. bytes_sent
9. duration_ms
10. hierarchy_type / upstream_ip
```
