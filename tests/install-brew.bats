#!/usr/bin/env bats
# Tests for scripts/lib-brew.sh: installing the Homebrew formulae in brew.txt.
#
# Mock strategy: `brew` crosses a process boundary and a real install takes
# minutes and changes the machine, so a stub on PATH records its calls.
# `brew list --versions <f>` succeeds only for formulae named in
# $SCRATCH/installed; `brew install <f>` fails for formulae in $SCRATCH/broken.

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    mkdir -p "$SCRATCH/bin" "$SCRATCH/core"
    touch "$SCRATCH/installed" "$SCRATCH/broken"
    unset DOTFILES_SKIP_BREW
    # shellcheck source=../scripts/lib-brew.sh
    source "$CORE_DIR/scripts/lib-brew.sh"
}

teardown() {
    rm -rf "$SCRATCH"
}

_plant_brew_stub() {
    cat > "$SCRATCH/bin/brew" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$SCRATCH/brew-calls.log"
case "$1" in
    list) grep -qx "$3" "$SCRATCH/installed" ;;
    install) ! grep -qx "$2" "$SCRATCH/broken" ;;
esac
STUB
    chmod +x "$SCRATCH/bin/brew"
}

_manifest() { printf '%s\n' "$@" > "$SCRATCH/core/brew.txt"; }

@test "core brew.txt lists ffmpeg for record-demo" {
    grep -qE '^ffmpeg[[:space:]]+# record-demo' "$CORE_DIR/brew.txt"
}

@test "install.sh sources lib-brew.sh, runs it, and offers --skip-brew" {
    grep -qF 'source "$SCRIPTS_DIR/lib-brew.sh"' "$CORE_DIR/install.sh"
    grep -qx '_install_brew_formulae "$CORE_DIR"' "$CORE_DIR/install.sh"
    grep -qF -- '--skip-brew' "$CORE_DIR/install.sh"
}

@test "installs only the missing formulae, ignoring comments and blank lines" {
    _plant_brew_stub
    _manifest "# header" "" "ffmpeg  # record-demo" "jq" "  # indented comment"
    echo jq > "$SCRATCH/installed"
    PATH="$SCRATCH/bin:$PATH" run _install_brew_formulae "$SCRATCH/core"
    [ "$status" -eq 0 ]
    grep -qx "install ffmpeg" "$SCRATCH/brew-calls.log"
    ! grep -q "install jq" "$SCRATCH/brew-calls.log"
    [[ "$output" == *"already installed: jq"* ]]
}

@test "a failed install warns and does not abort" {
    _plant_brew_stub
    _manifest "ffmpeg" "jq"
    echo ffmpeg > "$SCRATCH/broken"
    PATH="$SCRATCH/bin:$PATH" run _install_brew_formulae "$SCRATCH/core"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: Failed to install Homebrew formula: ffmpeg"* ]]
    grep -qx "install jq" "$SCRATCH/brew-calls.log"
}

@test "without brew it names the formulae to install and returns 0" {
    _manifest "ffmpeg"
    PATH="/usr/bin:/bin" run _install_brew_formulae "$SCRATCH/core"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Homebrew not found"*"ffmpeg"* ]]
}

@test "DOTFILES_SKIP_BREW=1 skips before touching brew" {
    _plant_brew_stub
    _manifest "ffmpeg"
    DOTFILES_SKIP_BREW=1 PATH="$SCRATCH/bin:$PATH" run _install_brew_formulae "$SCRATCH/core"
    [ "$status" -eq 0 ]
    [ ! -f "$SCRATCH/brew-calls.log" ]
}

@test "falls back to an overlay's .claude/brew.txt" {
    _plant_brew_stub
    mkdir -p "$SCRATCH/ov/.claude"
    echo "ffmpeg" > "$SCRATCH/ov/.claude/brew.txt"
    PATH="$SCRATCH/bin:$PATH" run _install_brew_formulae "$SCRATCH/ov"
    [ "$status" -eq 0 ]
    grep -qx "install ffmpeg" "$SCRATCH/brew-calls.log"
}
