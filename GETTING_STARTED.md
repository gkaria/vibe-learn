# Getting Started with vibe-learn

This walks you through your first session — from install to having an audio overview ready. Takes about 10 minutes.

---

## 1. Install

```bash
curl -fsSL https://raw.githubusercontent.com/gkaria/vibe-learn/main/scripts/setup.sh | bash
```

You'll see output like:

```
Installing vibe-learn to ~/.vibe-learn/
✓ Scripts installed
✓ Claude Code hooks registered (~/.claude/settings.json)
✓ Slash commands installed (~/.claude/commands/)

Claude Code:
  /learn              — explain what just happened
  /digest             — full session learning report
  /quiz               — check your understanding
  vibe-learn briefing — maintainer briefing
  vibe-learn audio-prep — prepare NotebookLM audio overview

Make sure ~/.local/bin is in your PATH:
  export PATH="$HOME/.local/bin:$PATH"
```

That's it. vibe-learn is now active globally for every project you open in Claude Code.

**Requires `jq`** — if you don't have it: `brew install jq` (macOS) or `apt-get install jq` (Linux).

---

## 2. Open a project and work normally

Open any project in Claude Code and give it a real task — something that involves writing or editing files:

```
Build a simple Express API with a /health endpoint
```

You don't need to do anything differently. vibe-learn runs silently in the background, logging every file write, edit, and command to `.vibe-learn/session-log.jsonl`.

---

## 3. See what appeared in context

After Claude finishes its response, look at the **next message Claude sends** — it will have a pause summary injected at the top of its context. When Claude references what it just did, you're seeing vibe-learn's summary feeding through.

If you ask Claude "what did you just do?", it knows — because vibe-learn told it. The summary looks like this:

```
⏸ vibe-learn — what just happened:
Goal: Build a simple Express API with a /health endpoint

  ✦ Created src/index.ts
  ✦ Created src/routes/health.ts
  ✦ Ran: npm install express
  ✦ Ran: npx tsc --noEmit

 /learn [question]  ·  /digest  ·  vibe-learn briefing  ·  vibe-learn audio-prep
```

That last line is your menu. You can type any of those commands right now.

---

## 4. Ask `/learn`

Type `/learn` to get a plain-language explanation of what was just built:

```
/learn
```

Claude reads the session log and explains what happened — the files created, why each decision was made, what patterns were used. No arguments needed.

You can also ask a specific question:

```
/learn why did we separate the health route into its own file?
/learn what does the tsconfig do here?
/learn explain the middleware setup
```

The answer is grounded in your actual session — the real files, the real commands, the real choices the AI made — not a generic explanation.

---

## 5. Get a full session report with `/digest`

At the end of a longer session, run:

```
/digest
```

This produces a structured learning report:

```
## Session Digest

### What Was Built
A minimal Express API with a /health endpoint, TypeScript configuration,
and basic project structure.

### Key Decisions
- Express chosen over Fastify for familiarity and ecosystem size
- Health route separated into its own file to establish a routing pattern
  for future endpoints
- TypeScript strict mode enabled to catch type errors early

### Patterns Used
- Route handler separation
- Middleware registration order
- npm scripts for build and dev workflows

### Files Worth Reviewing
- src/index.ts — app entry point and middleware wiring
- src/routes/health.ts — example of the routing pattern used throughout

### Things To Study Next
- [ ] How Express middleware order affects request handling
- [ ] What npx tsc --noEmit does and when to run it
- [ ] How to add error handling middleware
```

Save it to a file with `/digest` — Claude will offer to write it to `.vibe-learn/digests/`.

---

## 6. Check your understanding with `/quiz`

Reading the digest feels like learning; answering questions proves it. Run:

```
/quiz
```

Claude picks 3–5 moments from the session and asks about them one at a time:

```
Question 1 of 3: The health route was separated into its own file instead
of living in index.ts. Why, and what does that make easier later?
```

Answer in your own words. After each answer, Claude tells you what you got right, what you missed, and gives a short correct explanation — colleague tone, not an exam.

Results are saved to `.vibe-learn/knowledge.json`, a small cross-session knowledge ledger. That makes the learning cumulative:

- `/quiz review` — re-quizzes concepts you answered shakily, or anything unreviewed for two weeks
- `/learn` — opens with a one-line heads-up when a shaky concept comes up again in a later session
- `/digest` — "Things To Study Next" carries unresolved items forward instead of resetting each session

---

## 7. Open the session briefing

The session briefing was already generated automatically in the background. Open it:

```bash
vibe-learn briefing
```

This prints the path and regenerates if needed:

```
Session briefing index: /your-project/.vibe-learn/briefing/index.html
Session briefing:  /your-project/.vibe-learn/briefing/sessions/2026-06-05-myproject-abc.html
NotebookLM pack:   /your-project/.vibe-learn/briefing/exports/2026-06-05-myproject-abc-notebooklm-pack.md
```

Open `index.html` directly in your browser — no server needed. You'll see the session index, and from there you can open the full briefing which includes the maintainer brief, file tour, command log, diff, and study queue.

---

## 8. Prepare an audio overview (optional)

If you want to listen to a walkthrough of the session on your commute:

```bash
vibe-learn audio-prep
```

Output:

```
NotebookLM pack: /your-project/.vibe-learn/briefing/exports/2026-06-05-myproject-abc-notebooklm-pack.md

✓ Pack path copied to clipboard

Next steps:
  1. Open NotebookLM:  https://notebooklm.google.com
  2. Create a new notebook
  3. Add source → Upload file → select the pack above
  4. Generate an Audio Overview

Paste this prompt when asked to customise the overview:

  Create a maintainer-focused audio overview. Explain what changed, why it
  matters, what to inspect first, and what could break. Assume the listener
  owns this codebase and needs enough technical depth to support it.

✓ NotebookLM opened in browser
```

Upload the `.md` file as a source, paste the prompt, and click Generate. NotebookLM produces an 8–15 minute two-host conversation explaining your session back to you — what was built, why decisions were made, what to inspect, what could break.

---

## What happens every session from here

Once installed, this is your normal workflow:

| Moment | What vibe-learn does |
|--------|----------------------|
| You open a project | Session starts, previous summary injected into context |
| Claude writes or edits a file | Logged silently in <50ms |
| Claude runs a command | Logged with exit code |
| Claude finishes a response | Pause summary written, session briefing regenerated in background |
| You type `/learn` | Claude explains the session grounded in the real log |
| You type `/quiz` | Claude checks your understanding and tracks it across sessions |
| You run `vibe-learn audio-prep` | Pack ready, NotebookLM opens |

You don't change how you work. You just have a trail to learn from afterward.

---

## Next steps

- **Codex or OpenCode?** See [README.md](README.md#supported-assistants) for setup.
- **Save notes to Obsidian?** See [README.md](README.md#obsidian-integration).
- **Per-project install** (to share with teammates): `vibe-learn install` in your project root.
- **Something not working?** Check that `jq` is installed and that `~/.local/bin` is in your `PATH`.
