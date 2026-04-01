# vibe-learn

**A learning companion for the vibe coding era.**

Watches Claude Code build your software. Helps you understand what was built, why, and how — at your own pace.

---

## The Problem

Vibe coding gives you **output without understanding**. Claude writes 15 files, refactors a module, adds error handling, installs three dependencies — and you hit "accept" on all of it. A week later you can't debug your own app because you never really learned the architecture.

The faster AI gets at building, the wider the gap between "what was built" and "what the builder understands." vibe-learn closes that gap.

---

## Who Is This For?

- **Beginners** vibe coding their first app — need explanations of *what* and *why*
- **Mid-level developers** learning new patterns or frameworks via Claude — need explanations of *approach* and *trade-offs*
- **Senior engineers** auditing or reviewing what Claude built — need a structured walkthrough of *decisions* and *architecture*

vibe-learn adapts its depth and language based on the complexity of the codebase and the nature of the changes.

---

## Three Learning Modes

### 1. Pause Summaries
During natural pauses (when Claude finishes a response), a brief "here's what just happened" summary is generated. Not a full report — just enough to keep you oriented.

**Implementation:** Stop hook generates a 3–5 line mechanical summary of the last batch of changes. Delivered via additionalContext (so Claude sees it too) and written to `pause-summary.txt`. No API calls — pure bash + jq.

**Example output:**
```
⏸ vibe-learn — what just happened:
Goal: add user authentication and PostgreSQL connection

  ✦ Created src/middleware/auth.ts
  ✦ Created src/db/connection.ts
  ✦ Ran: npm install pg pg-pool
  ✦ Edited src/index.ts

Use /learn to understand any of these decisions, or /digest for a full session report.
```

### 2. On-Demand Digest
Run `/digest` to generate a structured learning report: what changed, the architectural decisions made, patterns used, and things to study further.

**Implementation:** A slash command that instructs Claude to read the session log and generate a markdown report. Leverages Claude's own context window — no external API calls. Optionally saves to `.vibe-learn/digests/`.

**Example output:** A markdown file like:
```markdown
# Session Digest — 17 Mar 2026, 14:32–15:47

## What Was Built
REST API with JWT authentication, three endpoints, and PostgreSQL integration.

## Key Decisions
- **Why Express over Fastify?** Claude chose Express because...
- **Why bcrypt for password hashing?** Industry standard because...

## Patterns Used
- Repository pattern for database access
- Middleware chain for auth → validation → handler

## Things to Study
- [ ] How JWT refresh tokens work
- [ ] Express middleware execution order
- [ ] PostgreSQL connection pooling with `pg-pool`
```

### 3. On-Demand Query
Ask a question about what Claude built, and vibe-learn answers with full grounding in the actual session activity.

**Implementation:** The `/learn` slash command instructs Claude to read the session log and answer questions like:
- "Why did Claude use the repository pattern here?"
- "What does this middleware chain do?"
- "Explain the error handling approach in this module"

The query has access to:
- The raw session log (what tools were used, what files were changed)
- The actual file contents (via Read tool access)
- The session transcript (what Claude said while building)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  CLAUDE CODE SESSION                     │
│                                                          │
│  SessionStart → UserPrompt → [Tool Use]* → Stop          │
│       ↓              ↓           ↓            ↓          │
│  [Bootstrap]    [Capture]   [Observe]    [Summarise]     │
└───────┬──────────────┬───────────┬────────────┬──────────┘
        ↓              ↓           ↓            ↓
