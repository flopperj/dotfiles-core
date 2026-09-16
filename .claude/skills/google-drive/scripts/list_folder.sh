#!/bin/bash
# List contents of a Google Drive folder
# Usage: list_folder.sh [FOLDER_ID] [--recursive] [--tree] [--max N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_auth.sh"
source "$SCRIPT_DIR/_common.sh"

check_dependencies || exit 1

FOLDER_ID=""
RECURSIVE=false
TREE_VIEW=false
MAX_RESULTS=50
OUTPUT_FORMAT="table"

print_usage() {
    cat <<'EOF'
List contents of a Google Drive folder

Usage: list_folder.sh [FOLDER_ID] [OPTIONS]

Arguments:
  FOLDER_ID             Folder ID or URL (default: root/My Drive)

Options:
  -r, --recursive       List contents recursively
  -t, --tree            Show tree view (implies --recursive)
  -m, --max N           Maximum results per folder (default: 50)
      --format FORMAT   Output format: table, json, ids (default: table)
  -h, --help            Show this help

Examples:
  list_folder.sh                       # List My Drive root
  list_folder.sh FOLDER_ID             # List specific folder
  list_folder.sh FOLDER_ID --tree      # Tree view
  list_folder.sh FOLDER_ID -r          # Recursive list
EOF
}

# Check if first argument is a folder ID or flag
if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
    FOLDER_ID=$(extract_file_id "$1") || exit 1
    shift
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--recursive) RECURSIVE=true; shift ;;
        -t|--tree) TREE_VIEW=true; RECURSIVE=true; shift ;;
        -m|--max) MAX_RESULTS="$2"; shift 2 ;;
        --format) OUTPUT_FORMAT="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
    esac
done

TOKEN=$(get_access_token) || exit 1
QUOTA_PROJECT=$(get_quota_project)

# Use 'root' for My Drive if no folder specified
if [[ -z "$FOLDER_ID" ]]; then
    FOLDER_ID="root"
fi

# Function to list a single folder
list_single_folder() {
    local folder_id="$1"
    local indent="${2:-0}"
    
    local q="'$folder_id' in parents and trashed = false"
    local encoded_q
    encoded_q=$(url_encode "$q")
    
    local url="$DRIVE_API/files?pageSize=$MAX_RESULTS&orderBy=folder,name"
    url+="&fields=files(id,name,mimeType,modifiedTime,size)"
    url+="&q=$encoded_q"
    
    local response
    response=$(curl -sS \
        -H "Authorization: Bearer $TOKEN" \
        -H "x-goog-user-project: $QUOTA_PROJECT" \
        "$url")
    
    if ! handle_api_error "$response" "List folder"; then
        return 1
    fi
    
    echo "$response"
}

# Print folder contents with tree view
print_tree() {
    local folder_id="$1"
    local prefix="${2:-}"
    
    local response
    response=$(list_single_folder "$folder_id") || return 1
    
    local items
    items=$(echo "$response" | jq -r '.files | length')
    
    local i=0
    echo "$response" | jq -c '.files[]' | while read -r item; do
        i=$((i + 1))
        local name
        name=$(echo "$item" | jq -r '.name')
        local mime
        mime=$(echo "$item" | jq -r '.mimeType')
        local id
        id=$(echo "$item" | jq -r '.id')
        
        local connector="├── "
        local next_prefix="${prefix}│   "
        
        # Check if last item
        if [[ $i -eq $items ]]; then
            connector="└── "
            next_prefix="${prefix}    "
        fi
        
        # Add folder/file icon
        local icon="📄"
        if [[ "$mime" == "application/vnd.google-apps.folder" ]]; then
            icon="📁"
        elif [[ "$mime" == "application/vnd.google-apps.document" ]]; then
            icon="📝"
        elif [[ "$mime" == "application/vnd.google-apps.spreadsheet" ]]; then
            icon="📊"
        elif [[ "$mime" == "application/vnd.google-apps.presentation" ]]; then
            icon="📽️"
        fi
        
        echo "${prefix}${connector}${icon} ${name}"
        
        # Recurse into folders
        if [[ "$mime" == "application/vnd.google-apps.folder" ]]; then
            print_tree "$id" "$next_prefix"
        fi
    done
}

# Print flat list (with optional recursion)
print_flat() {
    local folder_id="$1"
    local indent="${2:-0}"
    
    local response
    response=$(list_single_folder "$folder_id") || return 1
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        if [[ "$indent" -eq 0 ]]; then
            echo "$response" | jq '.files'
        else
            echo "$response" | jq '.files[]'
        fi
        return
    fi
    
    if [[ "$OUTPUT_FORMAT" == "ids" ]]; then
        echo "$response" | jq -r '.files[].id'
        return
    fi
    
    # Table format
    echo "$response" | jq -r '.files[] | [.name, .mimeType, .modifiedTime, .id] | @tsv' | \
    while IFS=$'\t' read -r name mime modified id; do
        print_file_row "$name" "$mime" "$modified" "$id" "$indent"
        
        # Recurse into folders
        if [[ "$RECURSIVE" == "true" && "$mime" == "application/vnd.google-apps.folder" ]]; then
            print_flat "$id" $((indent + 1))
        fi
    done
}

# Main output
if [[ "$TREE_VIEW" == "true" ]]; then
    # Get folder name for root
    if [[ "$FOLDER_ID" == "root" ]]; then
        echo "📁 My Drive"
    else
        FOLDER_INFO=$(curl -sS \
            -H "Authorization: Bearer $TOKEN" \
            -H "x-goog-user-project: $QUOTA_PROJECT" \
            "$DRIVE_API/files/$FOLDER_ID?fields=name")
        FOLDER_NAME=$(echo "$FOLDER_INFO" | jq -r '.name')
        echo "📁 $FOLDER_NAME"
    fi
    print_tree "$FOLDER_ID"
else
    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        print_table_header
    fi
    print_flat "$FOLDER_ID"
fi
