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
- Channel modes, `[tdi] channels = "A" | "AE" | "AET"` (`tdi_settings`,
  `channel_names`, `channel_suffix`), recorded in every product. In the
  mode `"AE"` the pre-processing stage whitens A and E each by its own PSD
  and writes the features of the channel-averaged periodogram under a stem
  ending in `_ae`, with one PSD column per channel; the labelling stage
  adds the onset of the A and E network (`signal_start_index_ae`,
  `label_peak_snr_ae`) from the root of the summed squared window SNRs.
  `"AET"` is accepted by the labelling stage, which sets the three-channel
  onset to the AE onset and says so, and refused by the pre-processing
  stage until the features of the T channel exist. `whitening_psd` takes
  the `channel` and refuses an analytic PSD for T. The mode `"A"` leaves
  every product as it was.

### Changed (relative to the layer inside MilliHertzQML.jl)
- `figure_mission_trace` takes `score_label`, `score_name` and
  `score_range`; its score axis spans the scores and the threshold unless
  `score_range` is given, instead of a classifier probability in [0, 1].
