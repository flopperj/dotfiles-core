#!/usr/bin/env bash
# lib-symlinks.sh — symlink management functions.
# Sourced by install.sh; DOTFILES_DIR and HOME are set by the orchestrator.

# Phase 1 migrated content — the set of skills/agents/_shared that live in
# dotfiles-core. When the submodule is populated we prefer the submodule copy;
# when it is absent (deinit'd or fresh clone without --recurse-submodules) we
# fall back to the in-tree overlay copy. This list must be updated as more
# content is migrated in Phase 2+.
_CORE_SKILLS=("forge" "grill-me" "to-prd")
_CORE_AGENTS=("aristotle-deconstructor.md" "cyrus-tdd-engineer.md" "optimus-planner.md" "ranger-reviewer.md" "scout-reviewer.md")

# Return the best available source path for a Phase 1 migrated skill directory.
# $1: df_dir (overlay repo root)
# $2: skill name (e.g. "forge")
# Prints the resolved path. Caller must check that it is a real directory.
_resolve_core_skill_path() {
    local df_dir="$1"
    local skill_name="$2"
    local submodule_path="$df_dir/.claude/dotfiles-core/.claude/skills/$skill_name"
    if [ -d "$submodule_path" ]; then
        echo "$submodule_path"
    else
        echo "$df_dir/.claude/skills/$skill_name"
    fi
}

# Return the best available source path for a Phase 1 migrated agent file.
# $1: df_dir (overlay repo root)
# $2: agent filename (e.g. "cyrus-tdd-engineer.md")
# Prints the resolved path. Caller must check that it is a real file.
_resolve_core_agent_path() {
    local df_dir="$1"
    local agent_filename="$2"
    local submodule_path="$df_dir/.claude/dotfiles-core/.claude/agents/$agent_filename"
    if [ -f "$submodule_path" ]; then
        echo "$submodule_path"
    else
        echo "$df_dir/.claude/agents/$agent_filename"
    fi
}

# Return the best available source path for the _shared directory.
# $1: df_dir (overlay repo root)
# Prints the resolved path.
_resolve_core_shared_path() {
    local df_dir="$1"
    local submodule_path="$df_dir/.claude/dotfiles-core/.claude/_shared"
    if [ -d "$submodule_path" ]; then
        echo "$submodule_path"
    else
        echo "$df_dir/.claude/_shared"
    fi
}

# Return true (0) if a skill name is in the Phase 1 migrated set.
_is_core_skill() {
    local skill_name="$1"
    local name
    for name in "${_CORE_SKILLS[@]}"; do
        [ "$name" = "$skill_name" ] && return 0
    done
    return 1
}

# Return true (0) if an agent filename is in the Phase 1 migrated set.
_is_core_agent() {
    local agent_filename="$1"
    local name
    for name in "${_CORE_AGENTS[@]}"; do
        [ "$name" = "$agent_filename" ] && return 0
    done
    return 1
}