┌─────────────────────────────────────────────────────────┐
│                 .vibe-learn/                              │
│                                                          │
│  session-log.jsonl   ← raw event stream (append-only)    │
│  session-meta.json   ← counters, timestamps, config      │
│  pause-summary.txt   ← latest pause summary              │
│  digests/            ← /digest markdown reports           │
│  └── 2026-03-17-1432.md                                  │
└─────────────────────────────────────────────────────────┘
```

### Hook Mapping

| Hook Event         | Matcher                          | Mode           | Purpose                              |
|--------------------|----------------------------------|----------------|--------------------------------------|
| `SessionStart`     | —                                | Bootstrap      | Create dirs, load config, inject prior digest |
| `UserPromptSubmit` | —                                | Capture        | Log the human's original prompt/intent |
| `PostToolUse`      | `Write\|Edit\|MultiEdit\|Bash`   | Observe        | Log every meaningful action (sync, fast) |
| `Stop`             | —                                | Pause Summary  | Brief "what just happened" summary   |

### Key Design Principle: Fast and Local

All hooks are synchronous, mechanical, and fast — no API calls, no network dependencies. The observe hook must complete in < 50ms and never block Claude.

The intelligent learning features (`/learn` and `/digest`) are slash commands that leverage Claude's own context window. No separate API integration needed — Claude reads the session log directly and generates explanations on demand.

---

## Data Model

### Session Log Entry (JSONL)

```json
{
  "timestamp": "2026-03-17T14:32:05Z",
  "event": "tool_use",
  "tool": "Write",
  "file": "src/middleware/auth.ts",
  "action": "created",
  "summary": null,
  "context": {
    "new_file": true,
    "lines": 42
  }
}
```

```json
{
  "timestamp": "2026-03-17T14:32:01Z",
  "event": "user_prompt",
  "prompt": "Add JWT authentication to the API",
  "context": {}
}
```

### Session Metadata

```json
{
  "session_id": "abc123",
  "started_at": "2026-03-17T14:32:00Z",
  "event_count": 47,
  "config": {
    "log_dir": ".vibe-learn"
  }
}
```

---

## Phased Build Plan

### Phase 1: The Observer (Foundation)
**Ship this first. Everything else builds on it.**

- SessionStart bootstrap hook
- PostToolUse sync observer (JSONL logging)
- UserPromptSubmit capture (log the human's intent)
- Basic Stop hook (mechanical summary, no AI)
- `.vibe-learn/` directory structure
- README with setup instructions

**Deliverable:** A working hook system that silently logs everything Claude does. Pure bash + jq — no external dependencies.

**Status:** Complete.

### Phase 2: The Digest & Query (Learning Commands)
**The learning layer — powered by Claude's own context window.**

- `/digest` slash command — structured markdown report (What Was Built, Key Decisions, Patterns Used, Things to Study)
- `/learn` slash command — on-demand Q&A grounded in session activity
- Both read the session log directly via Claude's Read tool
- No external API calls — leverages the intelligence already in the conversation
- Optionally saves digest reports to `.vibe-learn/digests/`

**Deliverable:** Two slash commands that turn raw session data into understanding.

**Status:** Complete.

### Phase 3: Polish & Distribution
- Configuration UI or config file for preferences
- Support for multiple learning levels (beginner/intermediate/senior)
- Cross-session learning history
- npm/plugin registry publishing

---

## Distribution

**Repo:** `vibe-learn` (github.com/gkaria/vibe-learn)

**Format:** Global setup via `setup.sh` (primary) + per-project `install.sh` (secondary) + manual hook config (tertiary)

**Plugin structure:**
```
vibe-learn/
├── README.md
├── LICENSE (MIT)
├── hooks.json                    # Plugin hook configuration
├── CLAUDE.md                     # Directive for Claude Code awareness
├── .claude/commands/
│   ├── learn.md                  # /learn slash command
│   └── digest.md                 # /digest slash command
├── scripts/
│   ├── bootstrap.sh              # SessionStart: initialise session
│   ├── observe.sh                # PostToolUse (sync): log events
│   ├── capture-prompt.sh         # UserPromptSubmit: log human intent
│   ├── pause-summary.sh          # Stop: brief summary
│   └── install.sh                # Install vibe-learn into a project
├── config/
│   └── defaults.json             # Default configuration
└── examples/
    ├── sample-session-log.jsonl  # Example raw session log
    ├── sample-pause-summary.txt  # Example pause summary
    └── sample-digest.md          # Example /digest output
```

---

## Positioning

**Tagline:** "Learn as Claude builds."

**For Gaurang's audience:** This sits at the intersection of AI tooling, developer education, and the vibe coding movement. It's a tool *and* a thesis — that the best way to learn from AI isn't to stop it from coding for you, but to have it teach you while it does.

**Content potential:**
- Weekly Commit piece: "I Built a Learning Layer for Vibe Coding"
- YouTube walkthrough: Screen recording of a vibe-learn session
- X thread: The problem, the solution, the demo
- Open-source launch on GitHub

---

## Open Questions

1. **Transcript access:** Can hooks read the Claude Code transcript (what Claude *said* while building)? The `transcript_path` field in hook input suggests yes — this would improve `/learn` and `/digest` quality.
2. **Notification display:** Can hooks surface text in the terminal UI without using stdout (which goes to Claude's context)? The Notification event might help here.
3. **Privacy:** Session logs may contain sensitive code. Need clear documentation about what's stored and where.
