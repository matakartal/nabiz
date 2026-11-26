# Security

## Reporting a problem

Please report security problems **privately**, through [Report a vulnerability](../../security/advisories/new) on the
Security tab — never in a public issue, discussion or pull request. Include what you found, how to reproduce it, and
what an attacker could do with it.

- You'll get an answer within a week. A confirmed problem is fixed in a release as soon as possible, and you're
  credited in the release notes unless you'd rather not be.
- Only the [latest release](../../releases/latest) gets security fixes; Nabız updates itself from the panel.
- Please give us a reasonable time to ship a fix before talking about it publicly.

In scope: anything that lets another app, a web page, an AI model or a file make Nabız read, change, delete or send
something it shouldn't — for example through the MCP socket, the launcher, the AI chat or the clean-up.

## What Nabız touches

- **Processes:** your own user's processes only, never other users' or the system's. Nabız never asks for
  administrator rights.
- **AI limits (off by default):** for providers you turn on, Nabız reads the sign-in their official CLI keeps on your
  Mac — Claude Code's Keychain item (after macOS asks you), `~/.codex/auth.json`, `~/.gemini/oauth_creds.json` — and
  sends it only to the same provider's usage endpoint. It never stores, refreshes, logs or forwards it.
- **AI chat:** your messages go to the provider you pick through its own CLI, started with no file or command tools;
  Claude, Codex and Grok get web search only when it's on. Pasted and attached text is treated as material, never as
  instructions. Apple's on-device model never leaves the Mac. Chats are encrypted on disk with a key in the Keychain.
- **MCP server (off by default):** a Unix socket only your user can open (mode 600, peer checked). Restart, shut down,
  log out, quitting all apps and emptying the Trash are never exposed; the clipboard only if you allow it; recordings
  export only into Desktop, Movies, Downloads or Documents and never over an existing file.
- **Clean-up:** lists everything with its size, asks first, checks each item again right before acting, and never
  touches source code, uncommitted work or ignored files that don't rebuild themselves (like `.env`).
- **Network:** exchange rates (frankfurter.dev), market prices (Hyperliquid), weather (Open-Meteo, the chosen city's
  coordinates only), update checks (GitHub), and what you ask for (web search, video downloads, speed test). None of
  these carries anything about you beyond what the request itself needs.
- **Stored on disk:** the clipboard history and AI chats are encrypted with a key in your Keychain; crash reports stay
  on your Mac until you choose to send one.
