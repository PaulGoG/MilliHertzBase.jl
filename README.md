# MilliHertzBase.jl

[![CI](https://github.com/PaulGoG/MilliHertzBase.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/PaulGoG/MilliHertzBase.jl/actions/workflows/CI.yml)
[![Docs (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://PaulGoG.github.io/MilliHertzBase.jl/dev/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Gravitational-wave layer for the analysis of LISA telemetry: the LISA noise
model and the analytic TDI noise of the LISA Data Challenge, IMRPhenomA
waveforms of massive black hole binaries, the detector response, readers of
LDC products, the stages that generate, pre-process, label and export
records, and an adapter that reads a DeepSpaceTelemetry run as a stream. It
builds on [StreamingInference.jl](https://github.com/PaulGoG/StreamingInference.jl),
which holds the domain-general streaming, conditioning and evaluation code.

I wrote this code as the gravitational-wave layer of
[MilliHertzQML.jl](https://github.com/PaulGoG/MilliHertzQML.jl) and moved
it into its own package so that other methods on LISA data can share it.

```
MilliHertzBase.jl/
├── src/
│   ├── MilliHertzBase.jl       # Module and public names
│   ├── noise.jl                # LISA sensitivity (Robson, Cornish & Liu 2019)
│   ├── waveforms.jl            # IMRPhenomA
│   ├── response.jl             # Detector response
│   ├── ldc.jl                  # LDC products, TDI channels, analytic TDI noise
│   └── stages/                 # Generation, pre-processing, labelling, payload export
├── ext/                        # DeepSpaceTelemetry, CurvatureDistinguishability, CairoMakie
├── test/
└── docs/
```

## Installation

The package is not registered; install it from this repository (Julia ≥ 1.13).
Its dependency StreamingInference.jl is fetched from the commit recorded in
`Project.toml`.

```julia
using Pkg
Pkg.add(url = "https://github.com/PaulGoG/MilliHertzBase.jl")
```

## Entry points

```sh
julia -i activate.jl          # REPL in the package environment (activates and instantiates it)
julia test/runtests.jl        # test suite, with Aqua, JET and ExplicitImports
julia docs/make.jl            # manual, built into docs/build/
```

If your git configuration rewrites GitHub URLs to SSH, set
`JULIA_PKG_USE_CLI_GIT=true` so that Pkg clones through the git command line.

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

Version 0.1.0-DEV, extracted from MilliHertzQML.jl 3.0.0-DEV with its
history from the separation of the layers; used by MilliHertzQML.jl. The
analytic TDI noise model is a port of the LDC toolbox (MIT licence, see
`THIRD_PARTY_NOTICES.md`).

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
└── docs/
    ├── Project.toml            # Documentation environment
    ├── activate.jl
    ├── make.jl
    └── src/                    # Manual pages
```

</details>
