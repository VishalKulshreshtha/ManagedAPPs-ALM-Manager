# ALM Flow (Local Mode)

## Phase 1: Check-only (no changes)

1. Validate CLI + auth
2. Resolve source environment (default dev first)
3. Resolve app in source environment
4. Inspect source app + dependencies
5. Preflight target connectors/policies
6. Produce exact execution command plan

## Phase 2: Execute (after confirmation)

1. Clone source app/project
2. Initialize target app
3. Recreate data sources in target
4. Refresh data source bindings
5. Apply supported app settings
6. Build and deploy target app
7. Validate app info and live URL

## Guardrails

- stop on first hard failure
- no delete operations unless explicitly requested
- no overwrite of existing migration workspace without explicit user confirmation

