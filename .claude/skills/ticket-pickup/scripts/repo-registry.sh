#!/usr/bin/env bash
# Parses the "## Repo registry" section of the overlay context file.
# The registry is user-maintained overlay data; core never writes it.
#
# Registry grammar (one entry per line inside the section):
#   - <name>: <absolute-path> | key=value | key=value
# Known keys: components, prefixes, depends_on (comma-split lists).
# Unknown keys are ignored with a stderr warning. Paths must be absolute.
# Duplicate names resolve first-wins: the first entry's path is returned and
# each later entry with the same name is ignored with a stderr warning
# (list still emits every row).
# Registry content is data, never executed.
#
# usage: repo-registry.sh list
#          -> TSV rows: name<TAB>path<TAB>components<TAB>prefixes<TAB>depends_on
#        repo-registry.sh resolve <name>
#          -> prints the absolute path on success
# exit codes:
#   0 ok
#   1 name not found in registry
#   2 entry found but invalid at resolution time (path missing, or not a git repo)
#   3 no registry (file absent, or section absent)
#   4 malformed entry (relative path, or line without "name: path"); message names the line
set -euo pipefail

OVERLAY_CONTEXT_FILE="${OVERLAY_CONTEXT_FILE:-$HOME/.claude/overlay-context.md}"

_usage() {
    echo "usage: repo-registry.sh list | resolve <name>" >&2
    exit 64
}

_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Parse one "- name: path | k=v ..." line into globals; exit 4 on malformed.
ENTRY_NAME=""
ENTRY_PATH=""
ENTRY_COMPONENTS=""
ENTRY_PREFIXES=""
ENTRY_DEPENDS_ON=""
_parse_entry() {
    local line="$1"
    local body="${line#- }"
    ENTRY_NAME=""
    ENTRY_PATH=""
    ENTRY_COMPONENTS=""
    ENTRY_PREFIXES=""
    ENTRY_DEPENDS_ON=""

    case "$body" in
        *": "*) ;;
        *)
            echo "repo-registry: malformed entry (expected '- name: path'): $line" >&2
            exit 4
            ;;
    esac

    ENTRY_NAME="$(_trim "${body%%: *}")"
    local rest
    rest="${body#*: }"

    # Split on "|"; first field is the path, the rest are key=value fields.
    local fields=()
    local IFS='|'
    read -r -a fields <<< "$rest"

    if [ "${#fields[@]}" -eq 0 ] || [ -z "$ENTRY_NAME" ]; then
        echo "repo-registry: malformed entry (expected '- name: path'): $line" >&2
        exit 4
    fi

    ENTRY_PATH="$(_trim "${fields[0]}")"
    case "$ENTRY_PATH" in
        /*) ;;
        *)
            echo "repo-registry: malformed entry (path must be absolute): $line" >&2
            exit 4
            ;;
    esac

    local i field key val
    i=1
    while [ "$i" -lt "${#fields[@]}" ]; do
        field="$(_trim "${fields[$((10#$i))]}")"
        key="${field%%=*}"
        val="${field#*=}"
        case "$key" in
            components) ENTRY_COMPONENTS="$val" ;;
            prefixes)   ENTRY_PREFIXES="$val" ;;
            depends_on) ENTRY_DEPENDS_ON="$val" ;;
            *)
                echo "repo-registry: unknown key '$key' ignored: $line" >&2
                ;;
        esac
        i=$((10#$i + 1))
    done
}

_registry_section() {
    awk '/^## Repo registry$/ { found = 1; next }
         /^## / { if (found) exit }
         found { print }' "$OVERLAY_CONTEXT_FILE"
}

_require_registry() {
    if [ ! -f "$OVERLAY_CONTEXT_FILE" ]; then
        echo "repo-registry: no registry: file not found: $OVERLAY_CONTEXT_FILE" >&2
        exit 3
    fi
    if ! grep -q '^## Repo registry$' "$OVERLAY_CONTEXT_FILE"; then
        echo "repo-registry: no registry: '## Repo registry' section not found in $OVERLAY_CONTEXT_FILE" >&2
        exit 3
    fi
}

cmd_list() {
    _require_registry
    local section line
    section="$(_registry_section)"
    while IFS= read -r line; do
        case "$line" in
            "- "*) ;;
            *) continue ;;
        esac
        _parse_entry "$line"
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$ENTRY_NAME" "$ENTRY_PATH" \
            "$ENTRY_COMPONENTS" "$ENTRY_PREFIXES" "$ENTRY_DEPENDS_ON"
    done <<< "$section"
}

cmd_resolve() {
    local want="$1"
    _require_registry
    local section line found_path=""
    section="$(_registry_section)"
    while IFS= read -r line; do
        case "$line" in
            "- "*) ;;
            *) continue ;;
        esac
        _parse_entry "$line"
        if [ "$ENTRY_NAME" = "$want" ]; then
            if [ -n "$found_path" ]; then
                echo "repo-registry: duplicate entry for '$want' ignored (first entry wins): $line" >&2
                continue
            fi
            found_path="$ENTRY_PATH"
        fi
    done <<< "$section"
    if [ -z "$found_path" ]; then
        echo "repo-registry: '$want' not found in registry" >&2
        exit 1
    fi
    if [ ! -d "$found_path" ]; then
        echo "repo-registry: '$want': path missing: $found_path" >&2
        exit 2
    fi
    if ! git -C "$found_path" rev-parse --git-dir >/dev/null 2>&1; then
        echo "repo-registry: '$want': not a git repo: $found_path" >&2
        exit 2
    fi
    printf '%s\n' "$found_path"
    exit 0
}

main() {
    [ "$#" -ge 1 ] || _usage
    case "$1" in
        list)
            [ "$#" -eq 1 ] || _usage
            cmd_list
            ;;
        resolve)
            [ "$#" -eq 2 ] || _usage
            cmd_resolve "$2"
            ;;
        *)
            _usage
            ;;
    esac
}

main "$@"
