#!/bin/bash
# Download files from Google Drive to local filesystem
# Usage: download_file.sh FILE_ID [--output PATH] [--format FORMAT] [--stdout]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_auth.sh"
source "$SCRIPT_DIR/_common.sh"

check_dependencies || exit 1

FILE_ID=""
OUTPUT_PATH=""
EXPORT_FORMAT=""
TO_STDOUT=false

print_usage() {
    cat <<'EOF'
Download files from Google Drive

Usage: download_file.sh FILE_ID [OPTIONS]

Arguments:
  FILE_ID               Google Drive file ID or URL

Options:
  -o, --output PATH     Output file path (default: original filename)
  -f, --format FORMAT   Export format for Google Workspace files
  -s, --stdout          Print content to stdout (text files only)
  -h, --help            Show this help

Export formats by file type:
  Google Docs:    text, md, pdf, docx, html
  Google Sheets:  csv, xlsx, pdf
  Google Slides:  pdf, pptx

Examples:
  download_file.sh FILE_ID                       # Download file (auto-detect format)
  download_file.sh FILE_ID --output report.txt   # Download to specific path
  download_file.sh FILE_ID --format md           # Export Google Doc as markdown
  download_file.sh FILE_ID --stdout              # Print text content to stdout
  download_file.sh FILE_ID --format csv          # Export Sheet as CSV
EOF
}

if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
fi

FILE_ID=$(extract_file_id "$1") || exit 1
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output) OUTPUT_PATH="$2"; shift 2 ;;
        -f|--format) EXPORT_FORMAT="$2"; shift 2 ;;
        -s|--stdout) TO_STDOUT=true; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

META_RESPONSE=$(curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    "$DRIVE_API/files/$FILE_ID?fields=id,name,mimeType,size,webViewLink")

if ! handle_api_error "$META_RESPONSE" "Get file info"; then
    exit 1
fi

ORIGINAL_NAME=$(echo "$META_RESPONSE" | jq -r '.name')
MIME_TYPE=$(echo "$META_RESPONSE" | jq -r '.mimeType')

# Workspace-native files (Docs, Sheets, Slides) have no binary body to download; they must be exported to a concrete format
IS_WORKSPACE_FILE=false
case "$MIME_TYPE" in
    application/vnd.google-apps.document|\
    application/vnd.google-apps.spreadsheet|\
    application/vnd.google-apps.presentation)
        IS_WORKSPACE_FILE=true
        ;;
esac

if [[ "$IS_WORKSPACE_FILE" == "true" ]]; then
    case "$MIME_TYPE" in
        application/vnd.google-apps.document)
            case "${EXPORT_FORMAT:-text}" in
                text|txt) EXPORT_MIME="text/plain"; EXT=".txt" ;;
                md|markdown) EXPORT_MIME="text/plain"; EXT=".md" ;;
                pdf) EXPORT_MIME="application/pdf"; EXT=".pdf" ;;
                docx) EXPORT_MIME="application/vnd.openxmlformats-officedocument.wordprocessingml.document"; EXT=".docx" ;;
                html) EXPORT_MIME="text/html"; EXT=".html" ;;
                *)
                    echo "Invalid format '$EXPORT_FORMAT' for Google Docs" >&2
                    echo "Available formats: text, md, pdf, docx, html" >&2
                    exit 1
                    ;;
            esac
            ;;
        application/vnd.google-apps.spreadsheet)
            case "${EXPORT_FORMAT:-csv}" in
                csv) EXPORT_MIME="text/csv"; EXT=".csv" ;;
                xlsx) EXPORT_MIME="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"; EXT=".xlsx" ;;
                pdf) EXPORT_MIME="application/pdf"; EXT=".pdf" ;;
                *)
                    echo "Invalid format '$EXPORT_FORMAT' for Google Sheets" >&2
                    echo "Available formats: csv, xlsx, pdf" >&2
                    exit 1
                    ;;
            esac
            ;;
        application/vnd.google-apps.presentation)
            case "${EXPORT_FORMAT:-pdf}" in
                pdf) EXPORT_MIME="application/pdf"; EXT=".pdf" ;;
                pptx) EXPORT_MIME="application/vnd.openxmlformats-officedocument.presentationml.presentation"; EXT=".pptx" ;;
                *)
                    echo "Invalid format '$EXPORT_FORMAT' for Google Slides" >&2
                    echo "Available formats: pdf, pptx" >&2
                    exit 1
                    ;;
            esac
            ;;
    esac
    
    ENCODED_MIME=$(url_encode "$EXPORT_MIME")
    DOWNLOAD_URL="$DRIVE_API/files/$FILE_ID/export?mimeType=$ENCODED_MIME"
    
    if [[ "$TO_STDOUT" == "true" ]]; then
        case "$EXPORT_MIME" in
            application/pdf|application/vnd.openxmlformats-*)
                echo "ERROR: Cannot output binary content to stdout" >&2
                exit 1
                ;;
        esac
        
        curl -sS -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $QUOTA_PROJECT" "$DOWNLOAD_URL"
    else
        if [[ -z "$OUTPUT_PATH" ]]; then
            BASE_NAME="${ORIGINAL_NAME%.*}"
            OUTPUT_PATH="$BASE_NAME$EXT"
        fi
        
        curl -sS -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $QUOTA_PROJECT" "$DOWNLOAD_URL" -o "$OUTPUT_PATH"
        echo "Downloaded: $OUTPUT_PATH" >&2
    fi
else
    if [[ "$TO_STDOUT" == "true" ]]; then
        echo "ERROR: Cannot output binary files to stdout. Use --output instead." >&2
        exit 1
    fi
    
    DOWNLOAD_URL="$DRIVE_API/files/$FILE_ID?alt=media"
    
    if [[ -z "$OUTPUT_PATH" ]]; then
        OUTPUT_PATH="$ORIGINAL_NAME"
    fi
    
    curl -sS -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $QUOTA_PROJECT" "$DOWNLOAD_URL" -o "$OUTPUT_PATH"
    echo "Downloaded: $OUTPUT_PATH" >&2
fi
