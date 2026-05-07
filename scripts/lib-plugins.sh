#!/usr/bin/env bash
# lib-plugins.sh — install Claude Code CLI and plugins from a plugins.txt manifest.
# Sourced by core's install.sh and overlay's install-overlay.sh.
# Idempotent: safe to call multiple times; `claude plugin install` no-ops on
# already-installed plugins.

# _install_cli_and_plugins <dir>
#   <dir> is a directory containing either ./plugins.txt (core convention)
#   or ./.claude/plugins.txt (overlay convention). The first one found wins.
#
#   Behavior:
#   - If claude CLI is missing, attempts auto-install via curl.
#   - If auto-install fails, emits a WARNING and returns 0 (does not abort caller).
#   - If plugins.txt is absent in both locations, skips silently.
_install_cli_and_plugins() {
    local base_dir="$1"
    local plugins_file=""
    if [ -f "$base_dir/plugins.txt" ]; then
        plugins_file="$base_dir/plugins.txt"
    elif [ -f "$base_dir/.claude/plugins.txt" ]; then
        plugins_file="$base_dir/.claude/plugins.txt"
    fi

    if ! command -v claude &>/dev/null; then
        if [ -n "$plugins_file" ]; then
            echo "  Claude CLI not found. Installing..."
            if curl -fsSL https://claude.ai/install.sh | bash; then
                :
            else
                echo "  WARNING: Claude CLI auto-install failed. Skipping plugin install." >&2
                echo "  Install manually: https://claude.ai/install" >&2
                return 0
            fi
        fi
    fi

    if command -v claude &>/dev/null && [ -n "$plugins_file" ]; then
        while IFS= read -r plugin || [ -n "$plugin" ]; do
            [[ -z "$plugin" || "$plugin" == \#* ]] && continue
            echo "  Installing Claude plugin: $plugin"
            claude plugin install "$plugin" --scope user 2>&1 | sed 's/^/    /' || \
                echo "  WARNING: Failed to install plugin: $plugin"
        done < "$plugins_file"
    else
        echo "  Skipping Claude plugins (claude CLI not found or plugins.txt missing)"
    fi
}
