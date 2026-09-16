#!/bin/bash
# Get metadata about a Google Doc
# Usage: doc_info.sh DOC_ID [--format json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVE_SCRIPTS="$(dirname "$SCRIPT_DIR")/../google-drive/scripts"
source "$DRIVE_SCRIPTS/_auth.sh"
source "$DRIVE_SCRIPTS/_common.sh"

check_dependencies || exit 1

DOC_ID=""
OUTPUT_FORMAT="text"

print_usage() {
    cat <<'EOF'
Get metadata about a Google Doc

Usage: doc_info.sh DOC_ID [OPTIONS]

Arguments:
  DOC_ID                Google Doc ID or URL

Options:
  --format FORMAT       Output format: text, json (default: text)
  -h, --help            Show this help

Examples:
  doc_info.sh DOC_ID                 # Get document info
  doc_info.sh DOC_ID --format json   # Get document info as JSON
EOF
}

if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
fi

# First argument is doc ID
DOC_ID=$(extract_file_id "$1") || exit 1
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --format) OUTPUT_FORMAT="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

# Get document metadata
RESPONSE=$(curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    "$DOCS_API/documents/$DOC_ID")

if ! handle_api_error "$RESPONSE" "Get document info"; then
    exit 1
fi

case "$OUTPUT_FORMAT" in
    json)
        echo "$RESPONSE" | jq '.'
        ;;
    text)
        echo "Document Information"
        echo "==================="
        echo ""
        echo "Title:        $(echo "$RESPONSE" | jq -r '.title')"
        echo "Document ID:  $(echo "$RESPONSE" | jq -r '.documentId')"
        echo ""
        echo "URL:          https://docs.google.com/document/d/$DOC_ID/edit"
        
        # Get revision info if available
        REVISION_ID=$(echo "$RESPONSE" | jq -r '.revisionId // "N/A"')
        if [[ "$REVISION_ID" != "N/A" && -n "$REVISION_ID" ]]; then
            echo "Revision ID:  $REVISION_ID"
        fi
        
        # Document style info
        MARGINS=$(echo "$RESPONSE" | jq -r '.documentStyle // empty')
        if [[ -n "$MARGINS" && "$MARGINS" != "null" ]]; then
            echo ""
            echo "Document Style:"
            
            PAGE_WIDTH=$(echo "$RESPONSE" | jq -r '.documentStyle.pageSize.width.magnitude // "N/A"')
            PAGE_HEIGHT=$(echo "$RESPONSE" | jq -r '.documentStyle.pageSize.height.magnitude // "N/A"')
            if [[ "$PAGE_WIDTH" != "N/A" ]]; then
                echo "  Page Size:  ${PAGE_WIDTH}pt x ${PAGE_HEIGHT}pt"
            fi
        fi
        
        # Body content stats
        CONTENT_LENGTH=$(echo "$RESPONSE" | jq '[.body.content[].endIndex] | max // 0')
        echo ""
        echo "Content length: ~$CONTENT_LENGTH characters"
        ;;
    *)
        echo "Unknown format: $OUTPUT_FORMAT" >&2
        exit 1
        ;;
esac
