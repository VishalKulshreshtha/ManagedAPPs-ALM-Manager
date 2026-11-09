# Copilot Code ALM Migration Package

For complete context and ALM rationale, see `README.md`.
For execution phases and troubleshooting, see:
- `docs/ALM-FLOW.md`
- `docs/TROUBLESHOOTING.md`

This package works for both:

- **Local Copilot Code sessions** (your machine)
- **Copilot cloud agent sessions** (GitHub-hosted ephemeral runner)

## 1) Add these files to your repository

Copy the package contents into your repo root so you have:

- `.github/workflows/copilot-setup-steps.yml`
- `.github/prompts/alm-migrate.prompt.md`
- `scripts/ms-app-alm-migrate.ps1`

## 2) Commit and push

The setup workflow must exist on your **default branch** for cloud agent sessions to use it.

## 3) Configure secrets/variables (if needed)

If your tooling needs auth/proxy/private feeds, add those in the repository `copilot` environment (Settings -> Environments -> copilot).

## 4) Use in Copilot Code

### Option A: Reusable prompt (recommended)

In Copilot Chat, invoke the prompt file and provide:

- app name or app ID
- target environment ID
- mode (`check-only` first, then `execute`)
- source environment ID (optional; auto-detected from personal/default developer context first)

### Option B: Run script directly

```powershell
pwsh ./scripts/ms-app-alm-migrate.ps1 `
  -AppIdentifier "<app name or app id>" `
  -TargetEnvironmentId "<target-env-guid>" `
  -Mode check-only
```

Then execute:

```powershell
pwsh ./scripts/ms-app-alm-migrate.ps1 `
  -AppIdentifier "<app name or app id>" `
  -TargetEnvironmentId "<target-env-guid>" `
  -Mode execute `
  -TargetDisplayName "<new target app name>"
```

The script now inventories and migrates dependent app resources before deploy:
- source data sources (`ms app show` -> `ms app add data-source` in target)
- source app settings (supported scalar settings such as `show-header`)
- connector availability preflight in target environment

## Local vs Cloud guidance

- **Local**: Works immediately if `ms` CLI is installed and you are authenticated.
- **Cloud**: Works after `.github/workflows/copilot-setup-steps.yml` is on default branch so agent auto-installs `@microsoft/managed-apps-cli`.
