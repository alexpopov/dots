---
name: git-rebase-todo
description: Drive an interactive rebase by editing the todo list as a plain file — reorder, drop, squash, reword, or mark commits for edit. Use when you need to restructure a commit stack (not just amend commits in place, which is git-prev-next's job), or when `git rebase -i` would otherwise require an interactive $EDITOR you cannot drive.
---

# Interactive rebase without an editor

`git rebase -i` normally shows the todo list in `$EDITOR`. An agent has no
editor, so the usual workaround is `GIT_SEQUENCE_EDITOR="sed ..."` one-liners —
fine for a blanket `s/^pick/edit/`, useless for "move commit 4 above commit 2".

`git todo` (`~/dots/bin/scripts/git-todo`, on PATH via `~/.local/bin/scripts`)
pauses the rebase and hands you the todo list as an ordinary file.

## Workflow

```bash
git todo start HEAD~5     # rebase paused BEFORE any commit; prints the todo
git todo path             # -> the todo file; edit it with read/write/edit
git todo apply            # git re-parses it (rejects a malformed todo)
git rebase --continue     # run it
```

`start` works by inserting `break` as the first todo line, so nothing has been
replayed yet and every commit is still reorderable. It passes `--update-refs`,
so stacked branches follow.

Between `start` and `apply` the todo file is just text. Reorder lines to reorder
commits (top = oldest, applied first). Change the verb to restructure:

| verb | effect |
|------|--------|
| `pick <sha> # subject` | keep as-is |
| `reword` | keep the change, stop to rewrite the message |
| `edit` | stop after applying, so you can amend content |
| `squash` | fold into the previous commit, combine messages |
| `fixup` | fold into the previous commit, discard this message |
| `drop` (or delete the line) | remove the commit |
| `break` | stop here |

## Rules

- **`git todo apply` after every edit.** Writing the file alone works but skips
  git's validation; `apply` runs it through `git rebase --edit-todo`, so `pcik`
  is an error instead of a silently dropped commit.
- **Never hardcode `.git/rebase-merge/git-rebase-todo`.** Wrong inside a
  worktree. Use `git todo path` (`git rev-parse --git-path`).
- **Run `git todo status` often.** It is easy to forget you are mid-rebase
  across tool calls; it reports pending step count and current HEAD.
- Working tree must be clean before `start`.
- Bail out with `git rebase --abort` — it restores the original HEAD.

## When NOT to use this

Amending a series of commits in place (adding `Differential Revision:` lines,
fixing messages, folding edits into older commits) — use **git-prev-next**
instead, which walks the stack for you. Reach for `git todo` when the *shape* of
the stack changes: order, count, or which commits get squashed together.

## Under the hood

`GIT_SEQUENCE_EDITOR` is handed the todo path as `$1`, so any in-place file
editor is a valid "sequence editor" — that is the entire mechanism, and it is
what `git prev` uses too:

```bash
GIT_SEQUENCE_EDITOR='sed -i "1i break"' git rebase -i --update-refs <base>  # start paused
GIT_SEQUENCE_EDITOR=true git rebase --edit-todo                             # re-read after editing
```
