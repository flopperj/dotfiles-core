#!/bin/bash
# Insert an image into a Google Doc from a publicly accessible URL
# Usage: insert_image.sh DOC_ID IMAGE_URL [--index N] [--width W] [--height H]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVE_SCRIPTS="$(dirname "$SCRIPT_DIR")/../google-drive/scripts"
source "$DRIVE_SCRIPTS/_auth.sh"
source "$DRIVE_SCRIPTS/_common.sh"

check_dependencies || exit 1

DOC_ID=""
IMAGE_URL=""
INSERT_INDEX=""
WIDTH=""
HEIGHT=""

print_usage() {
    cat <<'EOF'
Insert an image into a Google Doc

Usage: insert_image.sh DOC_ID IMAGE_URL [OPTIONS]

Arguments:
  DOC_ID                Google Doc ID or URL
  IMAGE_URL              Publicly accessible image URL (e.g. webContentLink from Drive)

Options:
      --index N          Insert at specific index (default: end of document)
      --width W          Image width in points (72pt = 1 inch)
      --height H         Image height in points (optional, preserves aspect ratio if only width)
  -h, --help             Show this help

Examples:
  insert_image.sh DOC_ID "https://..."                    # Insert at end
  insert_image.sh DOC_ID "https://..." --index 1         # Insert at start
  insert_image.sh DOC_ID "https://..." --width 400       # Specify width

The image must be publicly accessible. For Drive files, use share_file.sh --anyone first.

IMPORTANT: Corporate Google Workspace policies may block public sharing (--anyone).
If share_file.sh fails with error 403, use workarounds:
  - Include Drive view links in the doc instead of embedding
  - Manual insertion: Insert > Image > Drive in Google Docs UI
  - Host images on external public storage (GitHub, S3, etc.)

See: https://developers.google.com/workspace/docs/api/how-tos/images
EOF
}

if [[ $# -lt 2 ]]; then
    print_usage
    exit 1
fi

DOC_ID=$(extract_file_id "$1") || exit 1
shift
IMAGE_URL="$1"
shift

if [[ ! "$IMAGE_URL" =~ ^https?:// ]]; then
    echo "ERROR: IMAGE_URL must be a valid http or https URL" >&2
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --index) INSERT_INDEX="$2"; shift 2 ;;
        --width) WIDTH="$2"; shift 2 ;;
        --height) HEIGHT="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

if [[ -z "$INSERT_INDEX" ]]; then
    DOC_RESPONSE=$(curl -sS \
        -H "Authorization: Bearer $TOKEN" \
        -H "x-goog-user-project: $QUOTA_PROJECT" \
        "$DOCS_API/documents/$DOC_ID?fields=body.content")

    if ! handle_api_error "$DOC_RESPONSE" "Get document"; then
        exit 1
    fi

    END_INDEX=$(echo "$DOC_RESPONSE" | jq '[.body.content[].endIndex] | max')
    INSERT_INDEX=$((END_INDEX - 1))
fi

OBJECT_SIZE_JSON=""
if [[ -n "$WIDTH" && -n "$HEIGHT" ]]; then
    OBJECT_SIZE_JSON=$(jq -n -c --argjson w "$WIDTH" --argjson h "$HEIGHT" '{
        width: { magnitude: $w, unit: "PT" },
        height: { magnitude: $h, unit: "PT" }
    }')
elif [[ -n "$WIDTH" ]]; then
    OBJECT_SIZE_JSON=$(jq -n -c --argjson w "$WIDTH" '{width: { magnitude: $w, unit: "PT" }}')
elif [[ -n "$HEIGHT" ]]; then
    OBJECT_SIZE_JSON=$(jq -n -c --argjson h "$HEIGHT" '{height: { magnitude: $h, unit: "PT" }}')
fi

# InsertInlineImageRequest: https://developers.google.com/workspace/docs/api/how-tos/images
if [[ -n "$OBJECT_SIZE_JSON" ]]; then
    REQUEST=$(jq -n -c --arg uri "$IMAGE_URL" --argjson index "$INSERT_INDEX" --argjson size "$OBJECT_SIZE_JSON" '{
        requests: [{
            insertInlineImage: {
                uri: $uri,
                location: { index: $index },
                objectSize: $size
            }
        }]
    }')
else
    REQUEST=$(jq -n -c --arg uri "$IMAGE_URL" --argjson index "$INSERT_INDEX" '{
        requests: [{
            insertInlineImage: {
                uri: $uri,
                location: { index: $index }
            }
        }]
    }')
fi

RESPONSE=$(curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    -H "Content-Type: application/json" \
    -d "$REQUEST" \
    "$DOCS_API/documents/$DOC_ID:batchUpdate")

if ! handle_api_error "$RESPONSE" "Insert image"; then
    if echo "$RESPONSE" | grep -q "Internal error"; then
        echo "" >&2
        echo "HINT: Image insertion failed. Common causes:" >&2
        echo "  - Image URL is not publicly accessible" >&2
        echo "  - For Drive images: share_file.sh --anyone may have failed due to corporate policy" >&2
        echo "" >&2
        echo "Workarounds:" >&2
        echo "  - Include Drive view links in doc instead of embedding" >&2
        echo "  - Manual insertion: Insert > Image > Drive in Google Docs UI" >&2
        echo "  - Host images externally (GitHub, S3) with public access" >&2
    fi
    exit 1
fi

echo "Image inserted successfully into document: $DOC_ID"
echo "URL: https://docs.google.com/document/d/$DOC_ID/edit"
