# Troubleshooting (Local Copilot Code ALM Migration)

## `ms` command not found

Install CLI:

```bash
npm install -g @microsoft/managed-apps-cli
```

Restart terminal and verify:

```bash
ms --version
```

## Authentication check fails

Run:

```bash
ms auth login
ms auth status
```

If multiple accounts exist, switch account:

```bash
ms auth switch --account <email>
```

## App not found

If source environment is not provided, the flow first tries default/personal environment.  
If still unresolved, pass explicit source environment:

```powershell
pwsh ./scripts/ms-app-alm-migrate.ps1 `
  -AppIdentifier "<app>" `
  -SourceEnvironmentId "<source-env-guid>" `
  -TargetEnvironmentId "<target-env-guid>" `
  -Mode check-only
```

## Multiple app matches

Use exact app ID instead of display name.

## Connector missing in target environment

The script fails fast when required connectors are unavailable in target.  
Fix by enabling/allowing the connector in target environment policy, then rerun.

## Data source add fails

Common causes:

- connection ID does not exist in target environment
- DLP/ACP policy blocks connector operation
- source dependency needs manual connection creation first

Run `check-only` again and address the failing dependency.

## Build/deploy failure

Use:

```bash
ms app build-status --app <target-app-name> --show-log
```

Resolve build errors, then rerun execute mode.

