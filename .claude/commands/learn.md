Read .vibe-learn/session-log.jsonl to understand what has happened in this session.

If $ARGUMENTS is empty:
  Summarise the most recent actions in plain language — what was just built or changed, the decisions behind it, and any interesting patterns or concepts used. Format as a readable list starting with "📘 **What just happened:**". Keep it tight — 3-5 points max.

If $ARGUMENTS is provided:
  Answer the specific question: $ARGUMENTS
  Ground your answer in the session log and read relevant source files with your Read tool. Explain as if talking to someone learning to code — clear, no jargon, specific to what actually happened in this session.

In both cases: if the session log is empty or only has prompts with no tool events, say so and offer general help instead.
