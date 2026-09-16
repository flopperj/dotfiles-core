#!/bin/bash
# Get detailed information about a Google Drive file
# Usage: file_info.sh FILE_ID [--format json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_auth.sh"
source "$SCRIPT_DIR/_common.sh"

check_dependencies || exit 1

FILE_ID=""
OUTPUT_FORMAT="text"

print_usage() {
    cat <<'EOF'
Get detailed information about a Google Drive file

Usage: file_info.sh FILE_ID [OPTIONS]

Arguments:
  FILE_ID               Google Drive file ID or URL

Options:
  --format FORMAT       Output format: text, json (default: text)
  -h, --help            Show this help

Examples:
  file_info.sh FILE_ID                 # Get file info
  file_info.sh FILE_ID --format json   # Get file info as JSON
EOF
}

if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
fi

# First argument is file ID
FILE_ID=$(extract_file_id "$1") || exit 1
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

# Request detailed fields
FIELDS="id,name,mimeType,createdTime,modifiedTime,size,description"
FIELDS+=",webViewLink,webContentLink,owners,sharingUser,shared,permissions"
FIELDS+=",parents,starred,trashed,capabilities"

RESPONSE=$(curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    "$DRIVE_API/files/$FILE_ID?fields=$FIELDS")

if ! handle_api_error "$RESPONSE" "Get file info"; then
    exit 1
fi

case "$OUTPUT_FORMAT" in
    json)
        echo "$RESPONSE" | jq '.'
        ;;
    text)
        echo "File Information"
        echo "================"
        echo ""
        echo "Name:         $(echo "$RESPONSE" | jq -r '.name')"
        echo "ID:           $(echo "$RESPONSE" | jq -r '.id')"
        echo "Type:         $(get_type_name "$(echo "$RESPONSE" | jq -r '.mimeType')")"
        echo "MIME Type:    $(echo "$RESPONSE" | jq -r '.mimeType')"
        echo ""
        echo "Created:      $(echo "$RESPONSE" | jq -r '.createdTime // "N/A"')"
        echo "Modified:     $(echo "$RESPONSE" | jq -r '.modifiedTime // "N/A"')"
        
        SIZE=$(echo "$RESPONSE" | jq -r '.size // "N/A"')
        if [[ "$SIZE" != "N/A" && -n "$SIZE" ]]; then
            # Convert bytes to human readable
            if [[ $SIZE -gt 1073741824 ]]; then
                SIZE_HUMAN="$(echo "scale=2; $SIZE / 1073741824" | bc) GB"
            elif [[ $SIZE -gt 1048576 ]]; then
                SIZE_HUMAN="$(echo "scale=2; $SIZE / 1048576" | bc) MB"
            elif [[ $SIZE -gt 1024 ]]; then
                SIZE_HUMAN="$(echo "scale=2; $SIZE / 1024" | bc) KB"
            else
                SIZE_HUMAN="$SIZE bytes"
            fi
            echo "Size:         $SIZE_HUMAN ($SIZE bytes)"
        fi
        
        echo ""
        echo "URL:          $(echo "$RESPONSE" | jq -r '.webViewLink // "N/A"')"
        
        DESC=$(echo "$RESPONSE" | jq -r '.description // ""')
        if [[ -n "$DESC" ]]; then
            echo "Description:  $DESC"
        fi
        
        echo ""
        echo "Owner:        $(echo "$RESPONSE" | jq -r '.owners[0].displayName // "Unknown"') <$(echo "$RESPONSE" | jq -r '.owners[0].emailAddress // "N/A"')>"
        echo "Shared:       $(echo "$RESPONSE" | jq -r 'if .shared then "Yes" else "No" end')"
        
        if [[ $(echo "$RESPONSE" | jq '.permissions | length') -gt 0 ]]; then
            echo ""
            echo "Permissions:"
            echo "$RESPONSE" | jq -r '.permissions[] | "  - \(.role): \(.emailAddress // .type)"'
        fi
        
        echo ""
        echo "Starred:      $(echo "$RESPONSE" | jq -r 'if .starred then "Yes" else "No" end')"
        echo "Trashed:      $(echo "$RESPONSE" | jq -r 'if .trashed then "Yes" else "No" end')"
        ;;
    *)
        echo "Unknown format: $OUTPUT_FORMAT" >&2
        exit 1
        ;;
esac
