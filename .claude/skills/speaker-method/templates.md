# Working-Method Templates

The general templates (T-01–T-08), review prompts (PR-01–PR-03), and RCA format (PD-03) from Appendix K of the book, plus the chapter prompts that first create the plan, design, and handoff documents, collected by `/speaker-method` argument. Replace the parts in parentheses with your own. The prompts are the same text as in the book.

| Argument | Templates |
|:--|:--|
| `plan` | One-page plan document for a new feature: T-01, P02-01, P02-02, P21-01 |
| `design` | Writing a design document section: T-02, P20-02, P21-02 |
| `handoff` | Updating the handoff document: T-07, P02-03, P02-04 |
| `rca` | Failure analysis report: T-05, PD-03, T-06 |
| `review` | Adversarial review against the existing code: PR-01 |
| `security` | Review from a security perspective: T-04, PR-02, PR-03 |
| (no argument) | Common: T-03 implementation request, T-08 commit request |

When building a new feature from scratch, use them in this order: `plan` → `design` → T-03 (implementation) → `review`, `security` → `rca` (if a problem comes up) → T-08 (commit) → `handoff`.

## `plan` — One-Page Plan Document for a New Feature

The general template is T-01. Use P02-01 and P02-02 when you first create the plan document and feature table in Chapter 2, and P21-01 when you want a finished plan document reviewed.

### T-01 One-page plan document for a new feature
```text
Reference document: the plan document template in Chapter 2 of this book, the existing feature table in docs/01-plan/.
Write a one-page plan document for (feature name) as docs/01-plan/(slug).plan.md. Goal (who, when, what), success criteria (sentences confirmable by one log line or a sound or LED), out of scope, risks, decisions to make (answer column "undecided").
Do not change: the server-free design, the Android app, the behavior of existing features. Don't write code. I make the decisions.
How to verify: within one A4 page (about 60 lines). Each success criterion must have the log or behavior to check attached.
```

### P02-01 One-page plan document · Chapter 2, Section 2.3
```text
Reference document: the plan document template in Chapter 2 of this book. I'm attaching my notes (the "features our family wants" list from Chapter 0).
Write docs/01-plan/home-speaker.plan.md in the template's order. In the goals table of section 1, put the features from my notes as F1–F7 and leave the priority empty (I'll decide). For decisions D1–D8 in section 6, keep the questions from Chapter 2 of this book as they are and set the answer column to "undecided".
Do not change: the target board (Waveshare ESP32-S3-AUDIO-Board), ESP-IDF v5.5, the server-free design. Do not add features that are not in my notes.
How to verify: it must fit on one page (about 60 lines on A4). If it runs over, trim the section 2 references and the section 8 risks.
```
**How to verify** `wc -l docs/01-plan/home-speaker.plan.md`. **If you get stuck** If a feature that isn't in your notes got in: "Put the lines of my notes and the section 1 table of the plan side by side, and delete the lines that aren't in my notes."

### P02-02 Feature table draft · Chapter 2, Section 2.3
```text
Reference document: section 1 of the home-speaker.plan.md you just wrote and the feature table template in Chapter 2 of this book.
In docs/01-plan/home-speaker.features.md, split F1–F7 by area code (SYS, PRV, VOI, AST, RAD, TLG, APP, OTA) and assign feature IDs. Put a table of feature counts per area at the top. Leave the whole priority column as "P?".
Do not change: the ID rule 'area-number'. Completion criteria must be sentences you can verify by eye, ear, or log ("it works" is forbidden).
How to verify: the number of rows in the table must match the tally at the top. Count with grep -c '^| [A-Z]\{3\}-' and show me.
```
**How to verify** Run the same `grep -c` yourself and compare the numbers. **If you get stuck** If "it works" is still there: "Find the cells in the completion criteria column that contain 'works', 'normal', or 'fine', and replace them with a log line or a sound or LED."

