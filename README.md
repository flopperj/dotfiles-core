# dotfiles-core

Universal Claude Code agent pipeline framework.

## What this is

`dotfiles-core` is the universal core of a modular Claude Code framework. It provides:

- A complete agent pipeline: Aristotle (deconstruction) → Optimus (planning) → Cyrus (TDD implementation) → Scout/Ranger (review)
- Workflow orchestration skills: `/forge`, `/grill-me`, `/to-prd`, and more
- Shared role-guards, responsibility-boundaries, and agent memory seeds
- A standalone installer that wires everything into `~/.claude/`

## Quickstart

```bash
git clone <dotfiles-core-url>
cd dotfiles-core
./install.sh
```

After install, restart Claude Code. The full agent pipeline is available.

## Three-repo architecture

```
dotfiles-core   (this repo — universal, public, MIT)
     ↑ submodule
dotfiles        (company overlay — internal GHE only)
dotfiles-personal  (personal overlay — optional, Phase 4+)
```

Overlays consume `dotfiles-core` as a git submodule pinned to a specific SHA.
Universal improvements land in core; overlays adopt them via explicit pointer-bump commits.

## Fork and customize

Clone this repo. Run `install.sh`. Customize `~/.claude/CLAUDE.md` and `~/.claude/AGENTS.md`
to add overlay-specific routing, emoji codes, or skill extensions. Phase 2 ships `lib-overlays.sh`
for structured overlay fragment registration.

## License

MIT — see [LICENSE](LICENSE).
