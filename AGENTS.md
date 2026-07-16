# NOTR Repo Rules

## Full Send

In this repo, a "full send" means full send. The work is not done at code changes, not done at a local build, and not done at "the release should pick it up."

A full send includes all of the following:

1. Implement the requested change in the repo.
2. Update release metadata and docs that define the shipped state when needed.
3. Commit the entire required change set to git. Do not leave required release, docs, packaging, or website-triggering changes uncommitted.
4. Push the full change set to GitHub.
5. Build the Release app artifact.
6. Package the current `NOTR.dmg`.
7. Upload the current `NOTR.dmg` to the live GitHub release path.
8. Make sure the GitHub-hosted release state is live.
9. Update the local DMG/build artifacts so this Mac is using the current shipped build, not a stale previous package.
10. Install the built app to `/Applications/NOTR.app` on this Mac.
11. Launch the installed app.
12. Verify the live installed app from concrete evidence, not assumption.

Required verification evidence for a full send:

- the installed app log must show `/Applications/NOTR.app`
- the installed app log must show the expected version/build
- the installed app log must show the requested behavior is live when that behavior can be exercised locally
- any failure in build, packaging, upload, install, launch, or verification must be surfaced immediately

Do not call something a full send if it only compiles, only ships a commit, only pushes code, only uploads a DMG, or only assumes GitHub release propagation happened without verifying the live state.
