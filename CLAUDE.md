# imagineering-pm-bot (Figment)

## Project Overview

**Figment** is a Signal-based project management bot for the Imagineering organization,
named after the beloved purple dragon from EPCOT's Journey Into Imagination — the mascot
of Walt Disney Imagineering. "One little spark" of inspiration turns ideas into tasks.

Every incoming message is processed through a Claude LLM agent loop that has access to
~40 MCP tools for task management (Kan.bn), knowledge base (Outline), calendar
(Radicale), and web automation (Playwright). There are no hardcoded slash commands —
Figment understands natural language and autonomously decides which tools to invoke.

This project is adapted from **xdeca-pm-bot**, a production Telegram bot with the same
architecture. The key difference is the messaging platform: Signal instead of Telegram.

**Status**: Early-stage planning. Signal bot framework is TBD pending research.

## Bot Identity

- **Default name**: Figment
- **Default pronouns**: they/them
- **Default tone**: Playful, imaginative, and helpful — like a creative partner who
  keeps the team organized. Occasionally references "sparks of imagination" but doesn't
  overdo the theme.
- **Naming ceremony**: On first boot in a new chat, Figment introduces itself and the
  admin can rename it, change pronouns, or adjust the tone. Identity is stored per-chat
  in SQLite and injected into the system prompt.

## Tech Stack

| Layer             | Technology                                       |
| ----------------- | ------------------------------------------------ |
| Runtime           | Node.js 22+ / TypeScript 5.x                    |
| Messaging         | Signal (via signal-cli-rest-api or signal-sdk)   |
| LLM               | Claude Sonnet 4.6 (Anthropic API)                |
| Database          | SQLite via Drizzle ORM                           |
| MCP Tools         | Kan.bn, Outline, Radicale, Playwright            |
| Deployment        | Docker on GCP                                    |
| Package Manager   | pnpm                                             |

### Signal Bot Framework (TBD)

Two leading candidates under evaluation:

1. **signal-cli-rest-api** — Dockerized REST API wrapping signal-cli. Most mature
   (2.4k stars, 92 releases, actively maintained). Bot polls or uses webhooks for
   incoming messages and POSTs to `/v2/send` for outgoing. Runs as a sidecar container.

2. **signal-sdk** — TypeScript-native SDK with built-in signal-cli binaries. Provides
   `SignalBot` class with event-driven architecture, JSON-RPC communication, and a
   `SignalCli` class for lower-level control. Newer but purpose-built for bots.

Decision criteria: reliability, group message support, reaction/mention handling,
attachment support, and long-term maintenance outlook.

## Architecture

```
Signal Message
  |
  v
Signal Bridge (signal-cli-rest-api or signal-sdk)
  |
  v
Message Handler (rate limiting, history management)
  |
  v
Agent Loop (Claude Sonnet 4.6)
  |-- MCP: Kan.bn (task management, ~15 tools)
  |-- MCP: Outline (knowledge base, ~15 tools)
  |-- MCP: Radicale (calendar/contacts, ~15 tools)
  |-- MCP: Playwright (web automation)
  |-- Custom tools (chat config, user mapping, sprint info, standups, bot identity)
  |
  v
Response → Signal
```

### Key Components

- **Message handler** — Receives Signal messages, applies rate limiting for groups,
  manages conversation history (20 messages, 30-minute TTL).
- **Agent loop** — Sends conversation history + system prompt to Claude with all
  available tools. Claude decides autonomously what to do.
- **MCP servers** — Git submodule at `./mcp-servers/` containing Kan, Outline,
  Radicale server implementations.
- **Custom tools** — Bot-specific tools defined in `src/tools/` for chat configuration,
  user identity mapping (Signal UUID to Kan user), sprint metadata, standup collection,
  bot personality, deploy info, and server ops.
- **Cron scheduler** — Periodic reminders: overdue tasks, stale tasks, unassigned tasks,
  standup prompts.
- **Database** — SQLite with Drizzle ORM for conversation history, chat config, user
  mappings, standup records, and bot state.

## Development Commands

