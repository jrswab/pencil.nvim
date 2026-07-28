# 006: Release Readiness Implementation Guide

## Context Summary

Milestone 006 turns the existing Neovim-native `pencil.nvim` implementation into a documented, installable, testable v0.1.0 candidate without changing its established M001–M005 behavior. The work must document the public `require("pencil")` API, unified commands, presets, safety and ownership guarantees, Lazy.nvim activation distinction, statusline use, migration boundary, MIT attribution, and Neovim 0.10+ support; add native help and its generated index; run deterministic real-Neovim tests on exactly Neovim 0.10 and current stable; and cover the complete release-readiness matrix. Runtime edits are out of scope except narrowly restoring an already normative M001–M005/public contract when release verification exposes it, with a regression test and no new feature. There is no release workflow, tag, changelog, publication, or version-bumping work.

## Implementation Checklist

### Slice 1 — Public documentation and attribution end to end

**Status:** complete.

**Dependency:** none. This slice produces a usable installation and reference experience against the current public runtime surface before CI is added.

- [x] `README.md: project overview, Installation, Configuration, API, Commands, Statusline, Safety, Migration, and Attribution sections` — write the concise entry point required by the specification: verified `jrswab/pencil.nvim` installation, Neovim 0.10+ and Vim unsupported statements, no required runtime dependencies, both exact Lazy.nvim forms with their different activation semantics, setup example, built-in presets or an exhaustive-help pointer, public Lua/command/statusline examples, restoration/conflict/fail-closed/per-window/quiet-notification guarantees, migration boundary, LICENSE link, and verified `preservim/vim-pencil` inspiration URL. Do not document unsupported options or imply compatibility.
- [x] `doc/pencil.txt: *pencil*` and `*pencil-installation*` sections — add standard Vim help overview, requirements, installation, runtimepath loading, Lazy.nvim bare-declaration versus `opts = {}` behavior, and the exact supported-version/dependency boundary. Examples must parse as Lua or Vim commands.
- [x] `doc/pencil.txt: *pencil-configuration*` — document setup precedence, defaults, all global and keyed filetype schemas, list replacement and empty-list behavior, all built-in presets, modeline/detection/width precedence, classifier context/results, and atomic validation. Distinguish buffer-local settings from window-local presentation and use the normative terminology from the specification.
- [x] `doc/pencil.txt: *pencil-api*`, `*pencil-commands*`, and `*pencil-status*` — document every public Lua function, accepted options and return meanings, command actions/aliases/completion, format actions, exact `A`/`H`/`S`/off semantics, notification policy, and statusline integration. Do not expose `pencil._test` or private helpers.
- [x] `doc/pencil.txt: *pencil-migration*` and attribution/license sections — state that this is a clean Neovim redesign inspired by `preservim/vim-pencil`, not a Vimscript compatibility port; give the prescribed migration replacements and explicitly preserve the repository MIT `LICENSE` and `Copyright (c) 2026 Jaron Swab` notice without inventing terms or claims.
- [x] `LICENSE: existing MIT notice` — verify the existing attribution remains unchanged while documentation links to it; do not add a second license or alter the copyright text.
- [x] `README.md: documentation/API agreement review` and `doc/pencil.txt: all seven stable tags` — compare README and help against `docs/plans/006_release_readiness_spec.md` for schemas, defaults, presets, commands, statuses, activation boundaries, safety, migration, and compatibility wording before generating the index.

**Independently testable outcome:** a clean checkout user can install the plugin, understand the two setup modes, find complete normative help through `:help pencil`, and distinguish supported API from internal test seams.

### Slice 2 — Generated help index and documentation smoke verification

**Status:** implemented; generated-tag freshness is verified without rewriting the repository artifact.

**Dependency:** Slice 1. The generated index must come from the completed help file and the smoke checks must exercise the real module/help loader.

- [x] `doc/tags: generated native-help index` — generate the committed index from `doc/pencil.txt` using the exact `nvim --headless --clean -u NONE +'lua local ok, err = pcall(vim.cmd, "helptags doc"); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") else assert(ok) end' +qa` command; retain entries for exactly `pencil`, `pencil-installation`, `pencil-configuration`, `pencil-api`, `pencil-commands`, `pencil-status`, and `pencil-migration`.
- [x] `tests/smoke.lua: module-loading and public documentation checks` — extend the real headless smoke suite, or add a focused M006 section, to verify the loaded module exposes the documented public functions and commands without asserting private implementation details. Keep existing M001–M005 behavior checks intact.
- [x] `tests/m006.lua: help/tag and README contract checks` — add deterministic real-Neovim checks for `require("pencil")`, `:help pencil` with `set rtp^=.`, the existence of `doc/tags`, and all seven exact tags. Use shell/file checks for README headings, required installation forms, repository/inspiration URLs, version/dependency statements, and forbidden compatibility claims rather than replacing runtime behavior tests with mocks.
- [x] `tests/run.sh: isolated suite entry point` — create an executable deterministic runner that puts the repository on `runtimepath`, loads `plugin/pencil.lua`, runs the existing smoke and M005 suites plus M006 checks, performs the required help/tag checks, prints the exact `nvim --version`, and exits nonzero on syntax, test, help, tag, or `git diff --check` failure. It must not require a third-party test plugin.

