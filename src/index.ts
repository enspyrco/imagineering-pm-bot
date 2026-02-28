import "dotenv/config";
import { initEnv, getEnv } from "./config/env.js";

function main(): void {
  // Validate environment first — fails fast on bad config
  initEnv();
  const env = getEnv();

  console.log(`Starting ${env.BOT_NAME} (imagineering-pm-bot)...`);
  console.log(`  Environment: ${env.NODE_ENV}`);
  console.log(`  Log level:   ${env.LOG_LEVEL}`);
  console.log(`  Database:    ${env.DATABASE_PATH}`);
  console.log(`  Signal API:  ${env.SIGNAL_API_URL}`);
  console.log(`  Playwright:  ${String(env.PLAYWRIGHT_ENABLED)}`);

  // TODO: Initialize database (Phase 1)
  // TODO: Register custom tools (Phase 2)
  // TODO: Initialize MCP servers (Phase 2)
  // TODO: Start Signal message handler (Phase 3)
  // TODO: Start cron schedulers (Phase 4)

  console.log(`${env.BOT_NAME} is ready!`);
}

try {
  main();
} catch (err: unknown) {
  console.error("Failed to start bot:", err);
  process.exit(1);
}

// Graceful shutdown — async because future phases add awaitable cleanup
// eslint-disable-next-line @typescript-eslint/require-await
async function shutdown(): Promise<void> {
  console.log("Shutting down...");
  // TODO: Shutdown MCP servers (await mcpManager.shutdown())
  // TODO: Close database connection (await db.close())
  process.exit(0);
}

process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());
