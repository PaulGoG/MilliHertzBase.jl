# MilliHertzBase.jl

[![CI](https://github.com/PaulGoG/MilliHertzBase.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/PaulGoG/MilliHertzBase.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/PaulGoG/MilliHertzBase.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/PaulGoG/MilliHertzBase.jl)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://PaulGoG.github.io/MilliHertzBase.jl/dev/)
[![Julia](https://img.shields.io/badge/julia-%E2%89%A5%201.13-9558B2)](https://julialang.org/)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

The gravitational-wave layer of a set of three Julia packages for the
analysis of LISA telemetry: everything specific to LISA and to massive
black hole binaries, and nothing of the detection method. It holds

- the LISA noise model and the analytic TDI noise of the LISA Data
  Challenge (LDC);
- IMRPhenomA waveforms of massive black hole binaries and the detector
  response;
- readers of the LDC products (the LDC-2a and LDC-2b layouts, records
  with gaps) and the A, E, T channel combinations;
- the pipeline stages that generate, pre-process, label and export
  records, on the A channel or on the A and E network, a record with gaps
  stretch by stretch, with the signal onset of every source measured
  against the analytic noise or against the record's own;
- an adapter that reads a DeepSpaceTelemetry run as a stream.

It builds on
[StreamingInference.jl](https://github.com/PaulGoG/StreamingInference.jl),
which holds the domain-general streaming, conditioning and evaluation
code, and it is used by
[MilliHertzQML.jl](https://github.com/PaulGoG/MilliHertzQML.jl), the
variational quantum classifier whose gravitational-wave layer this code
was before I moved it into its own package, so that other methods on LISA
data can share it. The manual is built from `main` at
[PaulGoG.github.io/MilliHertzBase.jl/dev](https://PaulGoG.github.io/MilliHertzBase.jl/dev/).

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
├── ext/                        # DeepSpaceTelemetry, CurvatureDistinguishability and CairoMakie extensions
├── test/                       # suite with static QA, own environment
└── docs/                       # Documenter manual, own environment
```

The full tree is at the end of this page.

## Installation

The package requires Julia 1.13 or later and is not registered. There is
no release yet: an environment adds it from this repository, following
`main` or pinned to a commit with `rev`:

```julia
using Pkg
Pkg.add(url = "https://github.com/PaulGoG/MilliHertzBase.jl")
```

StreamingInference.jl comes with it, from the commit recorded in
`Project.toml`. The extensions for
[DeepSpaceTelemetry.jl](https://github.com/PaulGoG/DeepSpaceTelemetry.jl)
(a producer run read as a stream) and
[CurvatureDistinguishability.jl](https://github.com/PaulGoG/CurvatureDistinguishability.jl)
(the constellation response) load when those packages, unregistered too,
are added by URL; the figures need `CairoMakie` in the same environment.
If your git configuration rewrites GitHub URLs to SSH, set
`JULIA_PKG_USE_CLI_GIT=true` so that Pkg clones through the git command
line.

## Entry points

```sh
julia -i activate.jl          # REPL in the package environment (activates and instantiates it)
julia test/runtests.jl        # test suite, with Aqua, JET and ExplicitImports
julia docs/make.jl            # manual, built into docs/build/
```

Each environment (the root, `test/`, `docs/`) has an `activate.jl` that
activates and instantiates it, and every entry point includes its own
first. The pipeline stages are library functions (`generate_telemetry`,
`preprocess_record`, `label_truth_stream`, `export_telemetry_payload`),
each driven by a TOML configuration; the scripts that run them from the
command line are those of MilliHertzQML.jl.

## Example

An IMRPhenomA signal at a matched-filter SNR of 20 in Gaussian noise of the
LISA sensitivity:

```julia
using MilliHertzBase, StreamingInference, Random

fs = 0.2                                     # sampling rate [Hz]
h, merger_index, p = phenoma_waveform(fs, 2 * 86400.0; total_mass = 2e6, mass_ratio = 2.0)
p.f_ring                                     # ringdown frequency [Hz]
h = scale_to_snr(h, fs, 20.0; psd = lisa_noise_psd)
record = synthesize_noise(Xoshiro(1), length(h), fs; psd = lisa_noise_psd, f_min = 1e-5) .+ h
matched_filter_snr(h, fs; psd = lisa_noise_psd)   # 20.0
```

## Status

No release yet: version 0.1.0-DEV on `main`, which MilliHertzQML.jl pins
by commit. The code was the gravitational-wave layer of MilliHertzQML.jl
until the layers were separated into packages on 1 October 2026; the
repository keeps the history of those files. Added since: the channel
modes (`[tdi] channels`), the pre-processing of records with gaps, the
one-source catalogue of the LDC-2b records, and the signal onset against
the record's own noise (`[ldc] psd_model = "record"`).

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
│   ├── config.jl               # Settings of the generation, pre-processing, LDC and telemetry sections
│   ├── noise.jl                # Instrument and confusion noise, sky-averaged sensitivity
│   ├── response.jl             # Detector-response interface, sky-averaged response
│   ├── waveforms.jl            # IMRPhenomA amplitude, phase, spectrum, time series
│   ├── ldc.jl                  # LDC readers, TDI to A/E/T, analytic TDI and confusion noise
│   ├── whitening.jl            # Whitening PSD of a record and from a feature sidecar
│   ├── telemetry.jl            # Telemetry interface of this layer (open_telemetry_run)
│   ├── visualization.jl        # Figure interface of this layer
│   └── stages/
│       ├── generation.jl       # Simulated telemetry with injected binaries
│       ├── preprocessing.jl    # Whitened band features of an LDC product
│       ├── labeling.jl         # Truth labels and signal onsets
│       └── export_payload.jl   # DeepSpaceTelemetry payload of an LDC product
├── ext/
│   ├── MilliHertzBaseDeepSpaceTelemetryExt.jl           # Producer run directory as a StreamingInference run
│   ├── MilliHertzBaseCurvatureDistinguishabilityExt.jl  # Constellation response
│   └── MilliHertzBaseCairoMakieExt.jl                   # Mission and strain traces
├── test/
│   ├── Project.toml            # Test environment (package by path, dependencies by URL and commit)
│   ├── activate.jl
│   └── runtests.jl
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
