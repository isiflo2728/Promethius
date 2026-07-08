# Branching & release flow

This repo uses a company-style Git Flow. **Never commit straight to `main`.**

```
feature/*  ──►  develop  ──►  staging  ──►  main
 your work      testing /      final        PRODUCTION
                integration    pre-prod      (protected)
```

## The branches

| Branch       | Purpose                                              | Protected |
|--------------|------------------------------------------------------|-----------|
| `main`       | **Production.** Only proven, released code.          | ✅ Yes     |
| `staging`    | Final pre-prod mirror. Last check before a release.  | ✅ Yes     |
| `develop`    | Integration/testing. Default branch; features land here. | ❌ No  |
| `feature/*`  | Day-to-day work. One branch per feature/fix.         | ❌ No     |

## Everyday workflow

1. **Start work** from `develop`:
   ```bash
   git checkout develop && git pull
   git checkout -b feature/short-description
   ```
2. **Commit & push**, then open a PR into **`develop`**.
   - Not done yet? Open it as a **draft**.
3. **Merge to develop** once it builds and the PR is green.
4. **Promote for release:** PR `develop → staging`, verify, then PR `staging → main`.

## Rules on protected branches (`main`, `staging`)

- No direct pushes — every change comes through a Pull Request.
- No force-pushes, no branch deletion.
- Linear history (squash or rebase merges).
- You can merge your own PR (no outside approval required — solo project).

## Branch naming

- `feature/…` — new work (`feature/sidebar-nav`)
- `fix/…` — bug fixes (`fix/composio-timeout`)
- `hotfix/…` — urgent prod fix, branched from `main`
