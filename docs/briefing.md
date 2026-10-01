# Session briefing and audio

Part of [vibe-learn](../README.md). After each session a local HTML briefing is generated from the same log the learning commands read. This page is how to open it and how to turn it into a NotebookLM audio overview.

---

## Open the briefing

```bash
vibe-learn briefing          # regenerate and show path
```

Plugin-only install? The `vibe-learn` CLI is on the Bash tool's PATH inside Claude Code, so just ask Claude to run `vibe-learn briefing`. To have it in your own shell too, run the curl installer — it adds the CLI and skips the duplicate hooks.

The briefing includes: maintainer brief (what changed / why it matters / inspect first / what could break), session timeline with filter buttons, file tour with colour-coded area badges, command log with failure highlighting, syntax-highlighted diff, a study queue, and a NotebookLM-ready source pack. When `.vibe-learn/knowledge.json` exists, the study queue leads with your shaky concepts, the page gains a Knowledge State section, the source pack gains a "Your knowledge state" table, and the audio prompt asks NotebookLM to dwell on what you've struggled with. Once you have a few sessions of [assistant health](health.md) history, the page also gains an Assistant health card: this session's numbers against your usual ones, and the tools and skills the session used.

No server, no build step, no external assets — just a static HTML file that opens directly from disk.

Screenshots of the index and session page live on the README under [What it looks like](../README.md#what-it-looks-like). The health trend page is in [docs/health.md](health.md).

---

## Audio overview with NotebookLM

Every session briefing also produces a markdown source pack at `.vibe-learn/briefing/exports/<session>-notebooklm-pack.md`. This is a structured document containing the session summary, timeline, file list, commands, and diff excerpt — formatted for upload to [NotebookLM](https://notebooklm.google.com).

To prepare the upload in one step:

```bash
vibe-learn audio-prep
```

This:

1. Finds the latest pack in `.vibe-learn/briefing/exports/`
2. Copies the file path to your clipboard
3. Opens NotebookLM in your browser
4. Opens the exports folder in Finder
5. Prints the audio prompt to paste when NotebookLM asks to customise the overview

The audio prompt tells NotebookLM to produce a maintainer-focused overview — what changed, why it matters, what to inspect first, what could break — pitched at someone who owns and needs to support the codebase. Upload the pack as a source, generate an Audio Overview, and listen on your commute.