### P21-01 Reviewing a new feature's plan document · Chapter 21, Section 21.3
**When** When starting the graduation project (wellness check). Write the plan document first with T-01.
```text
Read docs/01-plan/wellness-check.plan.md and answer three things only. (1) Can the success criteria be confirmed by a single log line? (2) Is there a risk missing from "out of scope" (for example, Wi-Fi down all day)? (3) Assign F1–F4 IDs that fit the existing feature table's ID scheme.
Do not change: the plan document body. Proposals only, in a table.
How to verify: a table (item | now | proposal | reason).
```
**How to verify** Read the table and carry only what you accept into the plan document. **If you get stuck** If the proposal modified the plan document, revert with `git checkout -- docs/01-plan/wellness-check.plan.md`.

## `design` — Writing a Design Document Section

The general template is T-02. P20-02 is an example of turning notes into a one-page design document, and P21-02 is an example of validating a finished design document against the existing one. After writing the design document, request the implementation with T-03 ("Common" at the bottom).

### T-02 Writing a design document section
```text
Reference document: docs/01-plan/(slug).plan.md, the (names of related sections) of the design document docs/design.md, the actual code in (related folder).
Write docs/design-(slug).md. Sections: data, firmware (which component, whether a new task, memory location), LAN and BLE API (routes, JSON, error codes), app, logs (what is printed and what is not), tests (self-test, real board).
Do not change: the existing design documents and code. Where the design document and the code differ, write based on the code and put the differences in a separate table.
How to verify: every new API has an error response, and every new buffer has its location (internal RAM/PSRAM) written down. An 'Open Questions' section at the end.
```

### P20-02 Emergency mode design document · Chapter 20, Section 20.3
```text
Based on the 'emergency mode' note in the to-do list, write a one-page emergency mode design document as docs/design-emergency-mode.md. Don't write code.
Reference document: the 'emergency mode' note in the to-do list (behavior, trigger words, limits, what it doesn't do, implementation notes), the Telegram tool protection from Chapter 15 (tool_guard TLG-14), the 'LAN API' section of the design document (docs/design.md).
Do not change: the TLG-14 protection makes an exception only for the emergency tool. No direct calls or texts to 119 (emergency services). Write "the speaker is not presented as the primary way to call for help" on the first line of the design document.
How to verify: the design document must have (1) the 5 steps of behavior, (2) a table of trigger word groups, (3) 5 limits, (4) what it doesn't do, (5) firmware, app, and test notes. Write nothing beyond that.
```
**How to verify** Read it yourself for the five groups. Check the first-line sentence. **If you get stuck** If the design document writes a sentence promising an emergency-call feature, have it deleted.

### P21-02 Validating the design document · Chapter 21, Section 21.3
**When** After writing the design document with T-02.
```text
Check docs/design-wellness-check.md against the 'LAN API' section of the design document docs/design.md, the 'Reminder Engine' section of docs/design-notes-schedule.md, and the settings (GET/PUT /settings/{group}) section and the 'Where everything is stored' section of the API spec document.
Find: (1) places that violate the rule for adding a settings group, (2) what happens when it hooks into the reminder engine tick and lands in the same minute as an existing schedule reminder, (3) NVS key name collisions.
Do not change: the existing design documents. Don't write code either.
How to verify: a table (section | problem | source file:section | sentence to fix).
```
**How to verify** Choose from the "sentence to fix" column and apply it to the design document yourself. **If you get stuck** NVS key names are limited to 15 characters. Add that this limit should be part of the collision check.

## `handoff` — Updating the Handoff Document

Send T-07 before ending a session. Use P02-03 and P02-04 when you first create HANDOFF and CLAUDE.md in Chapter 2.

### T-07 Updating the handoff (HANDOFF)
```text
Reference document: the HANDOFF template in Chapter 2 of this book and the current docs/HANDOFF.md.
Update docs/HANDOFF.md with what was done in this session.
- Change the one-line status at the top.
- Add the decisions I settled this time to section 3 (only what I said).
- Move what the review proposed but I haven't confirmed to section 4.
- In section 7, don't delete finished items; strike them through and add ✅. Mark each item as "not verified on hardware" where that applies.
- Put the one thing the next session should do first at the top of section 7.
Do not change: the line "The next session reads this document first", the commit rule in section 5. Don't write secrets.
How to verify: show only git diff docs/HANDOFF.md.
```

