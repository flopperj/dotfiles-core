#!/bin/bash
# Read the plain text content of a Google Doc
# Usage: read_doc.sh DOC_ID

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVE_SCRIPTS="$(dirname "$SCRIPT_DIR")/../google-drive/scripts"
source "$DRIVE_SCRIPTS/_auth.sh"
source "$DRIVE_SCRIPTS/_common.sh"

check_dependencies || exit 1

DOC_ID=""

print_usage() {
    cat <<'EOF'
Read the plain text content of a Google Doc

Usage: read_doc.sh DOC_ID

Arguments:
  DOC_ID                Google Doc ID or URL

Options:
  -h, --help            Show this help

Examples:
  read_doc.sh DOC_ID                       # Read document content
  read_doc.sh https://docs.google.com/document/d/DOC_ID/edit
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
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

# Get document content
RESPONSE=$(curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    "$DOCS_API/documents/$DOC_ID")

if ! handle_api_error "$RESPONSE" "Read document"; then
    exit 1
fi

# Extract plain text from the document body
# The body.content array contains structural elements (paragraphs, tables, etc.)
# We extract text from paragraph elements
echo "$RESPONSE" | jq -r '
    .body.content[]? |
    select(.paragraph) |
    .paragraph.elements[]? |
    select(.textRun) |
    .textRun.content // ""
' | tr -d '\r'
