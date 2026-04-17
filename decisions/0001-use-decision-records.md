# 0001. Use decision records

## Context

Past reasoning about how this system is configured lived in ad-hoc session logs and plan docs. That worked while memory was fresh but didn't scale.

## Decision

Keep short markdown records under `decisions/`, one per significant decision, numbered monotonically (`0001-topic-slug.md`). Each captures the context that forced the decision and the trade-offs considered. Rewrites happen by adding a new record, not editing the old one. Skipping the Status section, no value for a single-user dotfiles repo.

References: [Nygard's original ADR post](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions), [Fowler's 2026 take](https://martinfowler.com/bliki/ArchitectureDecisionRecord.html).
