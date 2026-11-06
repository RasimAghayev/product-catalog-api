# Git hooks

`pre-commit` runs a `gitleaks` secret scan over your staged changes before
each commit (local `gitleaks` binary if installed, otherwise a disposable
Docker container — no new project dependency added).

## Enable (once per clone)

```sh
git config core.hooksPath .githooks
```

Not enabled automatically because `core.hooksPath` is a local, per-clone
git config value — there is no portable way for a repo to force it on
checkout. CI runs the same kind of scan as a required job (Phase 10), so a
secret that slips past a clone without the hook enabled is still caught
before merge.
