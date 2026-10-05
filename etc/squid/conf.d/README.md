# Squid configuration

Configuration files are loaded in alphabetical order.
Order matters, especially for `http_access` rules.

## Authentication

01_auth.conf
Authentication providers and user ACL definitions.

## Security policies

02_blacklist.conf
Domain blocking rules.

03_quota.conf
Disabled template for external user traffic quota checks.

## Service behavior

90_cache.conf
Forward proxy behavior and cache settings.

## Access policy

98_access.conf
Final allow/deny rules.
All `http_access` decisions are made here.

## Logging

99_log.conf
Analytics logging configuration.

## Validation

Before applying changes:

```bash
squid -k parse
```
