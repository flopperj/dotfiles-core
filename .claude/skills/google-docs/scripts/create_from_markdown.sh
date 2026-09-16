#!/bin/bash
# Create a Google Doc from a Markdown file or stdin
# Usage: create_from_markdown.sh "Title" [--file PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVE_SCRIPTS="$SCRIPT_DIR/../../google-drive/scripts"
source "$DRIVE_SCRIPTS/_auth.sh"
source "$DRIVE_SCRIPTS/_common.sh"

check_dependencies || exit 1

TITLE=""
FILE_PATH=""

print_usage() {
    cat <<'EOF'
Create a Google Doc from Markdown

Usage: create_from_markdown.sh TITLE [OPTIONS]

Arguments:
  TITLE                 Document title

Options:
      --file PATH       Read Markdown from file (otherwise reads from stdin)
  -h, --help            Show this help

Examples:
  create_from_markdown.sh "Report" --file report.md        # From file
  cat report.md | create_from_markdown.sh "Report"         # From stdin
  echo "# Hello World" | create_from_markdown.sh "Test"    # From echo

Google Docs converts Markdown to native formatting:
  - Headings (# ## ###)
  - Lists (- * 1.)
  - Bold (**text**) and italic (*text*)
  - Links [text](url)
  - Code blocks
  - Tables
EOF
}

if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --file) FILE_PATH="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        -*)
            echo "Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
        *)
            if [[ -z "$TITLE" ]]; then
                TITLE="$1"
            else
                echo "Unexpected argument: $1" >&2
                print_usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$TITLE" ]]; then
    echo "ERROR: Title is required" >&2
    print_usage >&2
    exit 1
fi

# Read Markdown content
if [[ -n "$FILE_PATH" ]]; then
    if [[ ! -f "$FILE_PATH" ]]; then
        echo "ERROR: File not found: $FILE_PATH" >&2
        exit 1
    fi
    MARKDOWN_CONTENT=$(cat "$FILE_PATH")
else
    if [[ -t 0 ]]; then
        echo "ERROR: No input. Pipe Markdown content or use --file" >&2
        print_usage >&2
        exit 1
    fi
    MARKDOWN_CONTENT=$(cat)
fi

if [[ -z "$MARKDOWN_CONTENT" ]]; then
    echo "ERROR: No content provided" >&2
    exit 1
fi

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

# Use Drive API multipart upload to convert Markdown to Google Doc
# Create metadata JSON with target mimeType for conversion
METADATA=$(jq -n --arg name "$TITLE" '{
    name: $name,
    mimeType: "application/vnd.google-apps.document"
}')

# Generate a unique boundary for multipart request
BOUNDARY="boundary_$(date +%s)_$$"

# Build multipart body
MULTIPART_BODY="--${BOUNDARY}
Content-Type: application/json; charset=UTF-8

${METADATA}
--${BOUNDARY}
Content-Type: text/markdown

${MARKDOWN_CONTENT}
--${BOUNDARY}--"

RESPONSE=$(curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    -H "Content-Type: multipart/related; boundary=${BOUNDARY}" \
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink" \
    --data-binary "$MULTIPART_BODY")

if ! handle_api_error "$RESPONSE" "Create document"; then
    exit 1
fi

FILE_ID=$(echo "$RESPONSE" | jq -r '.id')

echo "Document ID: $FILE_ID"
echo "URL: https://docs.google.com/document/d/$FILE_ID/edit"
