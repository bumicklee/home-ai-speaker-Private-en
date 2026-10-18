# docs/

These are the feature table, design documents and app screen drawings used while building this speaker. You write your own documents in Chapter 2 of the book, and when you get stuck you compare them with the finished documents here.

| File | Book | Contents |
|:--|:--|:--|
| `01-plan/ai-speaker.features.md` | Chapter 2 | The feature table. Feature IDs used in code comments, the design document and the book (`VOI-03`, `TLG-08`, etc.) are looked up in this table |
| `design.md` | Chapter 2 onward | The design document: pin table, components, BLE and LAN specifications, partitions, sdkconfig. "Design document Section N.N" in code comments refers to this document |
| `design-voice-saver-mode.md` | Chapters 17 and 18 | Design for Saver mode and choosing an AI |
| `design-notes-schedule.md` | Chapter 16 | Design for notes, schedule, and reminders |
| `dev-environment.md` | Chapter 1 | The development environment (version table, install commands, common problems) |
| `ai-pa-app-screens.pdf` | Chapter 11, Appendix F | The 25 screens of the finished app (one screen per page) |
| `jarvis-app-design.html` | Chapter 11 | The first design canvas, exported (11 screens; its labels are still in Korean) |

- Dates and "Phase N" labels are kept as they were recorded during the build. The book calls them "Chapter N."
- The plan document, step-by-step work logs and root cause analysis (RCA) documents are not included. The same content is in the matching chapters of the book, and the code comments also point to the book's chapters and sections.
- `HANDOFF.md` (the handoff document) is not included. It is a document the next Claude Code session reads to learn the current state, so you create it directly in your repository in Chapter 2.
- The document templates are in `.claude/skills/speaker-method/templates.md` (`/speaker-method plan`, `design`, `handoff`, `rca`).
