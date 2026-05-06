#!/usr/bin/env bash
# lib-mcp-config.sh — MCP config file generation.
# Sourced by install.sh; _resolve_jenkins_mcp and _apply_jenkins_mcp are in lib-jenkins-mcp.sh.

# Generate or update ~/.claude/settings.json from the template.
# On fresh install: copies template. On existing install: no-op (user manages settings).
_generate_settings_json() {
    local template="$1/.claude/settings.json.template"
    local target="$HOME/.claude/settings.json"

    [ -f "$template" ] || return 0

    if [ ! -f "$target" ]; then
        echo "  Generating ~/.claude/settings.json from template..."
        cp "$template" "$target"
        echo "  Created ~/.claude/settings.json"
    fi
}

# Generate or update ~/.cursor/mcp.json from the template.
# Same logic as settings.json: resolve jenkins-mcp from env vars.
_generate_cursor_mcp_json() {
    local template="$1/.cursor/mcp.json.template"
    local target="$HOME/.cursor/mcp.json"

    [ -f "$template" ] || return 0
    command -v jq &>/dev/null || {
        echo "  Skipping cursor mcp.json generation (jq not installed)"
        return 0
    }

    _resolve_jenkins_mcp
    mkdir -p "$HOME/.cursor"

    if [ ! -f "$target" ] || [ -L "$target" ]; then
        # Remove stale symlink if converting from symlinked to generated
        [ -L "$target" ] && rm "$target"

        echo "  Generating ~/.cursor/mcp.json from template..."
        cp "$template" "$target"

        if [ "$_JENKINS_AVAILABLE" = true ]; then
            _apply_jenkins_mcp "$target" "set"
            echo "  Configured jenkins-mcp in cursor mcp.json"
        else
            _apply_jenkins_mcp "$target" "remove"
            echo "  Removed jenkins-mcp placeholder from cursor mcp.json"
        fi

        echo "  Created ~/.cursor/mcp.json"
    else
        if [ "$_JENKINS_AVAILABLE" = true ]; then
            if ! jq -e '.mcpServers["jenkins-mcp"]' "$target" &>/dev/null; then
                _apply_jenkins_mcp "$target" "set"
                echo "  Added jenkins-mcp to existing cursor mcp.json"
            else
                local current_user current_token
                current_user="$(jq -r '.mcpServers["jenkins-mcp"].env.JENKINS_USER // ""' "$target")"
                current_token="$(jq -r '.mcpServers["jenkins-mcp"].env.JENKINS_TOKEN // ""' "$target")"
                if [ "$current_user" != "$JENKINS_USER" ] || [ "$current_token" != "$JENKINS_TOKEN" ]; then
                    _apply_jenkins_mcp "$target" "set"
                    echo "  Updated jenkins-mcp credentials in cursor mcp.json"
                fi
            fi
        fi
    fi
}
