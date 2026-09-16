#!/bin/bash
# Copy a Google Drive file (create from template)
# Usage: copy_file.sh FILE_ID [--name NAME] [--folder FOLDER_ID]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_auth.sh"
source "$SCRIPT_DIR/_common.sh"

check_dependencies || exit 1

FILE_ID=""
NEW_NAME=""
FOLDER_ID=""

print_usage() {
    cat <<'EOF'
Copy a Google Drive file

Usage: copy_file.sh FILE_ID [OPTIONS]

Arguments:
  FILE_ID               Source file ID or URL

Options:
  -n, --name NAME       Name for the copy (default: "Copy of [original]")
  -f, --folder ID       Parent folder ID for the copy
  -h, --help            Show this help

Examples:
  copy_file.sh FILE_ID                          # Create a copy
  copy_file.sh FILE_ID --name "My Report"       # Copy with specific name
  copy_file.sh FILE_ID --folder FOLDER_ID       # Copy to a specific folder
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
        -n|--name) NEW_NAME="$2"; shift 2 ;;
        -f|--folder) FOLDER_ID="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

# Build request body
BODY="{}"

if [[ -n "$NEW_NAME" ]]; then
    BODY=$(echo "$BODY" | jq --arg name "$NEW_NAME" '. + {name: $name}')
fi

if [[ -n "$FOLDER_ID" ]]; then
    BODY=$(echo "$BODY" | jq --arg folder "$FOLDER_ID" '. + {parents: [$folder]}')
fi

# Make copy request
RESPONSE=$(curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "$DRIVE_API/files/$FILE_ID/copy?fields=id,name,mimeType,webViewLink")

if ! handle_api_error "$RESPONSE" "Copy file"; then
    exit 1
fi

FILE_NAME=$(echo "$RESPONSE" | jq -r '.name')
NEW_FILE_ID=$(echo "$RESPONSE" | jq -r '.id')
WEB_LINK=$(echo "$RESPONSE" | jq -r '.webViewLink')

echo "Created copy: $FILE_NAME"
echo "File ID: $NEW_FILE_ID"
echo "URL: $WEB_LINK"
