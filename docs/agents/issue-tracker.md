# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --json title,body,labels,comments --jq '...'`. **Important:** this repo has GitHub Projects (classic) linkage that makes the plain `gh issue view <number>` form fail with a GraphQL deprecation error. Always use the `--json` form. Filtering comments and labels via `jq` works on the `--json` output.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`. **Use `gh issue edit` even for PRs** — `gh pr edit --add-label` hits the same Projects (classic) GraphQL deprecation error on this repo. PR numbers and issue numbers share the same labels API in GitHub, so `gh issue edit <pr-number> --add-label X` works on a PR.
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.
