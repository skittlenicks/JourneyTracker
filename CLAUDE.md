# Journey Tracker

## Commits

- Never add Claude attribution to a commit or PR: no `Co-Authored-By: Claude`
  trailer, no "Generated with Claude Code" line, no session link. This is a
  rule for every commit in this repo. `.claude/settings.json` turns the
  default attribution off.
- Commit as `skittlenicks` with the GitHub no-reply email
  `138069357+skittlenicks@users.noreply.github.com`, never a real address.
  A fresh clone needs `git config user.name` and `user.email` set to these.

## Before changing code

Read the status rules in `specs/journey-tracking-spec.md`: don't change
anything tagged `VERIFIED` unless asked, and never mark an item `VERIFIED`
yourself.
