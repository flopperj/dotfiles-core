#!/bin/bash
# Search Google Drive files by name, type, or content
# Usage: search_files.sh [--name NAME] [--type TYPE] [--query QUERY] [--folder ID] [--max N] [--trashed] [--format FORMAT]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_auth.sh"
source "$SCRIPT_DIR/_common.sh"

check_dependencies || exit 1

NAME=""
FILE_TYPE=""
QUERY=""
FOLDER=""
MAX_RESULTS=20
INCLUDE_TRASHED=false
OUTPUT_FORMAT="table"

print_usage() {
    cat <<'EOF'
Search Google Drive files

Usage: search_files.sh [OPTIONS]

Options:
  -n, --name NAME       Search for files containing NAME in filename
  -t, --type TYPE       Filter by type: doc, sheet, slide, pdf, image, folder, all
  -q, --query QUERY     Raw Drive API query string (advanced)
  -f, --folder ID       Folder ID to search within
  -m, --max N           Maximum results (default: 20)
      --trashed         Include trashed files
      --format FORMAT   Output format: table, json, ids (default: table)
  -h, --help            Show this help

Examples:
  search_files.sh --name "report"              # Find files with "report" in name
  search_files.sh --type doc                   # Find all Google Docs
  search_files.sh --type pdf --name "invoice"  # Find PDFs with "invoice" in name
  search_files.sh --query "fullText contains 'budget'"  # Full-text search
  search_files.sh --format json                # Output as JSON
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name) NAME="$2"; shift 2 ;;
        -t|--type) FILE_TYPE="$2"; shift 2 ;;
        -q|--query) QUERY="$2"; shift 2 ;;
        -f|--folder) FOLDER="$2"; shift 2 ;;
        -m|--max) MAX_RESULTS="$2"; shift 2 ;;
        --trashed) INCLUDE_TRASHED=true; shift ;;
        --format) OUTPUT_FORMAT="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

# Build query parts
QUERY_PARTS=()

if [[ -n "$QUERY" ]]; then
    QUERY_PARTS+=("$QUERY")
fi

if [[ -n "$NAME" ]]; then
    QUERY_PARTS+=("name contains '$NAME'")
fi

if [[ -n "$FILE_TYPE" && "$FILE_TYPE" != "all" ]]; then
    case "$FILE_TYPE" in
        image)
            QUERY_PARTS+=("mimeType contains 'image/'")
            ;;
        doc|document|sheet|spreadsheet|slide|presentation|folder|pdf)
            MIME=$(get_mime_type "$FILE_TYPE")
            QUERY_PARTS+=("mimeType = '$MIME'")
            ;;
        *)
            echo "Unknown type: $FILE_TYPE" >&2
            echo "Valid types: doc, sheet, slide, pdf, image, folder, all" >&2
            exit 1
            ;;
    esac
fi

if [[ -n "$FOLDER" ]]; then
    QUERY_PARTS+=("'$FOLDER' in parents")
fi

if [[ "$INCLUDE_TRASHED" != "true" ]]; then
    QUERY_PARTS+=("trashed = false")
fi

# Join query parts with " and "
Q=""
for i in "${!QUERY_PARTS[@]}"; do
    if [[ $i -gt 0 ]]; then
        Q+=" and "
    fi
    Q+="${QUERY_PARTS[$i]}"
done

# Build request URL
URL="$DRIVE_API/files?pageSize=$MAX_RESULTS&orderBy=modifiedTime%20desc"
URL+="&fields=files(id,name,mimeType,modifiedTime,size,webViewLink,parents)"

if [[ -n "$Q" ]]; then
    ENCODED_Q=$(url_encode "$Q")
    URL+="&q=$ENCODED_Q"
fi

# Make API request
RESPONSE=$(curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    "$URL")

# Check for errors
if ! handle_api_error "$RESPONSE" "Search"; then
    exit 1
fi

# Output results
case "$OUTPUT_FORMAT" in
    json)
        echo "$RESPONSE" | jq '.files'
        ;;
    ids)
        echo "$RESPONSE" | jq -r '.files[].id'
        ;;
    table)
        FILES_COUNT=$(echo "$RESPONSE" | jq '.files | length')
        
        if [[ "$FILES_COUNT" -eq 0 ]]; then
            echo "No files found."
            exit 0
        fi
        
        print_table_header
        
        echo "$RESPONSE" | jq -r '.files[] | [.name, .mimeType, .modifiedTime, .id] | @tsv' | \
        while IFS=$'\t' read -r name mime modified id; do
            print_file_row "$name" "$mime" "$modified" "$id"
        done
        ;;
    *)
        echo "Unknown format: $OUTPUT_FORMAT" >&2
        exit 1
        ;;
esac
