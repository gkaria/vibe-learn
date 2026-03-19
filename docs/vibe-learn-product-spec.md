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

## Four Learning Modes

### 1. Real-Time Narration
As Claude codes, short contextual explanations surface — like a mentor narrating what's happening.

**Implementation:** PostToolUse hook (async) calls the Anthropic API with the tool input/output and asks for a one-sentence explanation. Output appears via the Notification mechanism or is logged to a sidecar terminal.

**Example output:**
```
📘 Created src/middleware/auth.ts — JWT authentication middleware
   that validates tokens on every API route. Uses the 'jsonwebtoken'
   package you installed earlier.
```

### 2. Post-Session Digest
When a session ends, vibe-learn generates a structured learning report: what changed, the architectural decisions made, patterns used, and things to study further.

**Implementation:** Stop/SessionEnd hook collects the full session log, sends it to the Anthropic API with a summarisation prompt, and writes a markdown report to `.vibe-learn/digests/`.

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
You ask a question about what Claude built, and vibe-learn answers with full grounding in the actual session activity.

**Implementation:** A custom slash command (`/learn`) or subagent that reads the session log and answers questions like:
- "Why did Claude use the repository pattern here?"
- "What does this middleware chain do?"
- "Explain the error handling approach in this module"

The query has access to:
- The raw session log (what tools were used, what files were changed)
- The actual file contents (via Read tool access)
- The session transcript (what Claude said while building)

### 4. Async Pause Summaries
During natural pauses (when Claude finishes a response), a brief "here's what just happened" digest is generated. Not a full report — just enough to keep you oriented.

**Implementation:** Stop hook generates a 3–5 line summary of the last batch of changes. Delivered via additionalContext (so Claude sees it too) and/or logged to a visible location.