# Remove symlinks in a target directory whose targets no longer exist.
_clean_stale_symlinks() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    for link in "$dir"/*; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            rm "$link"
            echo "  Removed stale symlink: $(basename "$link")"
        fi
    done
}

# Move a colliding non-symlink file to a timestamped .bak so prior backups
# are never overwritten by repeated runs. Tests can override the suffix
# via _BACKUP_SUFFIX_OVERRIDE to force distinct backups deterministically.
_backup_collision() {
    local path="$1"
    local suffix="${_BACKUP_SUFFIX_OVERRIDE:-$(date +%s)}"
    local backup="${path}.bak.${suffix}"
    if ! mv "$path" "$backup"; then
        echo "  ERROR: failed to back up $path to $backup" >&2
        return 1
    fi
    echo "  Backed up to $backup"
}

# Create all dotfiles symlinks in $HOME.
# Usage: install_symlinks <dotfiles_dir>
install_symlinks() {
    local df_dir="$1"

    # --- Shell aliases ---
    if [ -L "$HOME/.aliases.local" ] && [ ! -e "$HOME/.aliases.local" ]; then
        rm "$HOME/.aliases.local"
        echo "  Removed broken .aliases.local symlink"
    fi
    if [ ! -L "$HOME/.aliases.local" ] && [ ! -f "$HOME/.aliases.local" ]; then
        ln -s "$df_dir/.aliases.local" "$HOME/.aliases.local"
        echo "  Linked .aliases.local"
    elif [ -f "$HOME/.aliases.local" ] && [ ! -L "$HOME/.aliases.local" ]; then
        echo "  WARNING: ~/.aliases.local exists and is not a symlink. Skipping."
        echo "  To use dotfiles version: rm ~/.aliases.local && rerun this script."
    fi

    # --- Claude Code global instructions ---
    mkdir -p "$HOME/.claude"
    local claude_md_target="$HOME/.claude/CLAUDE.md"
    if [ -L "$claude_md_target" ]; then
        rm "$claude_md_target"
    elif [ -f "$claude_md_target" ]; then
        echo "  WARNING: ~/.claude/CLAUDE.md exists and is not a symlink. Backing up."
        _backup_collision "$claude_md_target"
    fi
    ln -s "$df_dir/.claude/CLAUDE.md" "$claude_md_target"
    echo "  Linked CLAUDE.md"

    # --- Editor-agnostic AGENTS.md ---
    if [ -f "$df_dir/.claude/AGENTS.md" ]; then
        local agents_md_target="$HOME/.claude/AGENTS.md"
        if [ -L "$agents_md_target" ]; then
            rm "$agents_md_target"
        elif [ -f "$agents_md_target" ]; then
            echo "  WARNING: ~/.claude/AGENTS.md exists and is not a symlink. Backing up."
            _backup_collision "$agents_md_target"
        fi
        ln -s "$df_dir/.claude/AGENTS.md" "$agents_md_target"
        echo "  Linked AGENTS.md"
    fi

    # --- Claude Code _shared directory ---
    # Prefer the submodule copy (Phase 1 migrated); fall back to in-tree.
    local shared_src
    shared_src="$(_resolve_core_shared_path "$df_dir")"
    if [ -d "$shared_src" ]; then
        local shared_target="$HOME/.claude/_shared"
        if [ -L "$shared_target" ]; then
            rm "$shared_target"
        elif [ -d "$shared_target" ]; then
            echo "  WARNING: ~/.claude/_shared exists and is not a symlink. Backing up."
            _backup_collision "$shared_target"
        fi
        ln -s "$shared_src" "$shared_target"
        echo "  Linked _shared"
    fi

    # --- Claude Code DoD ---
    local dod_target="$HOME/.claude/DoD.md"
    if [ -L "$dod_target" ]; then
        rm "$dod_target"
    elif [ -f "$dod_target" ]; then
        echo "  WARNING: ~/.claude/DoD.md exists and is not a symlink. Backing up."
        _backup_collision "$dod_target"
    fi
    if [ -f "$df_dir/.claude/DoD.md" ]; then
        ln -s "$df_dir/.claude/DoD.md" "$dod_target"
        echo "  Linked DoD.md"
    fi

    # --- Claude Code agents ---
    mkdir -p "$HOME/.claude/agents"
    _clean_stale_symlinks "$HOME/.claude/agents"

    for agent_file in "$df_dir"/.claude/agents/*.md; do
        [ -f "$agent_file" ] || continue
        local filename
        filename="$(basename "$agent_file")"
        # For Phase 1 migrated agents, prefer the submodule copy when available.
        local resolved_agent_file="$agent_file"
        if _is_core_agent "$filename"; then
            resolved_agent_file="$(_resolve_core_agent_path "$df_dir" "$filename")"
        fi
        local target="$HOME/.claude/agents/$filename"
        if [ -L "$target" ]; then
            rm "$target"
        elif [ -f "$target" ]; then
            echo "  WARNING: $target exists and is not a symlink. Backing up."
            _backup_collision "$target"
        fi
        ln -s "$resolved_agent_file" "$target"
        echo "  Linked agent: $filename"
    done

    # --- Claude Code skills ---
    mkdir -p "$HOME/.claude/skills"
    _clean_stale_symlinks "$HOME/.claude/skills"

    # Repo-local-only skills live under $df_dir only — never symlink to ~/.claude/skills so other
    # projects do not pick them up; remove legacy symlinks from older installs.
    if [ -L "$HOME/.claude/skills/self-evaluate" ]; then
        rm "$HOME/.claude/skills/self-evaluate"
        echo "  Removed repo-local-only skill symlink: self-evaluate"
    fi

    for skill_dir in "$df_dir"/.claude/skills/*/; do
        [ -d "$skill_dir" ] || continue
        local dirname
        dirname="$(basename "$skill_dir")"
        case "$dirname" in
            self-evaluate) continue ;;
        esac
        # For Phase 1 migrated skills, prefer the submodule copy when available.
        local resolved_skill_dir="$skill_dir"
        if _is_core_skill "$dirname"; then
            resolved_skill_dir="$(_resolve_core_skill_path "$df_dir" "$dirname")"
        fi
        local target="$HOME/.claude/skills/$dirname"
        if [ -L "$target" ]; then
            rm "$target"
        elif [ -d "$target" ]; then
            echo "  WARNING: $target exists and is not a symlink. Backing up."
            _backup_collision "$target"
        fi
        ln -s "$resolved_skill_dir" "$target"
        echo "  Linked skill: $dirname"
    done

    # --- Claude Code evals ---
    if [ -d "$df_dir/.claude/evals" ]; then
        local evals_target="$HOME/.claude/evals"
        if [ -L "$evals_target" ]; then
            rm "$evals_target"
        elif [ -d "$evals_target" ]; then
            echo "  WARNING: $evals_target exists and is not a symlink. Backing up."
            _backup_collision "$evals_target"
        fi
        ln -s "$df_dir/.claude/evals" "$evals_target"
        echo "  Linked evals"
    fi

    # --- Claude Code project templates ---
    if [ -d "$df_dir/.claude/project-templates" ]; then
        local templates_target="$HOME/.claude/project-templates"
        if [ -L "$templates_target" ]; then
            rm "$templates_target"
        elif [ -d "$templates_target" ]; then
            echo "  WARNING: $templates_target exists and is not a symlink. Backing up."
            _backup_collision "$templates_target"
        fi
        ln -s "$df_dir/.claude/project-templates" "$templates_target"
        echo "  Linked project-templates"
    fi

    # --- Claude Code policies ---
    if [ -f "$df_dir/.claude/policies.yaml" ]; then
        local policies_target="$HOME/.claude/policies.yaml"
        if [ -L "$policies_target" ]; then
            rm "$policies_target"
        elif [ -f "$policies_target" ]; then
            echo "  WARNING: $policies_target exists and is not a symlink. Backing up."
            _backup_collision "$policies_target"
        fi
        ln -s "$df_dir/.claude/policies.yaml" "$policies_target"
        echo "  Linked policies.yaml"
    fi

    # --- Cursor agents (mirror from Claude agents) ---
    mkdir -p "$HOME/.cursor/agents"
    _clean_stale_symlinks "$HOME/.cursor/agents"

    for agent_file in "$df_dir"/.claude/agents/*.md; do
        [ -f "$agent_file" ] || continue
        local filename
        filename="$(basename "$agent_file")"
        # Cursor mirrors also prefer the submodule for Phase 1 migrated agents.
        local resolved_agent_file_cursor="$agent_file"
        if _is_core_agent "$filename"; then
            resolved_agent_file_cursor="$(_resolve_core_agent_path "$df_dir" "$filename")"
        fi
        local target="$HOME/.cursor/agents/$filename"
        if [ -L "$target" ]; then
            rm "$target"
        elif [ -f "$target" ]; then
            echo "  WARNING: $target exists and is not a symlink. Backing up."
            _backup_collision "$target"
        fi
        ln -s "$resolved_agent_file_cursor" "$target"
        echo "  Linked Cursor agent: $filename"
    done

    # --- Cursor skills (mirror from Claude skills) ---
    mkdir -p "$HOME/.cursor/skills"
    _clean_stale_symlinks "$HOME/.cursor/skills"

    if [ -L "$HOME/.cursor/skills/self-evaluate" ]; then
        rm "$HOME/.cursor/skills/self-evaluate"
        echo "  Removed repo-local-only Cursor skill symlink: self-evaluate"
    fi

    for skill_dir in "$df_dir"/.claude/skills/*/; do
        [ -d "$skill_dir" ] || continue
        local dirname
        dirname="$(basename "$skill_dir")"
        case "$dirname" in
            self-evaluate) continue ;;
        esac
        # Cursor mirrors also prefer the submodule for Phase 1 migrated skills.
        local resolved_skill_dir_cursor="$skill_dir"
        if _is_core_skill "$dirname"; then
            resolved_skill_dir_cursor="$(_resolve_core_skill_path "$df_dir" "$dirname")"
        fi
        local target="$HOME/.cursor/skills/$dirname"
        if [ -L "$target" ]; then
            rm "$target"
        elif [ -d "$target" ]; then
            echo "  WARNING: $target exists and is not a symlink. Backing up."
            _backup_collision "$target"
        fi
        ln -s "$resolved_skill_dir_cursor" "$target"
        echo "  Linked Cursor skill: $dirname"
    done

    # --- Cursor rules (e.g. AGENTS.md pointer) ---
    if [ -d "$df_dir/.cursor/rules" ]; then
        mkdir -p "$HOME/.cursor/rules"
        _clean_stale_symlinks "$HOME/.cursor/rules"
        for rule_file in "$df_dir"/.cursor/rules/*.mdc; do
            [ -f "$rule_file" ] || continue
            local filename
            filename="$(basename "$rule_file")"
            local target="$HOME/.cursor/rules/$filename"
            if [ -L "$target" ]; then
                rm "$target"
            elif [ -f "$target" ]; then
                echo "  WARNING: $target exists and is not a symlink. Backing up."
                _backup_collision "$target"
            fi
            ln -s "$rule_file" "$target"
            echo "  Linked Cursor rule: $filename"
        done
    fi

    # --- Cursor hooks.json ---
    if [ -f "$df_dir/.cursor/hooks.json" ]; then
        mkdir -p "$HOME/.cursor"
        local hooks_target="$HOME/.cursor/hooks.json"
        if [ -L "$hooks_target" ]; then
            rm "$hooks_target"
        elif [ -f "$hooks_target" ]; then
            echo "  WARNING: ~/.cursor/hooks.json exists and is not a symlink. Backing up."
            _backup_collision "$hooks_target"
        fi
        ln -s "$df_dir/.cursor/hooks.json" "$hooks_target"
        echo "  Linked hooks.json"
    fi

    # --- Cursor hook scripts ---
    if [ -d "$df_dir/.cursor/hooks" ]; then
        mkdir -p "$HOME/.cursor/hooks"
        _clean_stale_symlinks "$HOME/.cursor/hooks"
        for hook_script in "$df_dir"/.cursor/hooks/*; do
            [ -f "$hook_script" ] || continue
            local filename
            filename="$(basename "$hook_script")"
            local target="$HOME/.cursor/hooks/$filename"
            if [ -L "$target" ]; then
                rm "$target"
            elif [ -f "$target" ]; then
                echo "  WARNING: $target exists and is not a symlink. Backing up."
                _backup_collision "$target"
            fi
            ln -s "$hook_script" "$target"
            chmod +x "$target"
            echo "  Linked hook script: $filename"
        done
    fi
}
