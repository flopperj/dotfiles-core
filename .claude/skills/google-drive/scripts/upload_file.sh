#!/bin/bash
# Upload a local file to Google Drive
# Usage: upload_file.sh FILE_PATH [--folder FOLDER_ID] [--name "filename"]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_auth.sh"
source "$SCRIPT_DIR/_common.sh"

check_dependencies || exit 1

FILE_PATH=""
FOLDER_ID=""
CUSTOM_NAME=""

print_usage() {
    cat <<'EOF'
Upload a file to Google Drive

Usage: upload_file.sh FILE_PATH [OPTIONS]

Arguments:
  FILE_PATH             Path to local file to upload

Options:
  -f, --folder ID       Parent folder ID (default: My Drive root)
  -n, --name NAME       Custom name for the uploaded file (default: original filename)
  -h, --help            Show this help

Examples:
  upload_file.sh image.png                      # Upload to root
  upload_file.sh image.png --folder FOLDER_ID   # Upload to folder
  upload_file.sh image.png --name "diagram.png"  # Custom name

Returns file ID and webViewLink for use with other scripts.
EOF
}

if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
fi

FILE_PATH="$1"
shift

if [[ ! -f "$FILE_PATH" ]]; then
    echo "ERROR: File not found: $FILE_PATH" >&2
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--folder) FOLDER_ID="$2"; shift 2 ;;
        -n|--name) CUSTOM_NAME="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

FILENAME="${CUSTOM_NAME:-$(basename "$FILE_PATH")}"

detect_mime_type() {
    if command -v file &>/dev/null; then
        file -b --mime-type "$FILE_PATH"
    else
        case "${FILE_PATH,,}" in
            *.png) echo "image/png" ;;
            *.jpg|*.jpeg) echo "image/jpeg" ;;
            *.gif) echo "image/gif" ;;
            *.pdf) echo "application/pdf" ;;
            *) echo "application/octet-stream" ;;
        esac
    fi
}

MIME_TYPE=$(detect_mime_type)

if [[ -n "$FOLDER_ID" ]]; then
    METADATA=$(jq -n -c --arg name "$FILENAME" --arg mime "$MIME_TYPE" --arg folder "$FOLDER_ID" '{
        name: $name,
        mimeType: $mime,
        parents: [$folder]
    }')
else
    METADATA=$(jq -n -c --arg name "$FILENAME" --arg mime "$MIME_TYPE" '{
        name: $name,
        mimeType: $mime
    }')
fi

# Use multipart/related per Drive API (metadata first, then file content)
BOUNDARY="boundary_$(date +%s)_$$"
RESPONSE=$( (
    printf '%s\r\n' "--${BOUNDARY}" "Content-Type: application/json; charset=UTF-8" ""
    printf '%s\r\n' "$METADATA"
    printf '%s\r\n' "--${BOUNDARY}" "Content-Type: ${MIME_TYPE}" ""
    cat "$FILE_PATH"
    printf '\r\n%s\r\n' "--${BOUNDARY}--"
) | curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    -H "Content-Type: multipart/related; boundary=${BOUNDARY}" \
    --data-binary @- \
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink,webContentLink")

if ! handle_api_error "$RESPONSE" "Upload file"; then
    exit 1
fi

FILE_ID=$(echo "$RESPONSE" | jq -r '.id')
WEB_VIEW=$(echo "$RESPONSE" | jq -r '.webViewLink')
WEB_CONTENT=$(echo "$RESPONSE" | jq -r '.webContentLink // empty')

echo "File ID: $FILE_ID"
echo "Name: $(echo "$RESPONSE" | jq -r '.name')"
echo "URL: $WEB_VIEW"
if [[ -n "$WEB_CONTENT" ]]; then
    echo "webContentLink: $WEB_CONTENT"
fi
