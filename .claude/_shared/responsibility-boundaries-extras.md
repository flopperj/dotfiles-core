# Extra boundary rows for per-skill tables.
# Format: <!-- key --> on one line, then the table row on the next line.
# boundaries-gen.sh reads these by key when a SKILL.md declares <!-- EXTRA_ROWS: key1,key2 -->.

<!-- ticket-swarm -->
| **Ticket Swarm** | Batch harvest, triage, domain grouping, team-lead dispatch, progress monitoring, PR gating | Write code, produce plans, perform strategic analysis, review PRs, enrich individual tickets |

<!-- ticket-pickup -->
| **Ticket Pickup** | Fetch ticket, enrich with codebase context, classify complexity, route to pipeline | Write code, produce plans, perform strategic analysis, review PRs |

<!-- team-lead -->
| **Team Lead** | Dependency detection, domain context injection, within-cluster sequencing, pipeline dispatch | Write code, produce plans, perform strategic analysis, review PRs, enrich tickets, classify complexity |

<!-- swarm-retro -->
| **Swarm Retro** | Analyze run logs, detect misclassifications, propose heuristic updates, promote patterns to agent memory | Write code, modify tickets, create PRs, launch pipelines, perform reviews |

<!-- agent-stats -->
| **Agent Stats** | Aggregate metrics.jsonl files into a read-only summary; surface health flags | Modify metrics, emit events, promote lessons, open PRs, run pipelines |

<!-- lessons-review -->
| **Lessons Review** | Surface all per-project lessons in one view; gate promotion to cross-project-lessons.md on user approval | Auto-promote, modify per-project lessons, rewrite malformed entries, write to role-guards or AGENTS.md |
