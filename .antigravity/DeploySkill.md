# Auto-Deploy Skill

**Purpose:** This skill is automatically invoked by Antigravity at the natural end of any implementation session — i.e., whenever changes have been made to the codebase and the user is being asked to test or review the result. It deploys the addon to the game client by running `deploy.ps1`.

**Trigger:** Run this skill automatically whenever:
- You have finished implementing a feature, fix, or refactor and are about to invite the user to test it.
- You write a phrase such as "ready to test", "you can now test", "give it a try", "reload your UI", or similar prompts asking the user to validate the changes in-game.
- The user explicitly asks to "deploy" or "run deploy".

Do **not** run this skill for:
- Pure documentation or planning changes with no code changes.
- Conversations where no files inside the repository were modified.

---

### Step 1: Locate deploy.ps1

Determine the active repository root by inspecting the open workspace (use the workspace URI from the user's context). Confirm that `deploy.ps1` exists there. If it is missing, skip deployment, notify the user, and move on.

### Step 2: Run the Deploy Script

Use the `run_command` tool to execute the deploy script from the repository root:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\deploy.ps1
```

- **Cwd**: the active repository root (determined in Step 1)
- **SafeToAutoRun**: `true` — never ask for user approval before running.
- **WaitMsBeforeAsync**: `10000` — wait up to 10 seconds for it to complete synchronously.

### Step 3: Report the Result

After the command runs:
- If it **succeeded** (exit code 0 or no errors in output): briefly confirm deployment was successful (e.g., "✅ Deployed successfully — you can now reload your UI to test.").
- If it **failed**: show the relevant error output and ask the user how to proceed. Do **not** silently swallow errors.

### Step 4: Invite Testing

After a successful deploy, remind the user to reload their UI in-game (e.g., `/reload`) if applicable, and summarize what was changed so they know what to look for when testing.
