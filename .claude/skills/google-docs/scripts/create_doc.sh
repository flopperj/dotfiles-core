#!/bin/bash
# Create a new Google Doc with optional Markdown content
# Usage: create_doc.sh "Title" ["Content"] [--markdown]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVE_SCRIPTS="$SCRIPT_DIR/../../google-drive/scripts"
source "$DRIVE_SCRIPTS/_auth.sh"
source "$DRIVE_SCRIPTS/_common.sh"

check_dependencies || exit 1

TITLE=""
CONTENT=""
USE_MARKDOWN=false

print_usage() {
    cat <<'EOF'
Create a new Google Doc

Usage: create_doc.sh TITLE [CONTENT] [OPTIONS]

Arguments:
  TITLE                 Document title
  CONTENT               Initial content (optional)

Options:
      --markdown        Convert content from Markdown to formatted text
  -h, --help            Show this help

Examples:
  create_doc.sh "My Document"                              # Create empty doc
  create_doc.sh "My Document" "Hello, world!"              # Create with plain text
  create_doc.sh "Report" "# Summary\n\n- Item 1" --markdown  # Create with Markdown
EOF
}

if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --markdown) USE_MARKDOWN=true; shift ;;
        -h|--help) print_usage; exit 0 ;;
        -*)
            echo "Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
        *)
            if [[ -z "$TITLE" ]]; then
                TITLE="$1"
            elif [[ -z "$CONTENT" ]]; then
                CONTENT="$1"
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

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

if [[ "$USE_MARKDOWN" == "true" && -n "$CONTENT" ]]; then
    # Drive's multipart upload converts text/markdown into a native Google Doc when the metadata names the Doc mimeType; the Docs API has no Markdown import.
    CONTENT=$(printf '%b' "$CONTENT")
    
    METADATA=$(jq -n --arg name "$TITLE" '{
        name: $name,
        mimeType: "application/vnd.google-apps.document"
    }')
    
    BOUNDARY="boundary_$(date +%s)_$$"
    
    MULTIPART_BODY="--${BOUNDARY}
Content-Type: application/json; charset=UTF-8

${METADATA}
--${BOUNDARY}
Content-Type: text/markdown

${CONTENT}
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
else
    CREATE_BODY=$(jq -n --arg title "$TITLE" '{title: $title}')
    
    RESPONSE=$(curl -sS -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "x-goog-user-project: $QUOTA_PROJECT" \
        -H "Content-Type: application/json" \
        "$DOCS_API/documents" \
        -d "$CREATE_BODY")
    
    if ! handle_api_error "$RESPONSE" "Create document"; then
        exit 1
    fi
    
    DOC_ID=$(echo "$RESPONSE" | jq -r '.documentId')
    
    if [[ -n "$CONTENT" ]]; then
        CONTENT=$(printf '%b' "$CONTENT")
        
        [[ "${CONTENT: -1}" != $'\n' ]] && CONTENT+=$'\n'
        
        INSERT_BODY=$(jq -n --arg text "$CONTENT" '{
            requests: [{
                insertText: {
                    location: {index: 1},
                    text: $text
                }
            }]
        }')
        
        UPDATE_RESPONSE=$(curl -sS -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -H "x-goog-user-project: $QUOTA_PROJECT" \
            -H "Content-Type: application/json" \
            "$DOCS_API/documents/$DOC_ID:batchUpdate" \
            -d "$INSERT_BODY")
        
        if ! handle_api_error "$UPDATE_RESPONSE" "Insert content"; then
            exit 1
        fi
    fi
    
    echo "Document ID: $DOC_ID"
    echo "URL: https://docs.google.com/document/d/$DOC_ID/edit"
fi
