#!/bin/bash

set -euo pipefail

function log {
    echo -e "\e[2m$1\e[22m" >&2
}

function anomaly_detection {
    local -r domain=$1
    local -r resolver=$2
    local -r reference=$3

    local reference_result
    local test_result

    reference_result="$(query "$reference" "$resolver")"
    if [[ -z "$reference_result" ]]; then
        log "Not an open resolver, skipping"
    else
        test_result="$(query "$domain" "$resolver")"
        if [[ -z "$test_result" ]]; then
            echo "anomaly"
        else
            log "Got $(tr "\n" " " <<< "$test_result")"
        fi
    fi
}

function query {
    local -r domain=$1
    local -r resolver=$2

    local response
    response=$(dig +short +multiline +timeout=2 +tries=2 \
               "@$resolver" "$domain" A)

    #shellcheck disable=SC2181
    [[ $? -ne 0 ]] && return
    echo -n "$response"
}

function main {
    local -r domain="$1"
    local -r resolvers_json="$2"
    local -r reference=google.com

    local baseline
    baseline="$(query "$domain" 1.1.1.1)"
    [[ -z $baseline ]] && echo "NXDOMAIN" && exit 1

    mapfile -t resolvers < <(jq -c ".[]" "$resolvers_json")

    count=0
    for resolver in "${resolvers[@]}"; do
        resolver_ip="$(jq -r .ip <<< "$resolver")"
        as_number="$(jq -r .as_number <<< "$resolver")"
        as_org="$(jq -r .as_org <<< "$resolver")"

        echo "Checking AS$as_number $as_org"
        if [[ -n "$(anomaly_detection "$domain" "$resolver_ip" "$reference")" ]]; then
            echo -e "\e[31mBad result from AS$as_number $as_org ($resolver_ip)\e[39m"
            ((count++)) || true
        fi

    done

    exit "$count"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