**Independently testable outcome:** one local runner validates loading, native help navigation, generated tags, README contract checks, and the existing real behavior suites in an isolated process.

### Slice 3 — Release-readiness behavior matrix and narrow correction loop

**Dependency:** Slice 2. Add focused tests before considering any runtime correction; all tests must observe real Neovim behavior through public calls where applicable.

- [x] `tests/m006.lua: minimum-version and activation-boundary cases` — cover module loading, the exact error for Neovim below 0.10 using an isolated supported test strategy, bare installation/direct controls versus successful `setup({})` automatic FileType activation, and setup failure atomicity. Do not fake the module’s production behavior in the test.
- [x] `tests/m006.lua: configuration and precedence matrix` — cover every built-in preset, simple-list replacement, keyed replacement and field-wise merge, unknown names, `filetypes = {}`, all setup/nested conceal/mappings/status fields and legal values, unknown-key rejection/aggregate errors, every per-call schema and buffer target, modelines including disabled-modeline behavior, the 20-line threshold, and hard width precedence.
- [x] `tests/m006.lua: API, commands, aliases, completion, and status matrix` — exercise every documented Lua function, nil/indicator meanings, all primary command actions, format actions, aliases, completion, mode results, status indicators, `A` outside Insert, and `H` for disabled/suspended/protected/unknown/external-unowned states. Verify routine operations remain quiet and only prescribed failures notify.
- [x] `tests/m006.lua: mapping, formatting, classification, and safety matrix` — cover both mapping groups, `<CR>` conflicts, repeated cycles, plain formatting, existing Treesitter/syntax classification, custom classifier context and exact results, invalid/error classifier fail-closed behavior, conceal defaults/opt-out, statusline non-interference, and absence of unrelated option changes. Parser-dependent cases must print an explicit skip reason; all non-parser safety/fallback cases must still run.
- [x] `tests/m006.lua: lifecycle and restoration matrix` — cover exact options/formatoptions restoration, external edits, multiple buffers and windows, late windows, filetype transitions, wipeout, cleanup, presentation isolation, and no mapping/formatting/presentation leakage. Preserve and invoke the existing `tests/smoke.lua` and `tests/m005.lua` suites rather than duplicating their implementation seams.
- [x] `lua/pencil/init.lua: existing public functions and lifecycle helpers exposed by release verification` — corrected only the normative external-formatoptions FileType ownership behavior; removed the private version test export. Completion and validation regressions are covered in `tests/m006.lua`.
- [x] `tests/m006.lua` and `tests/smoke.lua: correction regressions` — external formatoptions/FileType ownership, exact public surface/version guard, completion sets/counts, and parser failure handling are covered; smoke, M005, and M006 pass locally.

**Independently testable outcome:** the release contract is executable through real public behavior, optional parser cases are explicit, and any runtime diff is demonstrably a narrowly scoped regression correction rather than a feature.

### Slice 4 — CI on exactly Neovim 0.10 and current stable

**Status:** implemented; local verification uses the available Neovim 0.12.0-dev binary; the exact CI matrix remains CI-only.

**Dependency:** Slice 3 and a passing local runner. CI must run the same deterministic test surface and must not silently substitute a development build.

- [x] `.github/workflows/test.yml: workflow jobs and version matrix` — add GitHub Actions jobs for exactly Neovim 0.10 and the current stable version selected by the workflow configuration. Install or select explicit supported binaries, put the checkout on `runtimepath`, run `tests/run.sh`, print each binary’s `nvim --version`, and fail on syntax/test/help/tag/runner failures or `git diff --check`. Do not add a release/publish/tag workflow.
- [x] `.github/workflows/test.yml: stable-version guard` — ensure the stable job cannot silently resolve to an unsupported development build; record the exact resolved version and fail or report unavailable rather than substituting another binary.
- [x] `tests/run.sh: CI/local version and parser reporting` — print parser availability and explicit reasons for skipped parser-dependent cases, while always executing module loading, documentation, syntax/fallback, plain/custom/unknown safety, lifecycle, and other non-parser checks. Keep the runner deterministic in clean checkouts.
- [x] `.github/workflows/test.yml` and `tests/run.sh: checkout cleanliness verification` — run the specified `git diff --check` and ensure generated `doc/tags` is present and committed in the tested checkout; do not generate undocumented release artifacts.

