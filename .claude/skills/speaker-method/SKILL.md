---
name: speaker-method
description: The book's working-method templates. Use when writing a one-page plan document for a new feature, a design document section, a handoff document (HANDOFF) update, a failure analysis report (RCA), an adversarial review against the existing code, or a review from a security perspective.
when_to_use: plan document, design document, handoff, HANDOFF, failure analysis, RCA, root cause analysis, review, check, security review
argument-hint: "[plan | design | handoff | rca | review | security]"
---

# Working-Method Templates

Use the matching template in [templates.md](templates.md) according to the argument. If there is no argument, pick the template that fits the current conversation, and say which one you picked first.

| Argument | What it does |
|:--|:--|
| `plan` | One-page plan document for a new feature (goals, out of scope, decisions to make, stages, risks) |
| `design` | Add one section to the design document (data, flow, API, memory, how to verify) |
| `handoff` | Update `docs/HANDOFF.md` (current state, next steps, decisions not yet confirmed) |
| `rca` | Failure analysis report (symptom, log, direct cause, root cause, contributing cause, fix, recurrence prevention, status) |
| `review` | Adversarial review that compares the code just changed against the original code and the design document line by line |
| `security` | Review from the perspective of secret flows, external input (Telegram, radio titles), authentication, and log leaks |

## Common Principles

- **Don't guess.** Confirm the values used for a decision in the log or the code first, and mark anything you couldn't confirm as "needs confirmation".
- **Record human decisions.** Leave what the user chose, and why, in the document.
- **A review only reports before fixing.** For each problem found, write the evidence (file and function) and how to fix it, and fix it once the user approves.
