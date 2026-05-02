---
description: Run a parallel swarm of specialized code reviewers (power, performance, testability, readability, structure, architecture, security, privacy, catch-all) against the current branch and synthesize their findings.
argument-hint: "[source-branch] [target-ref]"
---

# Review Swarm

Run all specialized review agents in parallel against a branch's changes, then synthesize a consolidated report.

## Usage

```
/review-swarm                                  # interactive branch selection
/review-swarm feature/my-branch                # review branch against default target
/review-swarm feature/my-branch main           # review branch against explicit target
/review-swarm feature/my-branch abc1234        # review branch against a commit ref
```

## Procedure

### 1. Parse arguments

The user may provide zero, one, or two arguments:
- **Two arguments**: `$1` is the source branch, `$2` is the target ref. Skip to step 4.
- **One argument**: `$1` is the source branch. Prompt for target (step 3).
- **No arguments**: Prompt for source (step 2) and target (step 3).

### 2. Select source branch (if not provided as argument)

First, gather data by running these bash commands:

```bash
CURRENT=$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD)

git fetch --prune --quiet 2>/dev/null

git for-each-ref --sort=-committerdate \
  --format='%(refname:strip=3)|%(authorname)|%(committerdate:relative)' \
  refs/remotes/origin/ \
  | grep -v -E '^(main$|master$|develop$|release/|HEAD$)' \
  | head -20
```

Then use the **AskUserQuestion** tool to prompt the user:
- **Option 1**: The current branch — use the branch name as the label with "(Recommended)", description "Your current checked-out branch"
- **Option 2**: "Browse recent branches" — description "Show recently changed branches to pick from"

The user can always select "Other" to type in any branch name.

If the user selects **"Browse recent branches"**: print the full list as a formatted table (branch name, author, date), then use a second **AskUserQuestion** with up to 4 of the most recent branches as options (branch name as label, `{author}, {date}` as description). The user can select one or use "Other" to type any branch name from the list.

Store the result as `SOURCE_BRANCH`.

### 3. Select target branch (if not provided as argument)

Determine the default target:
1. Check the project's `CLAUDE.md` for a specified main branch.
2. Fall back to: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`
3. Fall back to `main`.

Gather recent main/release branches:
```bash
git for-each-ref --sort=-committerdate \
  --format='%(refname:strip=3)|%(committerdate:relative)' \
  refs/remotes/origin/ \
  | grep -E '^(main|master|release/)' \
  | head -10
```

Use the **AskUserQuestion** tool:
- **Option 1**: The default target branch (e.g. `main`) — label with "(Recommended)", description "Default branch"
- **Option 2**: "Browse main/release branches" — description "Show recent main and release branches to pick from"

The user can select "Other" to type in any branch name or commit ref.

If the user selects **"Browse main/release branches"**: print the full list as a formatted table (branch name, date), then use a second **AskUserQuestion** with up to 4 of the most recent branches as options (branch name as label, relative date as description). The user can select one or use "Other" to type any branch name or commit ref.

Store the result as `TARGET_REF`.

### 4. Capture the diff

For the target ref: always try `origin/{TARGET_REF}` first. If that fails (e.g. `git rev-parse --verify origin/{TARGET_REF}` exits non-zero), fall back to using the ref as-is. This ensures `main` resolves to `origin/main` rather than a stale local branch.
For the source: if it matches the current checked-out branch, use `HEAD`. Otherwise, try the name as-is first (local branch), and if that fails, try `origin/{source}`.

```bash
git diff "${TARGET_REF}...${SOURCE_BRANCH}" > /tmp/review-swarm.diff
git diff --name-only "${TARGET_REF}...${SOURCE_BRANCH}" > /tmp/review-swarm.files
```

### 5. If the diff is empty, report that there is nothing to review and stop.

### 6. Spawn all nine reviewers in a single assistant message

This is what gives you parallelism — they must be in one message, not sequential calls. Use the `Agent` tool with these `subagent_type` values:
- `power-reviewer`
- `performance-reviewer`
- `testability-reviewer`
- `readability-reviewer`
- `code-structure-reviewer`
- `swift-architecture-reviewer`
- `security-reviewer`
- `privacy-reviewer`
- `catch-all-reviewer`

Pass each one the same context block:

```
You are reviewing a PR. Check the project's CLAUDE.md (if one exists) for project-specific conventions, architecture patterns, and style guidelines.

The diff is at /tmp/review-swarm.diff.
The list of changed files is at /tmp/review-swarm.files.

Read the diff. Apply your specialty's review process. Use Read/Grep/Glob to inspect surrounding code or check for tests as needed. Return your findings in the structured output format defined in your agent definition.

Be concrete. Cite `file:line`. Suggest fixes. If nothing is wrong, say so plainly.
```

### 7. Wait for all reviewers to return, then synthesize.

## Synthesis Format

After all nine reviewers report back, consolidate as:

```
# Review Swarm Report

**Source**: <source-branch>  **Target**: <target-ref>  **Files changed**: <count>

## 🚨 Critical Blockers
[CRITICAL/DO_NOT_MERGE findings from any reviewer, grouped by lane.
Include reviewer name, file:line, the finding, and the suggested fix.]

## ⚠️ Warnings
[HIGH/WARNING findings worth discussing before merge.]

## 💡 Suggestions
[MEDIUM/LOW/SUGGESTION findings — nice-to-haves.]

## ✅ Clean Lanes
[Reviewers that returned PASS / no findings, listed compactly.]

## Per-Reviewer Recommendations
- power-reviewer: [MERGE | REVISE | MERGE_WITH_CAVEAT]
- performance-reviewer: [...]
- testability-reviewer: [... — also note missing test coverage]
- readability-reviewer: [...]
- code-structure-reviewer: [MERGE | REVISE | MERGE_WITH_CAVEAT]
- swift-architecture-reviewer: [APPROVED | NEEDS_REVISION]
- security-reviewer: [MERGE | REVISE | DO_NOT_MERGE]
- privacy-reviewer: [MERGE | REVISE | DO_NOT_MERGE]
- catch-all-reviewer: [MERGE | REVISE | MERGE_WITH_CAVEAT]

## 🎯 Overall Recommendation
[DO NOT MERGE | REVISE | MERGE WITH CAVEATS | MERGE]

[One-paragraph rationale.]
```

## Notes

- Each reviewer runs in its own context window — they do not see each other's output. Only this synthesis sees everything.
- If a reviewer fails or returns an unusable response, note it in the synthesis rather than silently dropping it.
- For follow-up questions about any specific finding, the user can address them in the main conversation — the synthesis is here in your context.
