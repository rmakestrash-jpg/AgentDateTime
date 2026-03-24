# Claude Code Time Awareness

Give Claude Code persistent temporal awareness across and within sessions.

## The problem

Claude Code has no inherent sense of time. It can't tell the difference between a quick follow-up and coming back after 3 hours. It doesn't know how long a build took, when it last touched a file, or whether you've been working for 12 hours straight. Putting "check the time" in your CLAUDE.md is a suggestion Claude will eventually ignore.

## The solution

This system uses Claude Code's hook system to inject timestamps deterministically into every conversation. No prompting required — Claude sees the time automatically on every message, every tool call, and every session start.

Additionally, **every lifecycle event** (21 total) is logged to a persistent append-only file. This gives Claude cross-session temporal memory: it knows when your last session ended, how long ago you worked on something, and what happened while you were away.

A short CLAUDE.md block teaches Claude how to interpret timestamps and reason about time gaps.

## What Claude sees

On every prompt:
```
[TIME] 2026-03-23T14:35:22Z (Mon 2:35 PM EDT (UTC-0400)) | since last prompt: 3m 12s | tools: 5
```

Before every tool call:
```
[TIME] 2026-03-23T14:35:25Z
```

After every tool call:
```
[TIME] 2026-03-23T14:35:30Z (tool took 5s)
```

On session start:
```
[TIME AWARENESS] Session started: 2026-03-23T14:30:00Z (Mon 2:30 PM EDT (UTC-0400))
Last session ended: 2026-03-23T06:15:00Z (8h 15m ago)
Last compaction: 2026-03-23T05:50:00Z
```

## What gets logged (but not injected)

These events are silently logged to `~/.claude/hooks/time_events.jsonl` for cross-session context:

- Stop, SubagentStop — when Claude finishes responding
- SessionEnd — when a session terminates (with reason)
- PreCompact, PostCompact — context compaction events
- PermissionRequest — when Claude waited for your approval
- TaskCompleted, TeammateIdle — agent orchestration events
- ConfigChange, WorktreeCreate/Remove — system events
- Notification, StopFailure, Setup, InstructionsLoaded — lifecycle events

The UserPromptSubmit hook reads this log to build activity summaries.

## Install

### Prerequisites

- [Claude Code](https://code.claude.com) installed
- `jq` installed (`brew install jq` / `apt install jq`)

### Global install (recommended)

```bash
git clone https://github.com/YOUR_USERNAME/claude-time-awareness.git
cd claude-time-awareness
chmod +x install.sh
./install.sh
```

This installs to `~/.claude/` and applies to all projects.

### Per-project install

```bash
cd your-project
/path/to/claude-time-awareness/install.sh --project
```

This installs to `.claude/` in your project directory. Commit `.claude/hooks/` and `.claude/settings.json` to share with your team.

### Manual install

1. Copy `hooks/time-log.sh` and `hooks/time-inject.sh` to `~/.claude/hooks/`
2. Make them executable: `chmod +x ~/.claude/hooks/*.sh`
3. Merge `settings-hooks.json` into your `~/.claude/settings.json`
4. Append `TIME_AWARENESS.md` to your `~/.claude/CLAUDE.md`

### Uninstall

```bash
./install.sh --uninstall
```

Then manually remove the hook entries from your `settings.json` and the Time Awareness block from your `CLAUDE.md`.

## How it works

```
┌──────────────────────────────────────┐
│  CLAUDE.md                           │
│  Teaches Claude to read timestamps   │
└──────────────┬───────────────────────┘
               │ read on every session
┌──────────────┴───────────────────────┐
│  time-inject.sh (Tier 1 hooks)      │
│  Logs event + injects timestamp     │
│  into Claude's conversation context │
├──────────────────────────────────────┤
│  time-log.sh (Tier 2/3 hooks)       │
│  Logs event silently                │
└──────────────┬───────────────────────┘
               │ reads / writes
┌──────────────┴───────────────────────┐
│  time_events.jsonl                   │
│  Persistent append-only event log   │
│  Auto-pruned at 500KB               │
└──────────────────────────────────────┘
```

### Hook classification

| Hook | Injects to Claude? | What it provides |
|------|-------------------|-----------------|
| UserPromptSubmit | ✅ | Timestamp + gap since last prompt + activity summary |
| PreToolUse | ✅ | Timestamp before tool execution |
| PostToolUse | ✅ | Timestamp + tool duration |
| SessionStart | ✅ | Session orientation + gap since last session |
| SubagentStart | ✅ | Subagent spawn timestamp |
| PostToolUseFailure | ✅ | Failure timestamp |
| All other 15 events | Logged only | Cross-session temporal record |

### Token cost

~80 tokens per prompt cycle (1 user message + ~5 tool calls). Negligible — under 0.04% of a 200k context window per cycle.

### Log format

Each line in `time_events.jsonl`:
```json
{"ts":"2026-03-23T14:30:05Z","event":"PreToolUse","sid":"abc123"}
```

The log auto-prunes at 500KB (configurable via `CLAUDE_TIME_LOG_MAX_BYTES` env var), keeping the newest half.

## Files

```
claude-time-awareness/
├── hooks/
│   ├── time-log.sh        # Shared event logger (all hooks call this)
│   └── time-inject.sh     # Context injector (Tier 1 hooks call this)
├── settings-hooks.json    # Hook wiring for all 21 events
├── TIME_AWARENESS.md      # CLAUDE.md block (standalone, import or paste)
├── install.sh             # Installer (global, per-project, or uninstall)
└── README.md              # This file
```

## Configuration

- **Log max size**: Set `CLAUDE_TIME_LOG_MAX_BYTES` env var (default: 524288 / 500KB)
- **Disable specific hooks**: Remove entries from your `settings.json`
- **Reduce noise**: Remove the PreToolUse hook if timestamps on every tool call feel excessive

## What makes this different

| Existing solution | Limitation |
|------------------|-----------|
| "Run `date`" in CLAUDE.md | Claude forgets, especially after compaction |
| Ted Murray's UserPromptSubmit hook | No tool timing, no cross-session persistence, no interpretive framing |
| Sycochucky's claude-code-toolkit | Session-start only, no per-prompt or per-tool timestamps |
| GitHub issue #32913 | Feature request — waiting on Anthropic |
| **This system** | Every lifecycle event logged, 6 injection points, persistent cross-session log, CLAUDE.md framing |

## License

MIT License — free to use, modify, and distribute. See [LICENSE](LICENSE) for full terms.
