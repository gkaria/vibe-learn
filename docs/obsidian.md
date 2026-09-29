# Obsidian

Part of [vibe-learn](../README.md). Save learnings to an [Obsidian](https://obsidian.md) vault and recall them across sessions.

```
/learn obsidian                          — save a learn note to your vault
/learn obsidian:recall authentication    — search past notes on a topic (read-only)
/digest obsidian                         — save the session digest to your vault
/digest obsidian:recall                  — digest enriched with connections to previous work
```

On first use, the assistant asks for your vault path and offers to save it to `.vibe-learn/obsidian.json` (project) or `~/.vibe-learn/obsidian.json` (global). Equivalent Codex, Copilot CLI, Grok, and Cursor requests work the same way via the skill.

Config keys (`config/obsidian-defaults.json` is the template):

- `vault_path` — absolute path to the vault root (required)
- `subfolder` — folder within the vault (default: `Development/Sessions`)
- `tags` — added to every note's frontmatter (default: `["vibe-learn"]`)
- `link_style` — `"wikilink"` or `"markdown"`
- `include_project_tag` — add the project directory name as a tag
- `note_naming` — filename template (default: `{date}-{project}`)
