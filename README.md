# Proxy stack

Docker Compose: Nginx, Squid, Vector, PostgreSQL и Grafana.
Nginx раздаёт PAC и проксирует веб-интерфейс Grafana.

## Структура

| Каталог | Назначение |
| --- | --- |
| `etc/<сервис>/` | Дополнительные конфигурации, монтируются read-only |
| `var/log/<сервис>/` | Файловые логи Squid и Vector |
| `data/<сервис>/` | Постоянные данные и рабочие файлы |

Сервисы: `nginx`, `squid`, `vector`, `postgresql`, `grafana`.
Vector дополнительно читает `var/log/squid` в режиме read-only.
В `data/postgresql` хранится БД; в `data/vector` — checkpoints и дисковый
буфер; в `data/squid` — рабочие файлы Squid; в `data/grafana` — внутренняя
БД и состояние Grafana. Nginx и PostgreSQL используют штатные конфигурации
своих образов. Кэширование HTTP-объектов Squid отключено.

## Подстановка домена

В конфигурациях используется шаблонный домен `example.com` и Kerberos realm
`EXAMPLE.COM`. Перед запуском замените их на свой домен:

```sh
bash scripts/set-domain.sh corp.company.ru
```

Скрипт принимает ровно один аргумент — DNS-домен без протокола, порта и пути.
Работает из любого рабочего каталога (пути определяются относительно скрипта).
Заменяет `example.com` и `EXAMPLE.COM` в текстовых конфигурациях сервисов
под `etc/` и в `compose.yml`. DNS-имена записываются в нижнем регистре,
realm — в верхнем; например, `proxy.corp.company.ru` и `CORP.COMPANY.RU`.
Предполагается, что Kerberos realm соответствует DNS-домену.

Helpers, keytab, данные, логи и документация не изменяются.

Скрипт заменяет только шаблон: повторный запуск с другим доменом не меняет
уже подставленный домен. Для другого окружения используйте исходные конфиги.
Keytab для нового principal нужно получить отдельно; контейнеры скрипт
не перезапускает.

## Подготовка

1. Скопировать `.env.example` в `.env` и задать разные пароли:
   - `POSTGRES_PASSWORD` — администратор PostgreSQL;
   - `SQUID_VECTOR_PASSWORD` — запись событий Vector;
   - `SQUID_GRAFANA_PASSWORD` — read-only доступ Grafana к аналитике;
   - `GRAFANA_ADMIN_PASSWORD` — администратор веб-интерфейса Grafana.
   Опционально задаются `GRAFANA_ADMIN_USER`, `GRAFANA_UID` и `GRAFANA_GID`.
   UID/GID должны иметь право записи в `data/grafana` (по умолчанию `1000:1000`).
   Для паролей PostgreSQL использовать случайные URL-safe значения, например
   hex. Не коммитить `.env`.
2. Подготовить `etc/squid/HTTP.keytab` для principal
   `HTTP/proxy.example.com@EXAMPLE.COM`. Проверьте наличие
   `/usr/lib/squid/negotiate_kerberos_auth` в выбранном образе Squid.
   Keytab должен читаться пользователем `proxy` внутри контейнера,
   но не быть общедоступным.
3. Обеспечить контейнеру Squid разрешение DNS домена AD, доступ к KDC
   и корректное время хоста. Клиенты должны разрешать `proxy.example.com`
   в адрес Docker-хоста.
4. Проверить образы и зафиксировать их версии/digests в `.env`.
   Для Squid и Vector пока используются изменяемые теги `latest`;
   совместимость конфигураций с выбранными образами требует проверки.

Это стартовый каркас: без keytab полноценная Kerberos-аутентификация Squid
не готова. Заготовки для отдельного `krb5.conf` и quota helper сохранены,
но закомментированы и сейчас не используются.

## Проверка и запуск

Требуются Docker Engine и Docker Compose v2.

```sh
docker compose config --quiet
docker compose pull
docker compose run --rm --no-deps nginx nginx -t
docker compose run --rm --no-deps --entrypoint /usr/sbin/squid squid -k parse -f /etc/squid/squid.conf
docker compose run --rm --no-deps --entrypoint vector vector validate --no-environment /etc/vector/vector_postgresql.yml
docker compose up -d
docker compose ps
```

Первый запуск PostgreSQL на пустом `data/postgresql` создаёт базу `squid`,
таблицу `squid_access_log`, роль `squid_vector` с правом INSERT и роль
`squid_grafana` с правом SELECT. Vector и Grafana подключаются к
`postgresql:5432` по внутренней сети Compose. Порт БД наружу не публикуется.
Datasource `Squid PostgreSQL` создаётся автоматически из
`etc/grafana/provisioning/datasources/postgresql.yml`. Dashboard
`Squid Analytics` загружается из `etc/grafana/dashboards/squid-analytics.json`
в папку Grafana `Squid`. Он содержит общие показатели, Top Users, Top Sites,
график трафика и детализацию сайтов по выбранному пользователю.

Init SQL выполняется только при создании новой БД. Если PostgreSQL уже была
инициализирована до добавления Grafana, роль `squid_grafana` и её права нужно
однократно создать вручную по разделу Grafana в `doc/postgresql.md`. Изменение
пароля в `.env` не меняет пароль роли в существующей БД: его нужно обновить
отдельно через SQL. Не удаляйте `data/postgresql` для применения изменений —
это уничтожит данные.

Внешние порты: `80` (PAC) и `3128` (прокси), по умолчанию на всех интерфейсах.
Ограничьте доступ доверенной сетью на Docker-хосте или задайте адрес привязки
в `ports`. Squid разрешает целевые порты 80 и 443; CONNECT — только 443.
PAC доступен по адресу `http://proxy.example.com/proxy.pac`, Grafana —
`http://grafana.example.com`. Оба имени должны указывать на Docker-хост.
Порт Grafana `3000` наружу не публикуется. PAC сохраняет fallback `DIRECT`.

## Логи и права

- Nginx: stdout/stderr, доступны через `docker compose logs nginx`.
- Squid: `var/log/squid/access.log`, `cache.log`.
- Vector: `var/log/vector/vector.log` (stdout/stderr перенаправлены в файл).
- PostgreSQL: stderr, доступен через `docker compose logs postgresql`.
- Grafana: stdout/stderr, доступны через `docker compose logs grafana`.

Ранние ошибки запуска также могут оставаться в `docker compose logs`.
Каталоги bind mounts создаются Docker при отсутствии. Squid при старте
назначает владельца каталогов логов и рабочих файлов. Владельцы файлов на
хосте будут соответствовать UID/GID контейнеров.
Vector в этом каркасе работает от root, чтобы читать логи Squid;
переход на непривилегированного пользователя требует согласования UID/GID.

Ротация файловых логов Squid и Vector пока не настроена. Для stdout/stderr
Nginx, PostgreSQL и Grafana следует настроить ротацию Docker logging driver. Для файлов
нужна отдельная политика хранения; host logrotate автоматически в контейнеры
не переносится.
Обновление образов не должно сопровождаться автоматическим переходом на
новый major PostgreSQL: для этого нужна миграция данных.
