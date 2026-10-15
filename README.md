# MilliHertzBase.jl

[![CI](https://github.com/PaulGoG/MilliHertzBase.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/PaulGoG/MilliHertzBase.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/PaulGoG/MilliHertzBase.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/PaulGoG/MilliHertzBase.jl)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://PaulGoG.github.io/MilliHertzBase.jl/dev/)
[![Julia](https://img.shields.io/badge/julia-%E2%89%A5%201.13-9558B2)](https://julialang.org/)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

MilliHertzBase.jl is the gravitational-wave layer of a set of three Julia
packages for the analysis of telemetry of the Laser Interferometer Space
Antenna (LISA): everything specific to LISA and to massive black hole
binaries, and nothing of the detection method. It builds on
[StreamingInference.jl](https://github.com/PaulGoG/StreamingInference.jl),
which holds the domain-general streaming, conditioning and evaluation code,
and [MilliHertzQML.jl](https://github.com/PaulGoG/MilliHertzQML.jl), a
variational quantum classifier, builds on both.

LISA observes gravitational waves through time-delay interferometry (TDI):
combinations of the phase measurements on the laser links between its
three spacecraft, time-shifted by the light travel times along the arms,
in which the laser frequency noise cancels (Tinto & Dhurandhar 2021,
doi:10.1007/s41114-020-00029-6). A TDI record holds the Michelson-type
combinations X, Y, Z; the stages work on the combinations A, E, T, whose
noises are uncorrelated
for equal arms and equal noise in every link (Prince et al. 2002,
doi:10.1103/PhysRevD.66.122002). The package holds

- the LISA sensitivity (Robson, Cornish & Liu 2019,
  doi:10.1088/1361-6382/ab1101) and the analytic TDI noise of the toolbox
  of the LISA Data Challenge (LDC);
- IMRPhenomA waveforms of non-spinning massive black hole binaries
  (inspiral, merger and ringdown; Ajith et al. 2008,
  doi:10.1103/PhysRevD.77.104017) and the detector response;
- readers of the LDC products, among them LDC-2a ("Sangria") and LDC-2b
  ("Spritz"), the latter with gaps and glitches, and the A, E, T
  combinations;
- the pipeline stages:
  - `generate_telemetry`, simulated telemetry with injected binaries;
  - `preprocess_record`, whitened band features of a TDI record, on the A
    channel or on A and E; a record with gaps is conditioned stretch by
    stretch between the gaps;
  - `label_truth_stream`, truth labels and the signal onset of every
    source, the first window in which the source reaches the labelling
    signal-to-noise ratio (SNR) threshold, measured by default against the
    noise of the record itself;
  - `export_telemetry_payload`, the payload of the DeepSpaceTelemetry
    producer.

[DeepSpaceTelemetry.jl](https://github.com/PaulGoG/DeepSpaceTelemetry.jl)
simulates the telemetry downlink of a spacecraft: ground-station passes,
packet loss and retransmission, and an on-board recorder. The export
stage writes the A channel as one payload column `Amplitude`, or the
columns `A`, `E` (and `T`) of several channels, which the producer (2.6
or later) carries as one payload. The manual is built from `main` at
[PaulGoG.github.io/MilliHertzBase.jl/dev](https://PaulGoG.github.io/MilliHertzBase.jl/dev/).

## Layout

```
MilliHertzBase.jl/
├── activate.jl                 # activates and instantiates the package environment
├── src/
│   ├── MilliHertzBase.jl       # module and public names
│   ├── noise.jl                # LISA sensitivity (Robson, Cornish & Liu 2019)
│   ├── waveforms.jl            # IMRPhenomA
│   ├── response.jl             # detector response
│   ├── ldc.jl                  # LDC products, TDI channels, analytic TDI noise
│   └── stages/                 # generation, pre-processing, labelling, payload export
├── ext/                        # CurvatureDistinguishability and CairoMakie extensions
├── test/                       # suite with static QA, own environment
└── docs/                       # Documenter manual, own environment
```

The full tree is at the end of this page.

## Installation

The package requires Julia 1.13 or later and is not registered; there is
no release yet. It depends on StreamingInference.jl, unregistered too, at
the commit recorded under `[sources]` in `Project.toml`. Most uses, the
examples below among them, also load StreamingInference directly, so an
environment adds it first, at that commit, and MilliHertzBase after it:

```julia
using Pkg
Pkg.add(url = "https://github.com/PaulGoG/StreamingInference.jl",
        rev = "e6c25c1ad4fdcb5e6e76bfb83b0f83d5ff4945d8")
Pkg.add(url = "https://github.com/PaulGoG/MilliHertzBase.jl")
```

MilliHertzBase follows `main` this way; `rev` pins it to a commit. The
extension for
[CurvatureDistinguishability.jl](https://github.com/PaulGoG/CurvatureDistinguishability.jl)
(the constellation response) loads when that package, unregistered too,
is added by URL, and runs of DeepSpaceTelemetry open once it is added the
same way, `Pkg.add(url = "https://github.com/PaulGoG/DeepSpaceTelemetry.jl")`;
the figures need `CairoMakie` in the same environment. If your git
configuration rewrites GitHub URLs to SSH, set `JULIA_PKG_USE_CLI_GIT=true`
so that Pkg clones through the git command line.

## Entry points

```sh
julia -i activate.jl          # REPL in the package environment (activates and instantiates it)
julia test/runtests.jl        # test suite, with Aqua, JET and ExplicitImports
julia docs/make.jl            # manual, built into docs/build/
```

Each environment (the root, `test/`, `docs/`) has an `activate.jl` that
activates and instantiates it, and every entry point includes its own
first.

## Example

An IMRPhenomA signal at a matched-filter SNR of 20 in Gaussian noise of the
LISA sensitivity, and the output of the matched filter on that record:

```julia
using MilliHertzBase, StreamingInference, Random

fs = 0.2                                     # sampling rate [Hz]
h, _, _ = phenoma_waveform(fs, 2 * 86400.0; total_mass = 2e6, mass_ratio = 2.0)
h = scale_to_snr(h, fs, 20.0; psd = lisa_noise_psd)
matched_filter_snr(h, fs; psd = lisa_noise_psd)   # ≈ 20
record = synthesize_noise(Xoshiro(1), length(h), fs; psd = lisa_noise_psd, f_min = 1e-5) .+ h

# Whitened, the noise has unit variance per sample, so the filter output is
# the SNR plus a Gaussian draw of unit variance
wh = whiten_record(h, fs; psd = lisa_noise_psd)
wd = whiten_record(record, fs; psd = lisa_noise_psd)
sum(wd .* wh) / sqrt(sum(abs2, wh))          # ≈ 20.1
```

The waveform and the noise model come from this package; the noise
synthesis, the SNR and the whitening from StreamingInference.jl.

## Stages and configuration

Each stage takes the parsed configuration: `load_config(path)` of a TOML
file, or a `Dict`. A missing key takes the default of the settings
function of its section (`generation_settings`, `preprocessing_settings`,
`ldc_settings`, `telemetry_settings`, `tdi_settings`), which validates the
section and refuses a value it cannot honour. Relative paths resolve
against the pipeline root of StreamingInference.jl: the directory set by
`with_pipeline_root`, else the environment variable
`STREAMINGINFERENCE_ROOT`, else the nearest directory above the active
environment whose `Project.toml` declares a package. The scripts that run
the stages from the command line are those of MilliHertzQML.jl.

The observed record is the HDF5 object `[preprocessing] tdi_group`, or,
when `[preprocessing] tdi_components` lists several objects, their sum
sample by sample over their common span: the layout of the LDC products
shipped as component streams, such as LDC-1b Yorsh (instrument noise,
confusion noise, one stream per source). `--tdi-group` of the scripts names
one object and overrides the list.

A simulated record of three days with one massive black hole binary,
generated and pre-processed under a temporary pipeline root:

```julia
using MilliHertzBase, StreamingInference

# Three days, one massive black hole binary, five Galactic binaries, no
# extreme-mass-ratio inspiral; every other key at its default
config = Dict(
    "generation" => Dict("days" => 3.0, "n_mbhb" => 1, "n_gbs" => 5, "n_emris" => 0),
)
product = with_pipeline_root(mktempdir()) do
    sim = generate_telemetry(config)         # record, labels and catalogue under data/inputs/
    preprocess_record(config; label_file = sim.label_file)
end
product.n_windows                            # 509 windows of 1000 samples, step 100
```

## Telemetry producer

The export stage writes the payload the DeepSpaceTelemetry producer
ingests: under `[tdi] channels = "A"` the A channel as its one column
`Amplitude`, and under `"AE"` or `"AET"` the columns `A`, `E` (and `T`),
which the producer (2.6 or later) carries as one payload under one link
accounting — one batch, one transfer, one loss for all of them. Reading a
run of the producer back is not specific to gravitational waves, so it
lives in StreamingInference.jl, whose DeepSpaceTelemetry extension builds
on the producer's reference run adapter; `open_telemetry_run` is
re-exported here, and its `columns` keyword selects the payload columns of
a run that carries several. A mission that carried the A channel alone is
replayed on A and E through StreamingInference's `ScheduledRecordRun`,
which serves every delivered batch from the TDI record (`channel_record`)
after checking its A column against the payload.

`telemetry_settings` also validates the replay settings of `[telemetry]`:
the persistence of an alert (`alert_persistence`), the confirmation tier
(`alert_confirmation_persistence`, 0 or above both `alert_persistence` and
the overlap `window_size ÷ step_size` of the `[preprocessing]` windows) and
the crediting (`alert_crediting`), which the replay scripts of
MilliHertzQML.jl pass to `alert_latency_table` of StreamingInference.jl.

## Status

No release yet: version 0.1.0-DEV on `main`, which MilliHertzQML.jl pins
by commit; install by URL and commit, as above.

## Full file tree

<details>
<summary>Full file tree</summary>

```
MilliHertzBase.jl/
├── Project.toml                # Package metadata, dependencies (StreamingInference by URL and commit), compat
├── activate.jl                 # Activates and instantiates the package environment
├── CHANGELOG.md
├── CITATION.cff
├── LICENSE
├── THIRD_PARTY_NOTICES.md      # Licence of the ported LDC noise model
├── src/
│   ├── MilliHertzBase.jl       # Module, exported names
│   ├── config.jl               # Settings of the generation, pre-processing, LDC, TDI and telemetry sections
│   ├── noise.jl                # Instrument and confusion noise, sky-averaged sensitivity
│   ├── response.jl             # Detector-response interface, sky-averaged response
│   ├── waveforms.jl            # IMRPhenomA amplitude, phase, spectrum, time series
│   ├── ldc.jl                  # LDC readers, TDI to A/E/T, analytic TDI and confusion noise
│   ├── whitening.jl            # Whitening PSD of a record and from a feature sidecar
│   ├── visualization.jl        # Figure interface of this layer
│   └── stages/
│       ├── generation.jl       # Simulated telemetry with injected binaries
│       ├── preprocessing.jl    # Whitened band features of a TDI product
│       ├── labeling.jl         # Truth labels and signal onsets
│       └── export_payload.jl   # DeepSpaceTelemetry payload of a TDI product (A, or several channels)
├── ext/
│   ├── MilliHertzBaseCurvatureDistinguishabilityExt.jl  # Constellation response
│   └── MilliHertzBaseCairoMakieExt.jl                   # Mission and strain traces
├── test/
│   ├── Project.toml            # Test environment (package by path, dependencies by URL and commit)
│   ├── activate.jl
│   ├── runtests.jl             # Static QA, noise, waveforms, LDC products, settings, figures, stages
│   ├── export_payload_tests.jl # Payload export: payload CSV, scenario fragment, batch geometry
│   ├── telemetry_integration_tests.jl  # Export, producer missions, replay through StreamingInference
│   ├── labeling_tests.jl       # Labelling stage on a synthetic truth stream
│   └── response_tests.jl       # Constellation response (CurvatureDistinguishability extension)
├── docs/
│   ├── Project.toml            # Documentation environment
│   ├── activate.jl
│   ├── make.jl
│   └── src/                    # Manual pages
├── .github/
│   ├── workflows/CI.yml        # Tests on the compat floor and the current release, formatting check, coverage
│   ├── workflows/Documentation.yml  # Manual built on every push, deployed to GitHub Pages
│   └── dependabot.yml          # Weekly updates of the Julia and GitHub Actions dependencies
└── codecov.yml                 # Coverage statuses informational; the commit status rests on the tests
```

</details>

## How to cite

`CITATION.cff` carries the metadata; in BibTeX:

```bibtex
@software{Gogita_MilliHertzBase_jl,
  author = {Gogîță, Paul-Adrian},
  title  = {{MilliHertzBase.jl}},
  url    = {https://github.com/PaulGoG/MilliHertzBase.jl},
  year   = {2026}
}
```

## License

MIT; see `LICENSE`. The analytic TDI noise model is a port of the LISA
Data Challenge toolbox (MIT, Copyright (c) 2019 LISA); its notice is in
`THIRD_PARTY_NOTICES.md`.
