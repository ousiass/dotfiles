# Notifications (`.sweep/notify.url`)

**Read this file only when `.sweep/notify.url` exists.** If it does not, `sweep_notify` is always a no-op, so you may ignore every call site.

Can notify a Slack / Discord / ntfy.sh that differs per project.

**Setup:** save a one-line URL at the repository root (`.gitignore`d):

```bash
echo "https://hooks.slack.com/services/T0XXX/B0XXX/xxxx" > .sweep/notify.url
```

**Automatic destination detection:** chosen by the URL's string pattern:

| String contained in URL | Service | Format |
|---|---|---|
| `hooks.slack.com` | Slack | `{"text": "..."}` JSON POST |
| `discord.com/api/webhooks` | Discord | `{"content": "..."}` JSON POST |
| `ntfy.sh` / other | ntfy-compatible | Plain-text POST body + `Title` / `Priority` headers |

**Notification timing:**

| Event | Notification content | Emoji |
|---|---|---|
| Batch merge completed (right after Issue close) | `Merged #<n> (PR #<P>, <duration>)` | `:white_check_mark:` |
| CI definitive failure detected | `CI failed on PR #<P> (attempt <k>/3): <checks>` | `:warning:` |
| Sweep gave up (CI respawn limit reached / agent failure limit reached) | `Manual intervention needed: #<n> — <reason>` | `:rotating_light:` |
| Final PR CI green (single-pr mode) | `Ready to merge: PR #<P>` | `:white_check_mark:` |
| Whole sweep done (completion-report phase) | `Sweep done: <merged> merged, <failed> failed, elapsed <duration>` | `:checkered_flag:` |

**Implementation of the send function:**

```bash
sweep_notify() {
  local title="$1" msg="$2" emoji="${3:-}"
  local url_file="${SWEEP_DIR:-.sweep}/notify.url"
  [[ -f "$url_file" ]] || return 0  # URL not set → silent
  local url
  url=$(head -n1 "$url_file")
  [[ -z "$url" ]] && return 0

  case "$url" in
    *hooks.slack.com*)
      curl -sf -X POST -H 'Content-Type: application/json' \
        --data "$(jq -nc --arg t "$emoji $title: $msg" '{text:$t}')" \
        "$url" >/dev/null 2>&1 || true
      ;;
    *discord.com/api/webhooks*)
      curl -sf -X POST -H 'Content-Type: application/json' \
        --data "$(jq -nc --arg c "$emoji **$title**: $msg" '{content:$c}')" \
        "$url" >/dev/null 2>&1 || true
      ;;
    *)
      curl -sf -X POST -H "Title: $title" -H "Tags: robot" \
        -d "$msg" "$url" >/dev/null 2>&1 || true
      ;;
  esac
}
```

Notification failures (network errors etc.) do not stop the sweep itself (`|| true`).