### P02-03 Creating the handoff document · Chapter 2, Section 2.3
```text
Reference document: the HANDOFF template in Chapter 2 of this book.
Create docs/HANDOFF.md. The status is "docs only, no code". The only item under section 7, next steps, is "Chapter 4 firmware skeleton".
Do not change: the one line at the top, "The next session reads this document first". Put "Commits are made only when I ask" in section 5.
How to verify: after creating the file, show only git status and don't commit.
```
**How to verify** `head -5 docs/HANDOFF.md`. **If you get stuck** Update it with T-07 in every later session.

### P02-04 Creating CLAUDE.md · Chapter 2, Section 2.3
```text
Reference document: the CLAUDE.md template in Chapter 2 of this book and docs/HANDOFF.md.
Create CLAUDE.md at the top of the repository, in six groups: what to read first, build and test commands, coding rules (only point to the 'Coding Rules' section of the design document), secrets rules, scope (Android only, no store release), and Git rules.
Do not change: it fits on one screen. Don't copy the contents of the design document; point to it by section name. The last line is "For any change that lowers security, first explain the risk, the protection that remains, and how to revert, then wait for my decision".
How to verify: when I open a new session and ask "What are the commit rules?", the answer must be in this file's words.
```
**How to verify** Ask it yourself in a new session. **If you get stuck** If the file grows long: "In CLAUDE.md, delete what's already in the design document or HANDOFF and replace it with one line that points to that document."

## `rca` — Failure Analysis Report

When you get a log, first sort out the time order and the causes and effects with T-05. Start the root cause analysis document in the PD-03 format before fixing anything, and wrap it up with T-06 after the fix.

### T-05 Log analysis
```text
I'm pasting the log (timestamps intact, not trimmed). (log)
I did (what I did) and saw (what I saw / didn't see).
1) Explain what happened in time order, pointing to timestamps rather than line numbers.
2) Mark each error and warning line as "cause or effect".
3) Check with grep whether these log strings exist in the current firmware (it could be a log from old firmware).
Don't fix anything yet.
```

### PD-03 Write an RCA document
```text
Write a root cause analysis document at docs/rca_<slug>.md. Reference: the RCA format in Chapter 19 of this book (format A for a single problem, format B when several are entangled).
Header: date written, target firmware commit (the output of git rev-parse --short HEAD), one-line status.
Format A: symptom (log as is, 5 lines before and after) | direct cause | root cause | contributing cause | impact | fix | remaining work. Then the timeline, what it wasn't, why it wasn't caught during development, how to verify (expected logs), and a recurrence prevention table.
Do not change: don't write the direct cause and the root cause as the same sentence. Distinguish "build passes" from "✅ verified on hardware" in the status. Leave anything I haven't seen on the real board as "needs hardware check".
How to verify: the recurrence prevention table has at least one line saying "added a log" or "added to the self-test".
```
**How to verify** Start writing it before fixing the code. After the fix, update only the status column.

### T-06 Writing an RCA
```text
Write an RCA for the problem just fixed. Follow the PD-03 format.
Attached: the symptom log, a summary of the fix diff, the verification log (if any).
Mark as "✅ verified on hardware" only what I saw on the real board. In the recurrence prevention table, at least one line with a log or self-test that will find this faster next time.
```

## `review` — Adversarial Review Against the Existing Code

Keep the review session and the fixing session separate. Pick the lines to fix from the table you get back, then have them fixed with T-03.

### PR-01 Compare comments and code line by line
**When** Right after porting verified code (the Chapter 6 approach).
```text
You are a reviewer. Don't modify code; report only.
Target: firmware/components/live_voice/, firmware/components/assistant/.
Reference: first read the "kept as is / changed" notes in each source file's header comment.
To do: compare the header comment with the code line by line and find (1) places that changed but aren't noted in the comment, (2) places where the order of session number, state flags, and failure marking has changed, (3) places where two tasks touch the same variable without a lock.
Output: a table (file·function | behavior the comment describes | current behavior | impact | severity). Label conjecture "conjecture".
Do not change: modify nothing.
How to verify: attach a one-line reproduction sequence to each row of the table. I'll confirm with logs.
```
**How to verify** Pick the rows you'll fix from the table you receive, then have them fixed with T-03. Keep the reviewing session and the fixing session separate.

