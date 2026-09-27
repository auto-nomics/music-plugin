# music plugin

Migrated from the legacy `music_deconvolution_container` wrapper in
nodes-io. One directory = one plugin family = one git-able unit. The
original container-era README moved with the build tree as
`container_README.md` (verbatim, modulo its `music_deconvolution_container`
kind spelling and its reference to the deleted `AUTONOMICS_IMAGE_PREFIX`
indirection — image references are self-contained digest pins since the
prefix's removal).

## Layout

- `manifest.toml` — node kind `music_deconvolution`: params, ports, image
  provenance, resources
- `Dockerfile` — image build provenance (moved verbatim from
  `containers/music-deconvolution/`; build + push still via GHCR, base is
  the digest-pinned `autonomics/bulk-rnaseq` image)
- `music_runner.R` — the baked runner, `COPY`-ed to
  `/opt/autonomics/music_runner.R` by the Dockerfile; the manifest declares
  no script, only `interpreter = "Rscript"` plus fixed argv (there is no
  `scripts/` directory: this is a baked-runner family, like `deseq2`)
- `test_smoke.sh` — image baseline (build, verify the pinned R/MuSiC/TOAST/
  SingleCellExperiment versions, push; `PUSH=0` skips the publish step);
  `root=` repointed to this directory
- `container_README.md` — the original containers/music-deconvolution/
  README.md

**Fixtures did not move.** The deterministic 120-gene smoke fixture stays in
the autonomics repository at `containers/music-deconvolution/fixtures/`
(beside its generator `generate_fixtures.py`) because the still-live Rust
test `crates/node-bundles/nodes-io/tests/music_deconvolution_container.rs`
reads it there. That test dies together with the wrapper; when it does, the
fixture directory can move here (the `real_podman` case in it exercises the
same contract `test_smoke.sh` version-checks).

## Provenance

- Image:
  `ghcr.io/auto-nomics/autonomics/music-deconvolution@sha256:886b83135179a48fffe2009238eb7d45ec89d32713cc1a2370078583e3bbfeaf`,
  tag `1.0.0`, from `Dockerfile` (base `autonomics/bulk-rnaseq`, itself
  digest-pinned; CRAN snapshot 2026-09-13, Bioconductor 3.22).
- Upstream: official [MuSiC](https://github.com/xuranw/MuSiC) 1.0.0 source
  tarball (sha256
  `57f2cd50335ffee220317b80169a88c28a18060a9830080424f0b28391b9d9f1`,
  revision `f21fe67f5670d5e9fca0ad7550abaae3423eb59c`); license
  GPL-3.0-or-later.

## Migration parity

The golden test (`crates/container-plugin/tests/music_migration.rs`)
compares the compiled `ContainerCommandSpec` against the legacy Rust
wrapper (`nodes-io/src/music_deconvolution_container.rs`): image, command,
outputs, resources, timeout, and env names/values are byte-equal, and the
script-less baked-runner shape is asserted. Deliberate deltas:

- **Baked runner preserved as argv.** The legacy wrapper passed
  `["Rscript", "--vanilla", "/opt/autonomics/music_runner.R"]` with
  `script: None`; the manifest expresses exactly that with
  `interpreter = "Rscript"` and `argv` (the DSL's baked-runner shape). All
  nine parameters travel through the same `AUTONOMICS_MUSIC_*` environment
  variables, so the pinned image needs no rebuild. Note the run report
  produced inside the pinned image still carries
  `"node": "music_deconvolution_container"`; that string is baked into the
  runner and changes only with the next image build.
- **Kind rename**: `music_deconvolution_container` → `music_deconvolution`;
  the artifact prefix follows the kind
  (`/artifacts/music_deconvolution_container` →
  `/artifacts/music_deconvolution`), the same rule the
  ldsc/mrpresso/mvmr/deseq2 migrations applied. DAG specs referencing the
  old kind must be regenerated.
- **`timeout_secs` / `artifact_prefix` are node-level constants**
  (7200 s, `/artifacts/music_deconvolution`) instead of per-instance spec
  params; the legacy spec accepted per-node overrides, the plugin DSL does
  not.
- **`select_cell_types` shape change**: the legacy spec carried a string
  array joined with `","` into `AUTONOMICS_MUSIC_SELECT_CELL_TYPES`. The
  v0 env renderer space-joins arrays, while the baked runner splits the
  variable on commas (`split_csv`), so the manifest declares a plain
  string carrying the comma-separated list — byte-identical env for every
  legacy-legal input (legacy entries are cell-type labels, which never
  contain commas). Same serialized-string pattern as the deseq2
  `covariates` migration. Empty means "all observed cell types", exactly
  like the legacy empty vec.
- **Validation moved or dropped**: the DSL cannot express
  `is_simple_r_identifier` or the duplicate-entry check. Non-empty
  `cell_type_col` / `subject_col` still fail closed at container start
  (the runner's `required_env()`), and a column name that is absent from
  the metadata still fails with the legacy "cell metadata is missing
  columns" message — but the identifier-shape and duplicate
  `select_cell_types` guards of the legacy `validate()` are lost
  (fail-open into MuSiC's own argument handling). `iter_max >= 1` and
  `nu > 0`, `epsilon > 0` are enforced at compile time via `min` /
  `exclusive_min`. The failure point for the surviving checks moves from
  registry build to container start, as in every baked-runner migration.
- **Resources pinned**: 4 CPUs, `12Gi` memory, pids limit 256, `1Gi` shm,
  isolated network, read-only rootfs, pull policy `missing` — the legacy
  wrapper's exact defaults; the manifest relies on the hardened defaults
  for the three boolean/enum fields.
- **Optional input ports dropped (v0 DSL gap).** The legacy `port_layout()`
  declared three required labeled inputs plus two *optional* unlabeled
  inputs (cell-size table, marker gene table). The manifest `PortLayout`
  has no optional-port flag — `compile_ports` marks every declared input
  required — so declaring them would force wiring on every run. They are
  omitted: the node exposes exactly the three required ports, and the
  cell-size/marker features are unreachable until the DSL grows optional
  input ports (the pinned runner still honours `AUTONOMICS_INPUT3` /
  `AUTONOMICS_INPUT4` if they ever return). The legacy `run_report.json`
  fields `markers_provided` / `cell_sizes_provided` are therefore always
  `false` on this node.
- **Output port labels**: the five output ports gain file-stem labels
  (`cell_type_proportions`, `nnls_proportions`, `gene_weights`,
  `diagnostics`, `run_report`) because the manifest pipeline always names
  output ports; the legacy ports were unlabeled — the same accepted delta
  as the deseq2/mvmr migrations.
