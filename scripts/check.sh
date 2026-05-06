#!/usr/bin/env bash
# check.sh — install.sh --check mode: report symlink health without modifying anything.
# Sourced by install.sh; run_check() is called with DOTFILES_DIR as argument.

# Run dotfiles health check.
# Usage: run_check <dotfiles_dir>
# Returns: 0 if all checks pass, 1 if any errors found.
run_check() {
    local df_dir="$1"
    echo "Dotfiles health check ($df_dir)"
    errors=0

    _check_link() {
        local target="$1" label="$3"
        if [ -L "$target" ]; then
            if [ ! -e "$target" ]; then
                echo "  BROKEN: $label -> $(readlink "$target")"
                errors=$((errors + 1))
            else
                echo "  OK:     $label"
            fi
        elif [ -e "$target" ]; then
            echo "  WARN:   $label exists but is not a symlink"
        else
            echo "  MISSING: $label"
            errors=$((errors + 1))
        fi
    }

    echo ""
    echo "Core files:"
    _check_link "$HOME/.aliases.local" "$df_dir" "~/.aliases.local"
    _check_link "$HOME/.claude/CLAUDE.md" "$df_dir" "~/.claude/CLAUDE.md"
    if [ -f "$df_dir/.claude/AGENTS.md" ]; then
        _check_link "$HOME/.claude/AGENTS.md" "$df_dir" "~/.claude/AGENTS.md"
    fi
    _check_link "$HOME/.claude/policies.yaml" "$df_dir" "~/.claude/policies.yaml"

    echo ""
    echo "Agents:"
    for f in "$df_dir"/.claude/agents/*.md; do
        [ -f "$f" ] || continue
        _check_link "$HOME/.claude/agents/$(basename "$f")" "$df_dir" "~/.claude/agents/$(basename "$f")"
    done

    echo ""
    echo "Skills:"
    for d in "$df_dir"/.claude/skills/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        # Repo-local-only skills are not symlinked into ~/.claude/skills (see lib-symlinks.sh).
        [ "$name" = "self-evaluate" ] && continue
        _check_link "$HOME/.claude/skills/$name" "$df_dir" "~/.claude/skills/$name"
    done

    echo ""
    echo "Project templates:"
    _check_link "$HOME/.claude/project-templates" "$df_dir" "~/.claude/project-templates"

    echo ""
    echo "Cursor Agents:"
    for f in "$df_dir"/.claude/agents/*.md; do
        [ -f "$f" ] || continue
        _check_link "$HOME/.cursor/agents/$(basename "$f")" "$df_dir" "~/.cursor/agents/$(basename "$f")"
    done

    echo ""
    echo "Cursor Skills:"
    for d in "$df_dir"/.claude/skills/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        [ "$name" = "self-evaluate" ] && continue
        _check_link "$HOME/.cursor/skills/$name" "$df_dir" "~/.cursor/skills/$name"
    done

    if [ -d "$df_dir/.cursor/rules" ]; then
        echo ""
        echo "Cursor Rules:"
        for f in "$df_dir"/.cursor/rules/*.mdc; do
            [ -f "$f" ] || continue
            _check_link "$HOME/.cursor/rules/$(basename "$f")" "$df_dir" "~/.cursor/rules/$(basename "$f")"
        done
    fi

    echo ""
    echo "Cursor Config:"
    _check_link "$HOME/.cursor/hooks.json" "$df_dir" "~/.cursor/hooks.json"
    if [ -f "$df_dir/.cursor/mcp.json.template" ]; then
        if [ -f "$HOME/.cursor/mcp.json" ] && [ ! -L "$HOME/.cursor/mcp.json" ]; then
            echo "  OK:     ~/.cursor/mcp.json (generated from template)"
        elif [ -L "$HOME/.cursor/mcp.json" ]; then
            echo "  WARN:   ~/.cursor/mcp.json is symlinked (should be generated). Re-run install.sh"
        else
            echo "  MISSING: ~/.cursor/mcp.json"
            errors=$((errors + 1))
        fi
    fi
    for f in "$df_dir"/.cursor/hooks/*; do
        [ -f "$f" ] || continue
        _check_link "$HOME/.cursor/hooks/$(basename "$f")" "$df_dir" "~/.cursor/hooks/$(basename "$f")"
    done

    echo ""
    echo "Stale symlinks:"
    stale=0
    for dir in "$HOME/.claude/agents" "$HOME/.claude/skills" "$HOME/.cursor/agents" "$HOME/.cursor/skills" "$HOME/.cursor/hooks" "$HOME/.cursor/rules"; do
        [ -d "$dir" ] || continue
        for link in "$dir"/*; do
            if [ -L "$link" ] && [ ! -e "$link" ]; then
                echo "  STALE: $link -> $(readlink "$link")"
                stale=$((stale + 1))
            fi
        done
    done
    [ "$stale" -eq 0 ] && echo "  None found."

    echo ""
    echo "Agent memory seeds:"
    if [ -d "$df_dir/.claude/agent-memory-seeds" ]; then
        for seed_agent_dir in "$df_dir"/.claude/agent-memory-seeds/*/; do
            [ -d "$seed_agent_dir" ] || continue
            agent_name="$(basename "$seed_agent_dir")"
            for seed_file in "$seed_agent_dir"*; do
                [ -f "$seed_file" ] || continue
                filename="$(basename "$seed_file")"
                [ "$filename" = "MEMORY.md" ] && continue
                target_file="$HOME/.claude/agent-memory/$agent_name/$filename"
                if [ ! -f "$target_file" ]; then
                    echo "  NOT SEEDED: $agent_name/$filename"
                    errors=$((errors + 1))
                else
                    echo "  OK:         $agent_name/$filename"
                fi
            done
        done
    else
        echo "  No seeds directory found."
    fi

    echo ""
    echo "CLI tools:"
    for cmd in claude gh git jq; do
        if command -v "$cmd" &>/dev/null; then
            echo "  OK:     $cmd"
        else
            echo "  MISSING: $cmd"
        fi
    done

    echo ""
    echo "Optional CLI tools:"
    if command -v mmdc &>/dev/null; then
        echo "  OK:     mmdc (mermaid-cli)"
    else
        echo "  MISSING: mmdc (mermaid-cli) — install with: npm install -g @mermaid-js/mermaid-cli"
    fi
    if command -v uv &>/dev/null; then
        echo "  OK:     uv (Python package runner)"
    else
        echo "  MISSING: uv (Python package runner) — install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    fi

    # Check Jenkins MCP registration in ~/.claude.json (Claude Code's MCP store).
    if [ -f "$HOME/.claude.json" ] && command -v jq &>/dev/null && \
       jq -e '.mcpServers["jenkins-mcp"]' "$HOME/.claude.json" &>/dev/null; then
        echo ""
        echo "Jenkins MCP (Claude Code):"

        _claude_json_env_var() {
            jq -r ".mcpServers[\"jenkins-mcp\"].env[\"$1\"] // \"\"" "$HOME/.claude.json" 2>/dev/null
        }

        ju_shell="${JENKINS_USER:-}"
        ju_claude="$(_claude_json_env_var JENKINS_USER)"
        if [ -n "$ju_shell" ]; then
            echo "  OK:     JENKINS_USER is set (shell env)"
        elif [ -n "$ju_claude" ]; then
            echo "  OK:     JENKINS_USER is set (claude.json)"
        else
            echo "  WARN:   JENKINS_USER not set — add to ~/.zshrc: export JENKINS_USER=\"your-intuit-username\""
        fi

        jt_shell="${JENKINS_TOKEN:-}"
        jt_claude="$(_claude_json_env_var JENKINS_TOKEN)"
        if [ -n "$jt_shell" ]; then
            echo "  OK:     JENKINS_TOKEN is set (shell env)"
        elif [ -n "$jt_claude" ]; then
            echo "  OK:     JENKINS_TOKEN is set (claude.json)"
        else
            echo "  WARN:   JENKINS_TOKEN not set — add to ~/.zshrc: export JENKINS_TOKEN=\"your-github-pat\""
        fi

        # Cursor parity check
        if [ -f "$HOME/.cursor/mcp.json" ] && command -v jq &>/dev/null && \
           jq -e '.mcpServers["jenkins-mcp"]' "$HOME/.cursor/mcp.json" &>/dev/null; then
            echo "  OK:     Cursor parity (jenkins-mcp in ~/.cursor/mcp.json)"
        else
            echo "  INFO:   jenkins-mcp not in ~/.cursor/mcp.json — Cursor agents won't have Jenkins access"
        fi
    elif command -v claude &>/dev/null; then
        echo ""
        echo "Jenkins MCP (Claude Code):"
        echo "  INFO:   Not registered — run install.sh or: claude mcp add jenkins-mcp -s user ..."
    fi

    echo ""
    if [ -f "$HOME/.dotfiles-last-install" ]; then
        echo "Last install: $(cat "$HOME/.dotfiles-last-install")"
    else
        echo "Last install: unknown (no marker file)"
    fi

    echo ""
    if [ "$errors" -gt 0 ]; then
        echo "Found $errors issue(s). Run install.sh to fix."
        return 1
    else
        echo "All checks passed."
        return 0
    fi
}
