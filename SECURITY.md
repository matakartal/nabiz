# Security

Please report security problems privately, through GitHub's **Report a vulnerability** button on the Security tab, rather than in a public issue.

## What Nabız touches

- **Processes:** it reads your own user's processes, never other users' or the system's, and never asks for administrator rights.
- **AI limits (off by default):** for providers you turn on, Nabız reads the sign-in their official CLI keeps on your Mac:
  - Claude Code's Keychain item, after macOS asks you,
  - `~/.codex/auth.json`,
  - `~/.gemini/oauth_creds.json`.

  It sends that sign-in only to the same provider's usage endpoint. It never stores, refreshes, logs or forwards it.
- **Other network requests:** exchange rates from frankfurter.dev and market prices from Hyperliquid's public API. Neither request carries anything about you.
