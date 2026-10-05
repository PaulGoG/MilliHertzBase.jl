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
  and writes the combined features of the two channels under a stem ending
  in `_ae`, with one PSD column per channel (`[preprocessing]
  channel_combination`: `"max"`, the default, the value of every feature
  farthest towards a signal among the channels; `"mean"`, the features of
  the channel-averaged periodogram); the labelling stage
  adds the onset of the A and E network (`signal_start_index_ae`,
  `label_peak_snr_ae`) from the root of the summed squared window SNRs.
  `"AET"` is accepted by the labelling stage, which sets the three-channel
  onset to the AE onset and says so, and refused by the pre-processing
  stage: no features of the T channel are defined (a veto on its band
  powers was examined on the LDC-2b records and not adopted). `whitening_psd` takes
  the `channel` and refuses an analytic PSD for T. The mode `"A"` leaves
  every product as it was. For the streamed replay of several channels:
  `channel_record` (the channels of a TDI product in single precision, the
  content a `ScheduledRecordRun` serves along the delivery of a mission that
  carried its A channel), `whitening_psd_from_sidecar` returning one PSD
  per channel of a multichannel product, and `mode_events` (the event table
  with the onset of a channel set).
- Records with gaps: `preprocess_record` conditions every stretch between
  samples marked `NaN` on its own (`stretch_whitening_psd`: the Welch
  estimate pooled over the stretches), keeps the windows of the record's
  grid that lie inside a stretch less the edge margin at both ends of
  each, and lists the stretches in the sidecar (`stretches`, `gap_samples`,
  schema 2). A record without gaps gives the product it gave before.

### Changed (relative to the layer inside MilliHertzQML.jl)
- `figure_mission_trace` takes `score_label`, `score_name` and
  `score_range`; its score axis spans the scores and the threshold unless
  `score_range` is given, instead of a classifier probability in [0, 1].
