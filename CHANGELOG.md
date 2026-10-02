# Changelog

All notable changes to this package are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- First release as a package of its own. The code was the
  gravitational-wave layer of MilliHertzQML.jl (3.0.0-DEV) and keeps its
  history from the commit that separated the layers: the LISA noise model
  and the analytic TDI noise of the LDC toolbox, IMRPhenomA waveforms, the
  detector-response interface, LDC readers and A/E/T channels, whitening
  PSDs, the generation, pre-processing, labelling and payload-export
  stages, and the DeepSpaceTelemetry, CurvatureDistinguishability and
  CairoMakie extensions. It depends on StreamingInference.jl.
- The constants `L_ARM`, `C_LIGHT` and `F_STAR` are public names.

### Changed (relative to the layer inside MilliHertzQML.jl)
- `figure_mission_trace` takes `score_label`, `score_name` and
  `score_range`; its score axis spans the scores and the threshold unless
  `score_range` is given, instead of a classifier probability in [0, 1].
