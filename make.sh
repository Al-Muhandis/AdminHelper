#!/usr/bin/env bash

function priv_clippit
(
    cat <<EOF
Usage: bash ${0} [OPTIONS]
Options:
    build   Build program
EOF
)

function priv_main
(
    set -euo pipefail
    if ((${#})); then
        case ${1} in
            build)
                if ! (which lazbuild); then
                    source '/etc/os-release'
                    case ${ID:?} in
                        debian | ubuntu)
                            sudo apt-get update
                            sudo apt-get install -y lazarus
                            ;;
                    esac
                fi
                if [[ -d 'use' ]]; then
                    git submodule update --recursive --init
                    git submodule update --recursive --remote
                    find 'use' -type 'f' -name '*.lpk' -exec lazbuild --add-package-link {} +
                fi
                find 'src' -type 'f' -name '*.lpi' \
                    -exec lazbuild --no-write-project --recursive --no-write-project --build-mode=release {} + 1>&2
                ;;
        esac
    else
        priv_clippit
    fi
)

priv_main "${@}" >/dev/null
