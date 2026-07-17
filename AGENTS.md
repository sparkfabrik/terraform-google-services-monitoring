# AGENTS.md

## Project Overview

Terraform module that provisions Google Cloud Monitoring alert policies and uptime checks for a curated set of GCP and Kubernetes services.

- **Authoritative description and supported services list:** see `README.md` (top section, above the `<!-- BEGIN_TF_DOCS -->` marker).
- **Full input/output/resource/module inventory:** the terraform-docs–generated table between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` in `README.md`. Regenerate with `make generate-docs` rather than reading individual `.tf` files.
- **Module layout at a glance:**
  - One top-level `*.tf` file per service at the repo root.
  - Cross-cutting reusable logic lives under `modules/<submodule>/`.
  - Canonical usage example: `examples/main.tf` (consumed by lint with `examples/test.tfvars`).

**Tech stack:**

- Terraform — required version declared in `versions.tf`.
- Providers — declared in `versions.tf`; latest applied version is recorded in the terraform-docs block of `README.md`.
- Docker-based tooling — TFLint, tfsec, terraform-docs. Pinned image tags in `Makefile`.
- GitHub Actions — workflows under `.github/workflows/`.
- Renovate — config in `renovate.json`.
- OpenSpec — scaffolded under `openspec/` (see "OpenSpec Change Management" below).

## Setup

This module is not deployed standalone — it is consumed by downstream Terraform stacks. For local development you need Docker and `make`. Discover available targets:

```bash
make help 2>/dev/null || grep -E '^[a-zA-Z_-]+:' Makefile
```

All linting, scanning, and doc generation run in containers pinned by the `Makefile` — no local Terraform, TFLint, tfsec, or terraform-docs install is required.

To test changes end-to-end, point a downstream Terraform stack at your branch:

```hcl
module "example" {
  source = "github.com/sparkfabrik/terraform-google-services-monitoring?ref=<your-branch>"
  # ...
}
```

## Key Conventions

- **Docker-only tooling.** Never install TFLint, tfsec, or terraform-docs locally — always use the `make` targets so versions stay pinned to the variables declared at the top of `Makefile`.
- **One `.tf` file per service** at the repo root. Look at the existing top-level files for the pattern (`ls *.tf`). Add a new service by creating a new top-level file plus a matching variable in `variables.tf`. Do not co-locate unrelated resources.
- **Variable structure.** Each service input is a single `object({...})` variable with `optional(...)` sub-attributes and sensible defaults. Inspect `variables.tf` for the established shape before adding a new input — match the patterns already in use (e.g., `enabled`, `project_id`, `notification_channels`).
- **README is generated.** The section between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` in `README.md` is owned by terraform-docs (config in `.terraform-docs.yml`). Never hand-edit that region — run `make generate-docs` after touching variables, outputs, or resources.
- **Migration notes live in `UPGRADING.md`.** The split is: `CHANGELOG.md` says _what_ changed, `UPGRADING.md` says _how_ to migrate. Rules:
  - Every breaking change gets a short one-line CHANGELOG bullet that links to `UPGRADING.md`. Never inline tables, config examples, or multi-paragraph migration text in the CHANGELOG.
  - Add a matching section to `UPGRADING.md` under `## Unreleased`, newest release first. When a release is tagged, rename `## Unreleased` to the version number in the same commit that cuts the CHANGELOG version.
  - A section contains, in order: what breaks and why it fails (or doesn't fail) at plan time, an old-to-new field mapping table when more than one field is involved, a before/after configuration snippet with values carried over verbatim, a verification step stating the expected `terraform plan` outcome, and any pitfalls consumers can hit during migration (e.g. Terraform silently discards unknown object attributes, so leftover legacy fields fall back to defaults without an error).
  - Only changes that require consumer action belong in `UPGRADING.md`. Additive or internal changes stay CHANGELOG-only.
- **Examples.** `examples/main.tf` is the canonical usage reference and is consumed by `tflint` / `tfsec` via `examples/test.tfvars`. Keep both in sync with new inputs.
- **Submodules.** Reusable cross-service logic lives under `modules/<name>/`. Check `ls modules/` for what currently exists before introducing a new submodule.
- **No state in this repo.** This module never holds Terraform state — see `.gitignore` for the ignored patterns.

## Code Style

- **Terraform**: TFLint configured in `.tflint.hcl`. Inspect that file for the active rule set rather than relying on a copy here.
- Standard module layout: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` at the root; one resource group per service file.
- Snake_case for resource names, variable names, and module keys. Object variables always use `optional(...)` with defaults rather than separate top-level variables.
- Run `make lint` before committing. Run `make tfsec` when touching anything that affects security posture (IAM, networking, encryption).

## Git Workflow

### Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<scope>): <description>
```

**Types:** `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `ci`, `perf`, `build`.
**Scope** is optional — typically the affected service or component (inspect recent `git log` for established scopes).

Keep the description lowercase, imperative, no period.

This project also uses the SparkFabrik issue-reference prefix when work is tied to a tracked ticket — inspect recent `git log --oneline` to see the established `refs <project>/#<issue>: ...` pattern.

See the `sf-commit-convention` skill for the full SparkFabrik commit and branching policy (including the mandatory `Assisted-by` trailer for AI-assisted commits).

### Branching

- Branch naming: `feat/`, `fix/`, `chore/`, `test/`, `docs/`, `refactor/`, `ci/` prefix + kebab-case description.
- **Never push directly to `main`.** Always open a pull request.

### Rebasing

- Always rebase onto `main` before pushing. No merge commits.
- Use `--force-with-lease` (never `--force`) after rebasing.
- Rebase before the first push, before opening a PR, and whenever `main` advances.

## OpenSpec Change Management

OpenSpec is scaffolded under `openspec/` (`changes/`, `changes/archive/`, `specs/`). Adopt it for non-trivial design work.

Spec artifacts live in `openspec/changes/<name>/`, archived in `openspec/changes/archive/YYYY-MM-DD-<name>/`.

### Git workflow for specs

OpenSpec itself has no opinion on git — it is a local file workflow. We add these conventions:

1. **Always commit spec artifacts to git** — never leave proposals, designs, specs, or tasks untracked. Commit them as soon as they are created or updated.

2. **Non-trivial changes: spec-first PR** — for changes that span multiple services, add new top-level variables, or alter the public module interface:
   - Create a branch (e.g., `docs/<issue>-<name>-spec`)
   - Commit the proposal, design, specs, and tasks
   - Open a PR for review ("is this the right plan?")
   - Merge the spec PR **before** starting implementation
   - This creates a review checkpoint and prevents building on a wrong design

3. **Trivial changes: spec + implementation in one PR** — for small, well-scoped changes (single service file, additive optional variable, internal refactor), spec and code can go in the same PR.

4. **Archive on merge** — when the implementation is complete, archive the change (`openspec/changes/<name>/` -> `openspec/changes/archive/YYYY-MM-DD-<name>/`) as part of that PR or as an immediate follow-up. Do not leave completed changes in the active directory.

## Package Management

This project has no application-level package managers. The only versioned dependencies are:

- Terraform provider constraints — declared in `versions.tf`.
- Docker image tags for tooling — declared as variables at the top of `Makefile`.
- Renovate configuration — `renovate.json` (automates routine updates).

### Dependency Safety

Before bumping any dependency manually (provider constraint, Docker tool image tag, or external module ref), follow these rules:

1. **Never assume you know the latest version.** Your training data is outdated. Always verify against the live source before bumping.

2. **Check the live source. Determine the right registry from the dependency itself:**
   - **Terraform providers** — read `source` from `versions.tf` and query the Terraform Registry:

     ```bash
     curl -s "https://registry.terraform.io/v1/providers/<namespace>/<name>" | jq '{version: .version, published_at: .published_at}'
     ```

   - **Docker image tags** — read the image reference from `Makefile`, then query its registry (Docker Hub, GHCR, or Quay) for available tags. Use the standard Docker Registry v2 API (`/v2/<image>/tags/list`) or each registry's HTTP API.

   - **External Terraform modules** — read `source` from the module call and check the upstream repository's tags/releases.

3. **Use the newest stable major version** compatible with the constraints in `versions.tf` and the resources already in use. Cross-check the upstream changelog for breaking changes against the resources this module references (look at `README.md`'s "Resources" table for the full list).

4. **Avoid releases published within the last 5 days** to reduce supply chain attack risk. Check the publication date from the registry response.

5. **Let Renovate drive routine bumps.** Only update versions manually when fixing a specific issue or unblocking a feature — and document the reason in the commit body.

## Testing

There is no dedicated test framework in this repo. Verification is performed via:

- **`make lint`** — TFLint against `examples/test.tfvars`.
- **`make tfsec`** — static security scanning against the same example tfvars.
- **GitHub Actions** — see `.github/workflows/` for the active jobs and triggers.
- **Manual integration test** — point a downstream stack at the branch (see Setup) and run `terraform plan` / `terraform apply` in a sandbox GCP project before tagging a release.

Always update `examples/main.tf` and `examples/test.tfvars` when adding inputs so that `make lint` exercises the new fields.

## CI/CD

GitHub Actions runs in `.github/workflows/`. Inspect that directory for the current set of workflows and their triggers — do not rely on a snapshot here.

```bash
ls .github/workflows/
```

Releases are tagged manually (`CHANGELOG.md` follows Keep a Changelog + SemVer; downstream `source = "...?ref=<tag>"` pins consumers to a specific version).

## Command Safety

### Safe (run autonomously)

These commands are read-only or non-destructive. Agents may run them freely:

- `make lint`
- `make tfsec`
- `make generate-docs` (only edits the `<!-- BEGIN_TF_DOCS -->` region of `README.md`)
- `git status`, `git log`, `git diff`, `git branch`, `git show`
- `terraform fmt -recursive -check` (read-only formatting check)
- `tflint --version`, `terraform version`

### Dangerous (ask user first)

These commands modify state or produce a release artifact. **Always ask for user confirmation before running:**

- `git push` (including `--force-with-lease`)
- `git tag` / `git push --tags` (cuts a module release consumed by downstream projects)
- `git rebase`, `git reset --soft`, `git cherry-pick`
- Bumping any version variable in `Makefile` or any provider constraint in `versions.tf`
- Editing `CHANGELOG.md` or `UPGRADING.md` for a release
- Modifying `renovate.json`

### Destructive (never run)

**Never execute these under any circumstances:**

- `git push --force` (use `--force-with-lease` instead, and only after confirmation)
- `git push` to `main` directly
- `git reset --hard` on a branch with unpushed work
- `git branch -D`, `git clean -fdx`
- `rm -rf` on `.terraform/`, `.git/`, or any tracked file
- Any `terraform apply` / `terraform destroy` against a real GCP project from this repo (this module is consumed by downstream stacks; never `apply` from here)

## Important Rules

- Never install Terraform tooling locally — always use `make` targets so versions stay pinned.
- Never hand-edit the `<!-- BEGIN_TF_DOCS -->` block in `README.md`; run `make generate-docs` instead.
- Run `make lint` (and `make tfsec` when relevant) before committing.
- One service per top-level `.tf` file; service inputs are a single object variable with `optional(...)` sub-attributes.
- Keep `examples/main.tf` and `examples/test.tfvars` in sync with new inputs — TFLint runs against them.
- Verify provider and tool versions on the live registry before bumping; let Renovate drive routine updates.
- Never `terraform apply` from this repo — this module is consumed by downstream stacks.
- Never push to `main` directly; always open a PR and rebase before merging.
- Follow Conventional Commits; consult the `sf-commit-convention` skill and recent `git log` for the established prefix and trailer rules.
- For non-trivial changes, draft an OpenSpec proposal under `openspec/changes/<name>/` and merge the spec PR before writing code.
- For ground truth on supported services, inputs, outputs, and resources, read `README.md` (the terraform-docs block) rather than hardcoded references in this document.
