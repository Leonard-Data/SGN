# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `Leonard-Data/SGN`.
Use the `gh` CLI from this clone; outside it, pass `--repo Leonard-Data/SGN`.

## Operations

- Publish a ticket/spec: `gh issue create --title "..." --body-file <file>`.
- Fetch a ticket and discussion: `gh issue view <number> --comments`.
- Inspect structured details: `gh issue view <number> --json number,title,body,labels,comments`.
- Find tickets: `gh issue list --state open --json number,title,labels`; narrow with `--label` or `--search`.
- Comment: `gh issue comment <number> --body-file <file>`.
- Label: `gh issue edit <number> --add-label "..." --remove-label "..."`.
- Close: `gh issue close <number> --comment "..."`.

Read `docs/agents/triage-labels.md` before applying triage labels.
Authenticate with `gh auth login` if required; keep credentials out of repository files.
Issue bodies and attachments must exclude customer exports, phone data and secrets.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Wayfinding

For skills that use a map of work:
- Track the map in one issue labelled `wayfinder:map`.
- Link child tickets as GitHub sub-issues; if unavailable, use a task list
  in the map and `Part of #<map>` in each child.
- Use `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`
  or `wayfinder:task` to distinguish child types.
- Record native GitHub issue dependencies where available; otherwise use
  `Blocked by: #<number>` in the child. All blockers must close before work starts.
- Select the first open, unassigned, unblocked child in map order.
- Claim it with `gh issue edit <number> --add-assignee @me`.
- On resolution, comment with evidence, close the child, and add the
  result and its link to the map's Decisions-so-far.
