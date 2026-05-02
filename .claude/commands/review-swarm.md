---
description: Run a parallel swarm of specialized code reviewers (power, performance, testability, readability, structure, architecture, security, privacy, catch-all) against the current branch and synthesize their findings.
argument-hint: "[base-ref]"
---

# Review Swarm

Run all specialized review agents in parallel against the current branch's changes, then synthesize a consolidated report.

## Usage

```
/review-swarm
/review-swarm main
/review-swarm develop
```

If no `base-ref` is provided, detect the repository's default branch (`main`, `master`, `develop`, etc.) using `git symbolic-ref refs/remotes/origin/HEAD` or ask the user. If the ref is a remote branch, we should ensure we're referencing the version on the remote -- usually accomplished by appending `origin/` on the branch name.

## Procedure

1. **Determine the base ref**:
   ```bash
   BASE_REF="${1:-$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')}"
   ```
   If detection fails and no argument was provided, ask the user which base branch to diff against.

2. **Capture the diff** against the base ref:
   ```bash
   git diff "$BASE_REF"...HEAD > /tmp/review-swarm.diff
   git diff --name-only "$BASE_REF"...HEAD > /tmp/review-swarm.files
   ```
   Also capture the list of changed files so each reviewer can scope its work.

3. **If the diff is empty**, report that there is nothing to review and stop.

4. **Spawn all nine reviewers in a single assistant message** (this is what gives you parallelism — they must be in one message, not sequential calls). Use the `Agent` tool with these `subagent_type` values:
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

5. **Wait for all reviewers to return**, then synthesize.

## Synthesis Format

After all nine reviewers report back, consolidate as:

```
# Review Swarm Report

**Base**: <base-ref>  **Head**: <current branch>  **Files changed**: <count>

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
