#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [[ $# -ne 1 ]]; then
    printf 'Usage: bash %s <domain>\n' "$0" >&2
    exit 1
fi

domain=${1,,}
if [[ ${#domain} -gt 253 || $domain != *.* ]]; then
    printf 'Invalid DNS domain: %s\n' "$1" >&2
    exit 1
fi

# Restrict input to DNS labels, which are also safe in a sed replacement.
if [[ ! $domain =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
    printf 'Invalid DNS domain: %s\n' "$1" >&2
    exit 1
fi
IFS='.' read -r -a labels <<< "$domain"
for label in "${labels[@]}"; do
    if [[ ${#label} -gt 63 ]]; then
        printf 'DNS label is too long: %s\n' "$label" >&2
        exit 1
    fi
done

realm=${domain^^}
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Only process known text configuration formats; skip helper programs.
mapfile -d '' -t files < <(
    find "$project_dir/etc" \
        -path "$project_dir/etc/squid/helpers" -prune -o \
        -type f \( -name '*.conf' -o -name '*.pac' -o -name '*.yml' -o -name '*.yaml' \
        -o -name '*.ini' -o -name '*.txt' -o -name '*.regex' \) -print0
)
if [[ -f "$project_dir/compose.yml" && ! -L "$project_dir/compose.yml" ]]; then
    files+=("$project_dir/compose.yml")
fi

changed=0
for file in "${files[@]}"; do
    if grep -IqE 'example\.com|EXAMPLE\.COM' "$file"; then
        sed -i \
            -e "s/example\\.com/$domain/g" \
            -e "s/EXAMPLE\\.COM/$realm/g" \
            "$file"
        printf 'Updated: %s\n' "${file#"$project_dir/"}"
        changed=$((changed + 1))
    fi
done

printf 'Domain: %s; realm: %s; files updated: %d\n' "$domain" "$realm" "$changed"
