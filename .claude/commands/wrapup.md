---
description: End-of-session wrap-up for UpNext — propose CHANGELOG entry, scan CLAUDE.md for staleness, then commit on approval.
---

You're closing out an UpNext coding session. Walk through this checklist exactly. Honor Carlos's standing rule: verify against code, show diffs before saving, never auto-commit without explicit approval.

## 1. Gather what changed

Run these in parallel:
- `git status` — untracked + working-tree state
- `git diff main` — every change vs main, committed + uncommitted (works in worktrees)
- `git log main..HEAD --oneline` — commits already on this branch
- `date +%Y-%m-%d` — today's date for the CHANGELOG header

If `git diff main` is empty AND there are no untracked files, stop. Tell the user there's nothing to wrap up.

## 2. Draft the CHANGELOG.md entry

Read CHANGELOG.md first to match the existing style. The pattern is:

```
## [YYYY-MM-DD] — Short Title

### Fixed/Added/Changed/Removed — Specific subject
- **Root cause:** …  (for bug fixes)
- **Fix:** …
- Other bullets as needed

### Files touched
- `path/to/file` — one-line description of what changed
```

Rules:
- Use today's actual date from step 1.
- Group multiple unrelated changes as separate `### Fixed/Added/...` sections under one date heading.
- Include only user-visible or behavior-affecting changes. **Skip:** comment-only edits, pure refactors, doc-only edits to CHANGELOG/CLAUDE itself.
- Mention any production deploys that happened (Firebase Hosting, Cloud Functions, Stripe dashboard changes) so the changelog matches what's actually live.

## 3. Scan CLAUDE.md for staleness

Re-read CLAUDE.md. Update it ONLY if one of these is true:
- A documented fact is now wrong (the code/product changed in a way that contradicts the doc)
- A new flow, surface, data field, or architectural piece now exists that future-Claude would need to know about
- A documented bug/gap was just resolved (remove or update the warning)

Do NOT update CLAUDE.md just because new code was written. Implementation details belong in CHANGELOG. CLAUDE.md is a snapshot of how the product currently works, not a log of how it got there.

## 4. Show diffs and ask for approval

Present in one message:
- The proposed CHANGELOG.md addition (as a diff)
- Any proposed CLAUDE.md edits (as diffs) — or "no CLAUDE.md changes needed" if clean
- A draft commit message (concise, why-focused, under 72 chars for the subject)

Do not save anything yet. Wait for explicit approval.

## 5. On approval — save and commit

1. Apply the CHANGELOG.md and CLAUDE.md edits
2. Stage files explicitly by name (do NOT use `git add -A` or `git add .`)
3. Create the commit with the approved message
4. Report the commit hash + a one-line summary

Do not push to remote unless the user explicitly asks.
