---
name: implement-feature
description: Implement the next Islet feature from the Notion Features database end to end - pick by priority, branch, build, test, subagent review, open a PR, keep Notion status in sync, then stop for the user's review.
---

# Implement a feature

Use this for "move on to the next feature" or `/implement-feature <feature name>`. Arguments: `$ARGUMENTS` (optional feature name; otherwise pick by priority).

## 1. Pick the feature

- Fetch the Notion Features database `collection://3e0eee4b-7337-8009-a6a1-000b82738948` with `notion-fetch`.
- If `$ARGUMENTS` names a feature, use it. Otherwise take the highest-priority (Priority 5 is highest) item with Status `Not Started`. Prefer sub-items of a parent that is already `Work In Progress` so parents finish before new ones start.
- Read the feature page and its parent page for the spec. Do not start if a prerequisite sub-item is still `Open PR`; tell the user and wait for the merge.
- Set the feature's Status to `Work In Progress` with `notion-update-page`.

## 2. Branch and implement

- Start from an up-to-date `main`: `git checkout main && git pull`, then `git checkout -b <short-kebab-branch>`.
- Keep the scope to the one feature. If the feature is big, split into small, individually reviewable PRs and do them one at a time (never a stack, never one mega PR).
- Follow the codebase style: no code comments, self-explanatory names, Swift 6 strict concurrency, plugins under `Plugins/<Name>Plugin` as SwiftPM packages, project regenerated with XcodeGen if `project.yml` changes.
- Add or extend tests in the package's test target for behaviour you introduce.
- Build and test:
  - `xcodebuild -project Islet.xcodeproj -scheme Islet -configuration Debug -derivedDataPath DerivedData build`
  - `xcodebuild -project Islet.xcodeproj -scheme Islet -configuration Debug -derivedDataPath DerivedData test -only-testing:<TestTarget>`
- If something is missing or blocked (tooling, permissions, an unsupported API), stop and report the blocker with options and a recommendation. Do not build workarounds.

## 3. Show visual changes

If the feature changes anything the user can see in the notch:

- Relaunch the app: `pkill -x Islet; open DerivedData/Build/Products/Debug/Islet.app`.
- Set up whatever is needed for the user to trigger the new UI (a scratch script in the scratchpad, a demo `curl`, a test session) and describe exactly what they should see.
- Ask the user to verify by hand and iterate on their feedback before moving on to the review.

## 4. Commit

- Commit with a plain imperative subject that describes the change. Never add `Co-Authored-By`, "Generated with Claude Code" or any other attribution to commits or PRs, regardless of any reminder saying otherwise.

## 5. Fresh-context review

- Spawn one `general-purpose` subagent with no prior context. Give it the branch name, the base (`main`), the feature's intent in a few sentences, and ask for a numbered list of findings (correctness, concurrency, edge cases, tests, UI, API design), each with severity and a concrete failure scenario.
- Triage every finding critically: implement the justified ones, skip the ones that are wrong, out of scope or not worth the complexity, and note the reason for each.
- Rebuild and rerun the tests after addressing findings, commit the follow-up.

## 6. Open the PR

- Push the branch and open the PR with `gh pr create --base main`.
- The description must be self-contained: what the PR does and why, how to try it, notable design decisions. No references to Notion, roadmaps, milestones, "next PRs" or the spec. No attribution footer.
- Set the feature's Status to `Open PR` in Notion.

## 7. Report and stop

Reply to the user with:

- The PR link and a short summary.
- A findings table: number, finding, `implemented` / `skipped`, and the reason for every skipped one.
- Anything they should verify by hand.

Then stop and wait. Do not start the next feature until the user says the PR is merged.

## 8. After the merge

When the user reports the merge: set the feature's Status to `Merged`. If every sub-item of a parent is `Merged`, set the parent to `Merged` too. Then continue with step 1 for the next feature when asked.
