#!/bin/bash
# Replace all content in a Google Doc
# Usage: replace_doc.sh DOC_ID "New content" [--markdown]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVE_SCRIPTS="$SCRIPT_DIR/../../google-drive/scripts"
source "$DRIVE_SCRIPTS/_auth.sh"
source "$DRIVE_SCRIPTS/_common.sh"

check_dependencies || exit 1

DOC_ID=""
NEW_CONTENT=""
USE_MARKDOWN=false

print_usage() {
    cat <<'EOF'
Replace all content in a Google Doc

Usage: replace_doc.sh DOC_ID CONTENT [OPTIONS]

Arguments:
  DOC_ID                Google Docs document ID or URL
  CONTENT               New content for the document

Options:
      --markdown        Convert content from Markdown (creates new doc)
  -h, --help            Show this help

Note: With --markdown, a new document is created because the Drive API
doesn't support in-place Markdown conversion.

Examples:
  replace_doc.sh DOC_ID "New content"
  replace_doc.sh DOC_ID "# New Heading\n\nNew text" --markdown
EOF
}

if [[ $# -lt 2 ]]; then
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
            if [[ -z "$DOC_ID" ]]; then
                DOC_ID=$(extract_file_id "$1") || exit 1
            elif [[ -z "$NEW_CONTENT" ]]; then
                NEW_CONTENT="$1"
            else
                echo "Unexpected argument: $1" >&2
                print_usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$DOC_ID" ]]; then
    echo "ERROR: Document ID is required" >&2
    print_usage >&2
    exit 1
fi

if [[ -z "$NEW_CONTENT" ]]; then
    echo "ERROR: Content is required" >&2
    print_usage >&2
    exit 1
fi

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

if [[ "$USE_MARKDOWN" == "true" ]]; then
    DOC_RESPONSE=$(curl -sS \
        -H "Authorization: Bearer $TOKEN" \
        -H "x-goog-user-project: $QUOTA_PROJECT" \
        "$DOCS_API/documents/$DOC_ID")
    
    if ! handle_api_error "$DOC_RESPONSE" "Get document"; then
        exit 1
    fi
    
    TITLE=$(echo "$DOC_RESPONSE" | jq -r '.title')
    
    NEW_CONTENT=$(printf '%b' "$NEW_CONTENT")
    
    # Drive's multipart upload converts text/markdown into a native Google Doc when the metadata names the Doc mimeType; the Docs API has no Markdown import.
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

${NEW_CONTENT}
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
    
    NEW_DOC_ID=$(echo "$RESPONSE" | jq -r '.id')
    
    echo "New Document ID: $NEW_DOC_ID"
    echo "URL: https://docs.google.com/document/d/$NEW_DOC_ID/edit"
    echo "Note: Markdown conversion creates a new document"
else
    DOC_RESPONSE=$(curl -sS \
        -H "Authorization: Bearer $TOKEN" \
        -H "x-goog-user-project: $QUOTA_PROJECT" \
        "$DOCS_API/documents/$DOC_ID")
    
    if ! handle_api_error "$DOC_RESPONSE" "Get document"; then
        exit 1
    fi
    
    END_INDEX=$(echo "$DOC_RESPONSE" | jq '[.body.content[]? | .endIndex // 0] | max')
    
    REQUESTS="[]"
    
    # An empty body still spans indices 1-2 (the mandatory trailing newline, which cannot be deleted), so only a longer body has content to clear
    if [[ $END_INDEX -gt 2 ]]; then
        DELETE_END=$((END_INDEX - 1))
        REQUESTS=$(echo "$REQUESTS" | jq --argjson end "$DELETE_END" '. + [{
            deleteContentRange: {
                range: {startIndex: 1, endIndex: $end}
            }
        }]')
    fi
    
    NEW_CONTENT=$(printf '%b' "$NEW_CONTENT")
    [[ "${NEW_CONTENT: -1}" != $'\n' ]] && NEW_CONTENT+=$'\n'
    
    REQUESTS=$(echo "$REQUESTS" | jq --arg text "$NEW_CONTENT" '. + [{
        insertText: {
            location: {index: 1},
            text: $text
        }
    }]')
    
    UPDATE_BODY=$(echo "$REQUESTS" | jq '{requests: .}')
    
    RESPONSE=$(curl -sS -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "x-goog-user-project: $QUOTA_PROJECT" \
        -H "Content-Type: application/json" \
        "$DOCS_API/documents/$DOC_ID:batchUpdate" \
        -d "$UPDATE_BODY")
    
    if ! handle_api_error "$RESPONSE" "Replace content"; then
        exit 1
    fi
    
    echo "Content replaced in document: $DOC_ID"
fi
