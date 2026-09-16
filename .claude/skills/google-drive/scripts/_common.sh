#!/bin/bash
# Common utilities for Google Drive/Docs scripts
# This file is sourced by other scripts, not executed directly
# Note: _auth.sh must be sourced first to set SKILL_ENV

url_encode() {
    local string="$1"
    printf '%s' "$string" | jq -sRr @uri
}

# Extract file ID from a Google Drive/Docs URL or return as-is if already an ID
extract_file_id() {
    local input="$1"
    
    if [[ "$input" =~ ^https?:// ]]; then
        # Match patterns like:
        # - docs.google.com/document/d/FILE_ID/edit
        # - drive.google.com/file/d/FILE_ID/view
        # - docs.google.com/spreadsheets/d/FILE_ID/edit
        if [[ "$input" =~ /d/([a-zA-Z0-9_-]+) ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
        echo "ERROR: Could not extract file ID from URL: $input" >&2
        return 1
    fi
    
    echo "$input"
}

get_mime_type() {
    local type="$1"
    case "$type" in
        doc|document)
            echo "application/vnd.google-apps.document" ;;
        sheet|spreadsheet)
            echo "application/vnd.google-apps.spreadsheet" ;;
        slide|presentation)
            echo "application/vnd.google-apps.presentation" ;;
        folder)
            echo "application/vnd.google-apps.folder" ;;
        pdf)
            echo "application/pdf" ;;
        image)
            echo "image/" ;;
        *)
            echo "" ;;
    esac
}

get_type_name() {
    local mime="$1"
    case "$mime" in
        application/vnd.google-apps.document)
            echo "Doc" ;;
        application/vnd.google-apps.spreadsheet)
            echo "Sheet" ;;
        application/vnd.google-apps.presentation)
            echo "Slides" ;;
        application/vnd.google-apps.folder)
            echo "Folder" ;;
        application/pdf)
            echo "PDF" ;;
        *)
            echo "${mime##*/}" | cut -c1-10 ;;
    esac
}

# Format a timestamp for display (YYYY-MM-DD)
format_date() {
    local timestamp="$1"
    echo "${timestamp:0:10}"
}

truncate() {
    local string="$1"
    local max_length="${2:-50}"
    
    if [[ ${#string} -gt $max_length ]]; then
        echo "${string:0:$((max_length - 2))}.."
    else
        echo "$string"
    fi
}

print_table_header() {
    printf "%-50s %-10s %-12s %s\n" "Name" "Type" "Modified" "ID"
    printf '%100s\n' '' | tr ' ' '-'
}

print_file_row() {
    local name="$1"
    local mime="$2"
    local modified="$3"
    local id="$4"
    local indent="${5:-0}"
    
    local prefix=""
    for ((i=0; i<indent; i++)); do
        prefix+="  "
    done
    
    local display_name
    display_name=$(truncate "$prefix$name" 50)
    local type_name
    type_name=$(get_type_name "$mime")
    local date
    date=$(format_date "$modified")
    
    printf "%-50s %-10s %-12s %s\n" "$display_name" "$type_name" "$date" "$id"
}

get_drive_scripts_dir() {
    local skills_dir
    skills_dir=$(get_skills_dir)
    echo "$skills_dir/google-drive/scripts"
}

get_docs_scripts_dir() {
    local skills_dir
    skills_dir=$(get_skills_dir)
    echo "$skills_dir/google-docs/scripts"
}

# Drive API base URL (used by the scripts that source this file)
# shellcheck disable=SC2034
DRIVE_API="https://www.googleapis.com/drive/v3"

# Docs API base URL (used by the scripts that source this file)
# shellcheck disable=SC2034
DOCS_API="https://docs.googleapis.com/v1"