**Example output:**
```
⏸️  Pause Summary (last 8 actions):
    Added user authentication (3 files created, 1 dependency installed).
    Set up PostgreSQL connection with connection pooling.
    Tests: 4 passing, 0 failing.
```

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
│  narration.log       ← real-time explanations            │
│  digests/            ← post-session markdown reports      │
│  └── 2026-03-17-1432.md                                  │
└─────────────────────────────────────────────────────────┘
```

### Hook Mapping

| Hook Event         | Matcher                          | Mode           | Purpose                              |
|--------------------|----------------------------------|----------------|--------------------------------------|
| `SessionStart`     | —                                | Bootstrap      | Create dirs, load config, inject prior digest |
| `UserPromptSubmit` | —                                | Capture        | Log the human's original prompt/intent |
| `PostToolUse`      | `Write\|Edit\|MultiEdit\|Bash`   | Observe        | Log every meaningful action (sync, fast) |
| `PostToolUse`      | `Write\|Edit\|MultiEdit\|Bash`   | Narrate        | Generate real-time explanation (async) |
| `Stop`             | —                                | Pause Summary  | Brief "what just happened" digest    |
| `SessionEnd`       | —                                | Full Digest    | Comprehensive learning report        |

### Key Design Principle: Two Speeds

The system operates at two speeds simultaneously:

1. **Fast path (sync, no API calls):** The observe hook appends a JSONL entry. Must complete in < 50ms. Never blocks Claude.
2. **Slow path (async, API calls):** The narration and digest hooks call the Anthropic API for intelligent summaries. Run in the background. Never block Claude.

This separation is critical — the observer is mechanical and deterministic, the narrator is AI-powered and optional.

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

```json
{
  "timestamp": "2026-03-17T14:33:12Z",
  "event": "narration",
  "target": "src/middleware/auth.ts",
  "explanation": "JWT authentication middleware that validates tokens on every API route. Uses the 'jsonwebtoken' package.",
  "level": "beginner"
}
```

### Session Metadata

```json
{
  "session_id": "abc123",
  "started_at": "2026-03-17T14:32:00Z",
  "event_count": 47,
  "files_created": 8,
  "files_modified": 3,
  "bash_commands": 12,
  "bash_failures": 1,
  "narrations_generated": 15,
  "config": {
    "narration_enabled": true,
    "difficulty_level": "auto",
    "digest_on_end": true
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

**Deliverable:** A working hook system that silently logs everything Claude does. No AI summarisation yet — just the raw data pipeline.

**Effort:** Small. Pure bash + jq. No dependencies beyond what Claude Code provides.

### Phase 2: The Narrator (Real-Time Learning)
**The signature feature.**

- Async PostToolUse hook that calls Anthropic API
- One-sentence explanations for each meaningful action
- Output to `narration.log` (tail-friendly)
- Configurable: on/off, verbosity level
- Adaptive complexity detection (look at file content, framework, patterns)

**Deliverable:** Real-time narration of what Claude is building. Run `tail -f .vibe-learn/narration.log` in a split terminal and watch the explanations flow.

**Effort:** Medium. Needs API integration, prompt engineering for good explanations, async hook setup.

### Phase 3: The Digest (Post-Session Reports)
**The "what did I learn today?" feature.**

- SessionEnd hook generates comprehensive markdown report
- Covers: what was built, key decisions, patterns used, things to study
- Includes links to relevant documentation
- Adaptive depth based on session complexity
- Stored in `.vibe-learn/digests/` with timestamps

**Deliverable:** After every vibe coding session, you get a structured learning document.

**Effort:** Medium. Prompt engineering for good digests, template structure, API integration.

### Phase 4: The Query Interface (On-Demand Learning)
**"Why did Claude do that?"**

- Custom `/learn` slash command or subagent
- Reads session log + file contents + transcript
- Answers grounded questions about the codebase
- Supports follow-up questions (unlike /btw)
- Can reference specific files, patterns, decisions

**Deliverable:** An interactive learning chat grounded in your actual session.

**Effort:** Larger. Needs slash command or subagent setup, context assembly, prompt engineering.

### Phase 5: Polish & Distribution
- Package as Claude Code plugin (hooks.json)
- Configuration UI or config file for preferences
- Support for multiple learning levels (beginner/intermediate/senior)
- Cross-session learning history
- Tests and documentation
- npm/plugin registry publishing

---

## Distribution

**Repo:** `vibe-learn` (github.com/gaurangkaria/vibe-learn)

**Format:** Claude Code Plugin (primary) + standalone setup instructions (secondary)

**Plugin structure:**
```
vibe-learn/
├── README.md
├── LICENSE (MIT)
├── hooks.json                    # Plugin hook configuration
├── CLAUDE.md                     # Directive for Claude Code awareness
├── scripts/
│   ├── bootstrap.sh              # SessionStart: initialise session
│   ├── observe.sh                # PostToolUse (sync): log events
│   ├── capture-prompt.sh         # UserPromptSubmit: log human intent
│   ├── narrate.sh                # PostToolUse (async): AI explanation
│   ├── pause-summary.sh          # Stop: brief digest
│   └── full-digest.sh            # SessionEnd: comprehensive report
├── prompts/
│   ├── narration.txt             # Prompt template for real-time narration
│   ├── digest.txt                # Prompt template for session digest
│   └── query.txt                 # Prompt template for on-demand queries
├── config/
│   └── defaults.json             # Default configuration
└── examples/
    ├── sample-digest.md          # Example of a session digest
    └── sample-narration.log      # Example of narration output
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

1. **Transcript access:** Can hooks read the Claude Code transcript (what Claude *said* while building)? The `transcript_path` field in hook input suggests yes — this would massively improve digest quality.
2. **Slash command registration:** Can a plugin register custom slash commands, or does that require a different mechanism?
3. **Notification display:** Can hooks surface text in the terminal UI without using stdout (which goes to Claude's context)? The Notification event might help here.
4. **Token budget:** The AI narration and digest features consume tokens. Need to estimate cost per session and offer controls.
5. **Privacy:** Session logs may contain sensitive code. Need clear documentation about what's stored and where.