```bash
# Install dependencies
pnpm install

# Development (watch mode)
pnpm dev

# Build
pnpm build

# Run production
pnpm start

# Run tests
pnpm test

# Run tests in watch mode
pnpm test:watch

# Lint
pnpm lint

# Format
pnpm format

# Type check
pnpm typecheck

# Database migrations
pnpm db:generate    # Generate migration from schema changes
pnpm db:migrate     # Apply pending migrations
pnpm db:studio      # Open Drizzle Studio

# Docker
docker compose up -d          # Start bot + signal-cli-rest-api
docker compose logs -f bot    # Tail bot logs
```

## Environment Variables

```bash
# Anthropic
ANTHROPIC_API_KEY=            # Claude API key

# Signal
SIGNAL_PHONE_NUMBER=          # Bot's registered Signal phone number
SIGNAL_API_URL=               # signal-cli-rest-api base URL (if using REST approach)

# Kan.bn
KAN_BASE_URL=                 # Kan.bn instance URL
KAN_API_KEY=                  # Kan.bn API key

# Outline
OUTLINE_BASE_URL=             # Outline instance URL
OUTLINE_API_KEY=              # Outline API key

# Radicale
RADICALE_BASE_URL=            # Radicale CalDAV/CardDAV server URL
RADICALE_USERNAME=            # Radicale auth username
RADICALE_PASSWORD=            # Radicale auth password

# Bot Config
BOT_NAME=                     # Display name for the bot (default: "Figment")
DATABASE_PATH=                # SQLite database path (default: ./data/bot.db)
LOG_LEVEL=                    # Logging level (default: info)
NODE_ENV=                     # production | development
```

## Key Conventions

### Code Style
- **Effective TypeScript** — strict mode, no `any`, prefer `unknown`, use branded types
  for IDs.
- **Doc comments** on all public APIs. Inline comments for non-obvious logic.
- Barrel exports via `index.ts` in each module directory.
- Zod for runtime validation of external inputs (Signal messages, API responses).

### Git & Workflow
- **Conventional Commits**: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`
- **ATDD**: Write acceptance tests first, then implement to make them pass.
- PR-based workflow with CI checks (lint, typecheck, test) required to merge.

### Project Structure

```
src/
  bot/            # Signal bot setup, message handling, rate limiting
  agent/          # Claude agent loop, system prompt, tool orchestration
  tools/          # Custom MCP tool definitions
  db/             # Drizzle schema, migrations, queries
  cron/           # Scheduled jobs (reminders, standups)
  config/         # Environment config, constants
  types/          # Shared TypeScript types
  utils/          # Shared utilities
mcp-servers/      # Git submodule: Kan, Outline, Radicale MCP servers
data/             # SQLite database (gitignored)
drizzle/          # Generated migrations
tests/            # Test files mirroring src/ structure
```

## MCP Server Integration

MCP servers are included as a git submodule and run as child processes managed by the
bot. Each server exposes tools via the Model Context Protocol that Claude can invoke
during the agent loop.

### Kan.bn Tools
Task and project management: list boards, create/update/delete cards, manage lists,
labels, checklists, comments, card members, search across workspace.

### Outline Tools
Knowledge base: search documents, create/update/delete documents, manage collections,
list comments, list revisions, manage users.

### Radicale Tools
Calendar and contacts: list/create/update/delete events, todos, contacts, calendars,
address books.

### Playwright Tools
Web automation: browser navigation, screenshots, form filling, element interaction.
Used for tasks that require web scraping or interaction with web UIs.

## Signal-Specific Considerations

These are areas where Signal differs from Telegram and will need adaptation:

- **No bot API** — Signal has no official bot API. We rely on signal-cli (unofficial).
- **Phone number identity** — Bots need a real phone number, not a bot token.
- **Group permissions** — Signal groups have admins; bot may need admin for full
  functionality.
- **Mentions** — Signal supports @mentions by UUID; need to map to user display names.
- **Reactions** — Signal supports emoji reactions; can be used for acknowledgments.
- **Disappearing messages** — Groups may have disappearing messages enabled; bot needs
  to handle this gracefully.
- **Rate limiting** — Signal is stricter about message frequency than Telegram.
- **No inline keyboards** — Signal does not support interactive buttons or menus.
- **No message editing** — Signal does not support editing sent messages (unlike
  Telegram).
- **Attachments** — Signal supports images, files, voice notes. API for these varies
  by framework choice.
