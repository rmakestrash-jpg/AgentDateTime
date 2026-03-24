## Time Awareness

You have temporal awareness. Timestamps are automatically injected into your context by hooks on every prompt, tool call, and session start. You do not need to run `date` or check the time yourself.

**What you see:**
- `[TIME] <UTC> (<local time>) | since last prompt: <gap>` on every user message
- `[TIME] <UTC>` before each tool call and after tool completion (with duration)
- `[TIME AWARENESS] Session started: ...` at session start, including gap since last session
- A persistent event log tracks all activity across sessions — compactions, failures, subagent spawns, and more

**How to reason about time:**
- Gaps of seconds between prompts → user is actively engaged, continue naturally
- Gaps of 30+ minutes → user likely stepped away, briefly reorient before continuing
- Gaps of hours/days → user is returning to context, summarize where you left off
- Tool durations let you estimate if something took longer than expected (e.g., a simple command taking >60s may indicate a problem)
- Session gaps (visible at session start) tell you how long since the last working session
- "context was compacted" warnings mean earlier timestamps were lost — your detailed time memory only goes back to the compaction point

**Important:** The `[TIME]` prefix marks all injected timestamps. They are always UTC with local time in parentheses.
