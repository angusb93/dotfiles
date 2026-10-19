#!/usr/bin/env bash
# headersHelper for the PostHog MCP server (Exhibition Co, EU region; the
# server routes by account). Reads the personal API key from 1Password at
# connect time so it never sits in ~/.claude.json, and asks for read-only
# mode, which removes every tool that creates, edits or deletes data.
set -euo pipefail
PATH="$PATH:/run/current-system/sw/bin:/opt/homebrew/bin"
export OP_SERVICE_ACCOUNT_TOKEN="$(<"$HOME/.config/op/service-account-token")"
token="$(op read --no-newline "op://6ozvud25wxpywiml26e3a53hxu/exco-posthog-key/credential")"
printf '{"Authorization":"Bearer %s","x-posthog-read-only":"true"}\n' "$token"
