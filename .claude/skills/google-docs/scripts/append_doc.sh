#!/bin/bash
# Append text to an existing Google Doc
# Usage: append_doc.sh DOC_ID TEXT

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVE_SCRIPTS="$(dirname "$SCRIPT_DIR")/../google-drive/scripts"
source "$DRIVE_SCRIPTS/_auth.sh"
source "$DRIVE_SCRIPTS/_common.sh"

check_dependencies || exit 1

DOC_ID=""
TEXT=""

print_usage() {
    cat <<'EOF'
Append text to an existing Google Doc

Usage: append_doc.sh DOC_ID TEXT

Arguments:
  DOC_ID                Google Doc ID or URL
  TEXT                  Text to append

Options:
  -h, --help            Show this help

Examples:
  append_doc.sh DOC_ID "New paragraph"
  append_doc.sh DOC_ID "\n\nMore content with newlines"
EOF
}

if [[ $# -lt 2 ]]; then
    print_usage
    exit 1
fi

DOC_ID=$(extract_file_id "$1") || exit 1
shift

TEXT="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

DOC_RESPONSE=$(curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    "$DOCS_API/documents/$DOC_ID?fields=body.content")

if ! handle_api_error "$DOC_RESPONSE" "Get document"; then
    exit 1
fi

# endIndex is exclusive and the body's final newline must stay last, so insert one position before it
END_INDEX=$(echo "$DOC_RESPONSE" | jq '[.body.content[].endIndex] | max')
INSERT_INDEX=$((END_INDEX - 1))

TEXT=$(printf '%b' "$TEXT")

REQUEST=$(jq -n --arg text "$TEXT" --argjson index "$INSERT_INDEX" '{
    requests: [
        {
            insertText: {
                location: {
                    index: $index
                },
                text: $text
            }
        }
    ]
}')

RESPONSE=$(curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    -H "Content-Type: application/json" \
    -d "$REQUEST" \
    "$DOCS_API/documents/$DOC_ID:batchUpdate")

if ! handle_api_error "$RESPONSE" "Append to document"; then
    exit 1
fi

echo "Text appended successfully to document: $DOC_ID"
echo "URL: https://docs.google.com/document/d/$DOC_ID/edit"
