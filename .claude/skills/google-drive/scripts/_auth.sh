#!/bin/bash
# Shared authentication helper for Google API scripts
# This file is sourced by other scripts, not executed directly

# Detect environment: "cws" for Cloud Workspace, "local" for local dev
detect_environment() {
    if [[ -d "/workspace/google-cloud-sdk" && -d "/home/coder" ]]; then
        echo "cws"
    elif [[ -d "/home/coder" && -d "/workspace" ]]; then
        echo "cws"
    else
        echo "local"
    fi
}

# Export environment for use by other scripts
SKILL_ENV=$(detect_environment)

# Get the gcloud command path based on environment
get_gcloud_cmd() {
    if [[ "$SKILL_ENV" == "cws" ]]; then
        if [[ -x "/workspace/google-cloud-sdk/bin/gcloud" ]]; then
            echo "/workspace/google-cloud-sdk/bin/gcloud"
            return 0
        fi
    fi
    
    if command -v gcloud &>/dev/null; then
        echo "gcloud"
        return 0
    fi
    
    echo "ERROR: gcloud CLI not found" >&2
    echo "" >&2
    if [[ "$SKILL_ENV" == "cws" ]]; then
        echo "Expected at: /workspace/google-cloud-sdk/bin/gcloud" >&2
    else
        echo "Install gcloud CLI: https://cloud.google.com/sdk/docs/install" >&2
    fi
    return 1
}

# Get the skills directory based on environment
get_skills_dir() {
    if [[ "$SKILL_ENV" == "cws" ]]; then
        echo "/home/coder/.cursor/skills"
    else
        echo "$HOME/.cursor/skills"
    fi
}

# Get the gcloud config directory based on environment
get_gcloud_config_dir() {
    if [[ "$SKILL_ENV" == "cws" ]]; then
        echo "/home/coder/.config/gcloud"
    else
        echo "$HOME/.config/gcloud"
    fi
}

# Get an access token for Google API calls
# Returns the token on stdout, errors on stderr
# Uses Application Default Credentials (ADC) for proper scope handling
get_access_token() {
    local gcloud_cmd
    gcloud_cmd=$(get_gcloud_cmd) || return 1
    
    local token
    token=$("$gcloud_cmd" auth application-default print-access-token 2>/dev/null)
    
    if [[ -z "$token" ]]; then
        echo "Not authenticated with Google Cloud." >&2
        echo "" >&2
        echo "Run the following command to authenticate:" >&2
        echo "" >&2
        
        if [[ "$SKILL_ENV" == "cws" ]]; then
            cat >&2 <<'EOF'
  /workspace/google-cloud-sdk/bin/gcloud auth application-default login \
    --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/drive,https://www.googleapis.com/auth/documents"
EOF
        else
            cat >&2 <<'EOF'
  gcloud auth application-default login \
    --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/drive,https://www.googleapis.com/auth/documents"
EOF
        fi
        
        echo "" >&2
        echo "Default project: rsg-api-auth-dev (Google Docs and Drive APIs enabled)" >&2
        echo "For a different project, see google-cloud-setup.md" >&2
        return 1
    fi
    
    echo "$token"
}

# Check that required tools are available
check_dependencies() {
    local missing=()
    
    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi
    
    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required tools: ${missing[*]}" >&2
        if [[ "$SKILL_ENV" == "cws" ]]; then
            echo "These should be pre-installed in Cloud Workspace. Contact support if missing." >&2
        else
            echo "Install them with your package manager (brew, apt, etc.)" >&2
        fi
        return 1
    fi
    
    return 0
}

# Handle API error responses
# Usage: handle_api_error "$response" "operation description"
handle_api_error() {
    local response="$1"
    local operation="$2"
    
    local error_message
    error_message=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    
    if [[ -n "$error_message" ]]; then
        local error_code
        error_code=$(echo "$response" | jq -r '.error.code // "unknown"' 2>/dev/null)
        echo "ERROR: $operation failed (code $error_code): $error_message" >&2
        return 1
    fi
    
    return 0
}

# Get the quota project from ADC credentials
get_quota_project() {
    local config_dir
    config_dir=$(get_gcloud_config_dir)
    local adc_file="$config_dir/application_default_credentials.json"
    
    if [[ -f "$adc_file" ]]; then
        local project
        project=$(jq -r '.quota_project_id // empty' "$adc_file" 2>/dev/null)
        if [[ -n "$project" ]]; then
            echo "$project"
            return 0
        fi
    fi
    
    # Fallback to gcloud config project
    local gcloud_cmd
    gcloud_cmd=$(get_gcloud_cmd 2>/dev/null) || return 1
    "$gcloud_cmd" config get-value project 2>/dev/null
}

# Get curl headers for API calls (including auth and quota project)
# Usage: HEADERS=$(get_api_headers) && curl $HEADERS ...
get_api_headers() {
    local token
    token=$(get_access_token) || return 1
    
    local quota_project
    quota_project=$(get_quota_project)
    
    echo "-H 'Authorization: Bearer $token'"
    if [[ -n "$quota_project" ]]; then
        echo "-H 'x-goog-user-project: $quota_project'"
    fi
}

# Print environment info (useful for debugging)
print_env_info() {
    echo "Environment: $SKILL_ENV"
    echo "Skills dir: $(get_skills_dir)"
    echo "gcloud: $(get_gcloud_cmd 2>/dev/null || echo 'not found')"
    echo "gcloud config: $(get_gcloud_config_dir)"
    echo "Quota project: $(get_quota_project 2>/dev/null || echo 'not set')"
}
