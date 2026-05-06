#!/usr/bin/env bash
# lib-jenkins-mcp.sh — Jenkins MCP resolution and Claude Code MCP registration.
# Sourced by install.sh.

# Resolve Jenkins MCP dependencies from the environment.
# Sets global variables: _JENKINS_UV_PATH, _JENKINS_DIR, _JENKINS_AVAILABLE
_resolve_jenkins_mcp() {
    _JENKINS_UV_PATH="$(command -v uv 2>/dev/null || true)"
    _JENKINS_DIR=""
    _JENKINS_AVAILABLE=false

    for candidate in "$HOME/Development/jenkins-mcp" "$HOME/dev/jenkins-mcp" "$HOME/src/jenkins-mcp"; do
        if [ -f "$candidate/server.py" ]; then
            _JENKINS_DIR="$candidate"
            break
        fi
    done

    if [ -n "$_JENKINS_UV_PATH" ] && [ -n "$_JENKINS_DIR" ] && \
       [ -n "${JENKINS_USER:-}" ] && [ -n "${JENKINS_TOKEN:-}" ]; then
        _JENKINS_AVAILABLE=true
    fi
}

# Apply jenkins-mcp config to a JSON file using jq.
# Usage: _apply_jenkins_mcp <target_json> <action>
#   action: "set"    — write/overwrite the jenkins-mcp entry
#           "remove" — delete the placeholder entry
_apply_jenkins_mcp() {
    local target="$1" action="$2"
    local tmp
    tmp="$(mktemp)"

    if [ "$action" = "remove" ]; then
        jq 'del(.mcpServers["jenkins-mcp"])' "$target" > "$tmp" && mv "$tmp" "$target"
    else
        jq --arg uv "$_JENKINS_UV_PATH" \
           --arg dir "$_JENKINS_DIR" \
           --arg user "$JENKINS_USER" \
           --arg token "$JENKINS_TOKEN" \
           '.mcpServers["jenkins-mcp"] = {
              "command": $uv,
              "args": ["run", "--directory", $dir, "python", "server.py"],
              "env": {"JENKINS_USER": $user, "JENKINS_TOKEN": $token}
            }' "$target" > "$tmp" && mv "$tmp" "$target"
    fi
}

# Register MCP servers in Claude Code via `claude mcp add` (stored in ~/.claude.json).
# Claude Code ignores mcpServers in settings.json — this is the only way to register them.
_register_claude_mcp_servers() {
    command -v claude &>/dev/null || return 0
    _resolve_jenkins_mcp

    if [ "$_JENKINS_AVAILABLE" = true ]; then
        local current
        current="$(claude mcp get jenkins-mcp 2>/dev/null || true)"
        if echo "$current" | grep -q "Status:"; then
            # Already registered — check if creds or path need updating
            local needs_update=false
            echo "$current" | grep -q "$JENKINS_USER" || needs_update=true
            echo "$current" | grep -q "$_JENKINS_DIR" || needs_update=true
            if [ "$needs_update" = true ]; then
                claude mcp remove jenkins-mcp -s user 2>/dev/null || true
                claude mcp add jenkins-mcp -s user \
                    -e JENKINS_USER="$JENKINS_USER" \
                    -e JENKINS_TOKEN="$JENKINS_TOKEN" \
                    -- "$_JENKINS_UV_PATH" run --directory "$_JENKINS_DIR" python server.py 2>/dev/null
                echo "  Updated jenkins-mcp in Claude Code (credentials or path changed)"
            fi
        else
            # Not registered — add it
            claude mcp add jenkins-mcp -s user \
                -e JENKINS_USER="$JENKINS_USER" \
                -e JENKINS_TOKEN="$JENKINS_TOKEN" \
                -- "$_JENKINS_UV_PATH" run --directory "$_JENKINS_DIR" python server.py 2>/dev/null
            echo "  Registered jenkins-mcp in Claude Code (claude mcp add)"
        fi
    fi

    # figma-desktop — local Figma MCP bridge (HTTP transport, not stdio)
    local figma_current
    figma_current="$(claude mcp get figma-desktop 2>/dev/null || true)"
    if ! echo "$figma_current" | grep -q "Status:"; then
        claude mcp add --transport http figma-desktop http://127.0.0.1:3845/mcp -s user 2>/dev/null && \
            echo "  Registered figma-desktop in Claude Code (claude mcp add --transport http)"
    fi

    # gitnexus — codebase knowledge graph MCP server (stdio, npx-based)
    local gitnexus_current
    gitnexus_current="$(claude mcp get gitnexus 2>/dev/null || true)"
    if ! echo "$gitnexus_current" | grep -q "Status:"; then
        claude mcp add gitnexus -s user -- npx -y gitnexus@latest mcp 2>/dev/null && \
            echo "  Registered gitnexus in Claude Code (claude mcp add)"
    fi
}