## `security` — Review from a Security Perspective

The general template is T-04, and PR-02 is the version fitted to this book's speaker. When you want to ask for a protection to be lifted, follow the PR-03 sequence.

### T-04 Review request (security perspective)
```text
You are a security reviewer. Don't modify code; report only.
Target: (folders and files). Reference: (library source path) and the '(section name)' section of the design document.
Questions: ① Can outside input alone stop a feature or exhaust memory? ② Is there a buffer or log where a secret remains unerased? ③ What happens when input larger than the buffer arrives? ④ Is the stack of the task running this code sufficient? ⑤ Is there a path by which outside text is turned into an AI instruction?
Output: a table (problem | how it happens | conditions needed | fix candidates). Evidence as file and function names. One reproduction line each.
```

### PR-02 Security review (against ESP-IDF source)
**When** After building code that takes input from outside, like BLE, LAN, and Telegram.
```text
You are a security reviewer. Don't modify code; report only.
Target: firmware/components/messenger_telegram/, firmware/components/assistant/tool_guard.c, firmware/components/local_api/.
Reference: the ESP-IDF v5.5 source (~/esp/esp-idf-v5.5/components/esp_http_client/, esp_http_server/, nvs_flash/) and the 'BLE GATT Specification' and 'LAN API' sections of the design document docs/design.md.
Answer five questions. ① Can an unregistered stranger stop a feature or exhaust memory just by sending the bot a message? ② Is there a buffer where an API key or bot token isn't erased after being copied (including the BUSY and error paths)? ③ What happens when a response is larger than the buffer? ④ Is the stack of the task doing TLS + JSON parsing sufficient (compare with the IDF example values)? ⑤ Is there still a path by which a message body is turned into an AI instruction?
Output: a table (problem | how it happens | what the attacker needs | fix candidates). When citing IDF source, give the file and function names.
How to verify: for each problem, write "this is how to reproduce it" as a curl or Telegram message example.
```
**How to verify** What this review found during the build: a way to stall Telegram forever with 10 long messages, a way to bypass protection via echo, and a stack shortage. Limits that can't be fixed (the library frees its copy of the token without erasing it) are documented as limits.

### PR-03 When requesting a change that lowers security
**When** When you want to ask for something like "lift the restriction". Also when Claude Code's automatic check has refused.
```text
I want to lift (the restriction to lift). Don't change it yet.
Answer in a table: (1) what gets weaker, (2) what protection remains as is, (3) what an attacker needs to use this gap, (4) how to revert (file and function names).
Give three or more options (keep as is / lift partially / lift entirely), with the risk of each.
Apply only after I choose, and when you do, record the decision and the remaining risk in the design document and HANDOFF.
```
**How to verify** During the build I followed this sequence when lifting the Telegram reply protection (Chapter 2; Chapter 19, Section 19.5). Even when the automatic check refuses, don't go toward turning the check off.

## Common — Implementation and Commit

Once there is a design document, request the implementation one step at a time with T-03, and when verification is done, request the commit with T-08. Commits happen only when you ask.

### T-03 Implementation request
```text
Reference document: the '(section name)' section of the design document docs/design-(slug).md, similar existing code at (file path).
Implement (what). (files and functions to create)
Do not change: (existing function names and arguments, settings keys and defaults, dependency direction, the Live engine, and anything else that must not be touched). Large buffers in PSRAM. Don't log secrets or content.
How to verify: idf.py build with 0 warnings (or flutter analyze 0, flutter test passes). Separate pure computation into its own file with a Mac self-test PASS. A list of the expected log lines to see on the real board. Don't commit.
```

### T-08 Commit request
```text
Show me git status and git diff --stat.
Check that no secrets (keys, tokens, passwords, files under certificates/, sdkconfig) are staged; if any are, stop and tell me.
If there are no problems, make this change alone into one commit. Message: one line on the first line saying what was done, a blank line, then a body with why it changed and what was verified (build, tests, whether on the real board). Include the feature ID if there is one.
Don't push.
```
