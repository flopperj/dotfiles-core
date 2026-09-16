#!/bin/bash
# Set sharing permissions on a Google Drive file or shared drive
# API: https://developers.google.com/drive/api/reference/rest/v3/permissions/create
# Guide: https://developers.google.com/workspace/drive/api/guides/manage-sharing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_auth.sh"
source "$SCRIPT_DIR/_common.sh"

check_dependencies || exit 1

FILE_ID=""
SHARE_TYPE=""
SHARE_EMAIL=""
SHARE_DOMAIN=""
SHARE_ROLE="reader"
ALLOW_FILE_DISCOVERY=""
EXPIRATION_TIME=""

print_usage() {
    cat <<'EOF'
Set sharing permissions on a Google Drive file or shared drive

Usage: share_file.sh FILE_ID [OPTIONS]

Arguments:
  FILE_ID               Google Drive file ID or URL

Options:
      --anyone           Share with anyone who has the link (type: anyone, role: reader)
      --email ADDRESS    Share with user (type: user)
      --group ADDRESS    Share with Google Group (type: group)
      --domain DOMAIN    Share with domain (type: domain)
      --role ROLE        Role: reader, commenter, writer (default: reader)
      --allow-discovery  For anyone/domain: allow file discovery via search
      --expires TIME     Expiration time RFC 3339 (user/group only, max 1 year)
  -h, --help             Show this help

Examples:
  share_file.sh FILE_ID --anyone
  share_file.sh FILE_ID --email user@example.com --role writer
  share_file.sh FILE_ID --group team@example.com --role commenter
  share_file.sh FILE_ID --domain example.com --role reader

For embedding images in Google Docs, use --anyone to get webContentLink.
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
        --anyone) SHARE_TYPE="anyone"; shift ;;
        --email) SHARE_TYPE="user"; SHARE_EMAIL="$2"; shift 2 ;;
        --group) SHARE_TYPE="group"; SHARE_EMAIL="$2"; shift 2 ;;
        --domain) SHARE_TYPE="domain"; SHARE_DOMAIN="$2"; shift 2 ;;
        --role) SHARE_ROLE="$2"; shift 2 ;;
        --allow-discovery) ALLOW_FILE_DISCOVERY="true"; shift ;;
        --expires) EXPIRATION_TIME="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

if [[ -z "$SHARE_TYPE" ]]; then
    echo "ERROR: Must specify --anyone, --email, --group, or --domain" >&2
    print_usage >&2
    exit 1
fi

case "$SHARE_ROLE" in
    reader|commenter|writer) ;;
    *)
        echo "ERROR: Invalid role. Use reader, commenter, or writer" >&2
        exit 1
        ;;
esac

if [[ "$SHARE_TYPE" == "user" || "$SHARE_TYPE" == "group" ]]; then
    if [[ -z "$SHARE_EMAIL" ]]; then
        echo "ERROR: --email or --group requires an address" >&2
        exit 1
    fi
fi

if [[ "$SHARE_TYPE" == "domain" ]]; then
    if [[ -z "$SHARE_DOMAIN" ]]; then
        echo "ERROR: --domain requires a domain name" >&2
        exit 1
    fi
fi

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

# Build Permission resource per https://developers.google.com/drive/api/reference/rest/v3/permissions#Permission
case "$SHARE_TYPE" in
    anyone)
        if [[ -n "$ALLOW_FILE_DISCOVERY" ]]; then
            BODY=$(jq -n -c --arg role "$SHARE_ROLE" '{type: "anyone", role: $role, allowFileDiscovery: true}')
        else
            BODY=$(jq -n -c --arg role "$SHARE_ROLE" '{type: "anyone", role: $role}')
        fi
        ;;
    user|group)
        BODY=$(jq -n -c --arg type "$SHARE_TYPE" --arg email "$SHARE_EMAIL" --arg role "$SHARE_ROLE" '{
            type: $type,
            role: $role,
            emailAddress: $email
        }')
        if [[ -n "$EXPIRATION_TIME" ]]; then
            BODY=$(echo "$BODY" | jq --arg exp "$EXPIRATION_TIME" '. + {expirationTime: $exp}')
        fi
        ;;
    domain)
        BODY=$(jq -n -c --arg domain "$SHARE_DOMAIN" --arg role "$SHARE_ROLE" '{
            type: "domain",
            role: $role,
            domain: $domain
        }')
        if [[ -n "$ALLOW_FILE_DISCOVERY" ]]; then
            BODY=$(echo "$BODY" | jq '. + {allowFileDiscovery: true}')
        fi
        ;;
esac

# permissions.create: POST files/{fileId}/permissions
# Query params: sendNotificationEmail=false (scripted use), supportsAllDrives=true (shared drives)
RESPONSE=$(curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "$DRIVE_API/files/$FILE_ID/permissions?sendNotificationEmail=false&supportsAllDrives=true&fields=id,type,role")

if ! handle_api_error "$RESPONSE" "Create permission"; then
    # Check for corporate policy restriction on public sharing
    if echo "$RESPONSE" | grep -q "does not have sufficient permissions" && [[ "$SHARE_TYPE" == "anyone" ]]; then
        echo "" >&2
        echo "HINT: Your organization's Google Workspace policy may restrict public link sharing." >&2
        echo "Workarounds:" >&2
        echo "  - Share with specific users: --email user@example.com" >&2
        echo "  - Share with your domain: --domain yourdomain.com" >&2
        echo "  - For Docs images: include Drive view links instead of embedding" >&2
        echo "  - Manual insertion: Insert > Image > Drive in Google Docs UI" >&2
    fi
    exit 1
fi

# Fetch file to get webContentLink (needed for Docs API image insertion)
META_RESPONSE=$(curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $QUOTA_PROJECT" \
    "$DRIVE_API/files/$FILE_ID?fields=webContentLink,webViewLink&supportsAllDrives=true")

if ! handle_api_error "$META_RESPONSE" "Get file info"; then
    exit 1
fi

PERM_ID=$(echo "$RESPONSE" | jq -r '.id')
WEB_CONTENT=$(echo "$META_RESPONSE" | jq -r '.webContentLink // empty')
WEB_VIEW=$(echo "$META_RESPONSE" | jq -r '.webViewLink // empty')

echo "Permission created: id=$PERM_ID type=$(echo "$RESPONSE" | jq -r '.type') role=$(echo "$RESPONSE" | jq -r '.role')"
echo "webViewLink: $WEB_VIEW"
if [[ -n "$WEB_CONTENT" ]]; then
    echo "webContentLink: $WEB_CONTENT"
fi