**Independently testable outcome:** a clean GitHub checkout runs the same complete readiness checks on exactly Neovim 0.10 and current stable, records the binaries used, and fails closed on regressions.

### Slice 5 — Final acceptance and scope verification

**Dependency:** Slices 1–4. This slice adds no product behavior; it proves agreement, generated artifacts, and repository boundaries.

- [x] `README.md`, `doc/pencil.txt`, `doc/tags`, `.github/workflows/test.yml`, `tests/m006.lua`, and `tests/run.sh: final acceptance pass` — verify all §3, §8, and §9 requirements, README/help agreement, seven tags, supported-version statements, migration/license/attribution claims, exact commands/aliases/status semantics, and absence of changelog/tag/release automation.
- [x] `lua/pencil/init.lua`, `plugin/pencil.lua`, `lua/pencil/classification.lua`, `lua/pencil/_test.lua`, `tests/smoke.lua`, and `tests/m005.lua: regression boundary` — confirm existing runtime and test seams are unchanged unless a specific M006 regression correction is recorded with its test and rationale; do not expose private helpers in documentation.
- [x] `docs/plans/006_release_readiness_spec.md: authority check` — reread Context and Constraints and confirm the implementation checklist follows its fixed decisions without re-evaluating or changing the specification.
- [x] `tests/run.sh: final local validation` — run the exact specification validation commands for module loading, `:help pencil`, `helptags doc`, all seven tags, `nvim --version`, `git diff --check`, and `git status --short`; report unavailable Neovim matrix binaries rather than substituting another version.

**Independently testable outcome:** the final diff contains only the M006 deliverables plus any explicitly justified narrow runtime correction, and the repository is ready for evaluation without creating a release.

## Parallel Work

Do not parallelize the initial public-surface agreement. First complete the README/help outline and identify every existing public function, command, preset, status, safety, ownership, and migration claim against the specification. Generate `doc/tags` only after the help file is stable.

After that contract is fixed, these tracks can proceed in parallel:

1. `README.md` and `doc/pencil.txt` content, including migration and attribution, followed by the README/help agreement review.
2. `tests/m006.lua` documentation, minimum-version, API, configuration, status, safety, and lifecycle assertions alongside `tests/run.sh` integration.
3. `.github/workflows/test.yml` version installation/selection and exact-version reporting after the runner’s command-line contract is stable.
4. Focused release verification of `lua/pencil/init.lua` against existing public contracts, only escalating to the narrow correction exception when a real regression test proves it necessary.
5. Generated `doc/tags` and local validation after `doc/pencil.txt` edits are complete.

Integrate in slice order. Run the complete real-Neovim suite after each integration point; parser-dependent checks may be skipped only with explicit output, and all other safety/fallback checks must remain executable without optional parsers.

## Acceptance / Verification

- [x] Verify `README.md` contains the exact `jrswab/pencil.nvim` installation identity, Neovim 0.10+ requirement, Vim unsupported/no-dependency statements, both Lazy.nvim examples with distinct semantics, setup/API/command/statusline examples, safety guarantees, migration heading, LICENSE link, and verified inspiration URL.
- [x] Verify `doc/pencil.txt` contains all seven exact stable tags and complete normative coverage for installation, configuration schemas/defaults/presets/precedence, API, commands/aliases/completion, status, lifecycle safety, classification, testing expectations, migration, license, and attribution.
- [x] Generate and validate `doc/tags` with the exact commands from the specification, then run `:help pencil` with `set rtp^=.`.
- [x] Run the deterministic runner and the existing isolated `tests/smoke.lua` and `tests/m005.lua` suites using real headless Neovim; record exact versions and parser availability/reasons.
- [ ] Run CI on exactly Neovim 0.10 and current stable; report any unavailable binary instead of substituting another version, and ensure the stable job rejects unsupported development builds.
- [x] Run the exact local validation sequence from §10: module load, help load, helptags generation, all seven tag checks, `nvim --version`, `git diff --check`, and `git status --short`.
- [x] Run `git diff --check -- docs/plans/006_release_readiness_implement.md` and inspect the plan with `git diff --no-index /dev/null docs/plans/006_release_readiness_implement.md` to confirm it contains only an implementation guide, no runtime/docs/CI implementation, and no placeholders.
- [x] Verify the planning task changes only `docs/plans/006_release_readiness_implement.md`; pre-existing working-tree changes in runtime/tests and untracked prior plans/specs are out of scope and must not be attributed to this guide.

**Local verification note:** The local acceptance run used NVIM v0.12.0-dev, including parser availability reporting; it did not verify the exact Neovim 0.10/current-stable CI matrix. CI remains pending until GitHub Actions runs.
