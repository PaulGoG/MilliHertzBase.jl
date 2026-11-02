# Changelog

All notable changes to this package are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- The test environment pins DeepSpaceTelemetry 3.1.1, whose installed copies
  are stamped clean again (3.1.0 left the tracked `data/` root out of its
  identity hash); the suite asserts `git_dirty == false` once more.

## [0.2.0] — 2026-10-31

### Breaking
- A record simulated on the sky-averaged response is written as
  `X = -h/√2`, `Y = 0`, `Z = h/√2` instead of `X = 0`, `Z = √2 h`: E and T
  recombine to zero, A to the same samples, bit for bit. Simulated records
  carry their channel set as the attribute `channels` of `obs/tdi` (`"A"`,
  or `"AE"` under the constellation response), and `preprocess_record`,
  `export_telemetry_payload`, `channel_record` and the record PSD of
  `label_truth_stream` refuse a wider channel mode on such a record
  (`check_recorded_channels`).
- Fifteen names are public and no longer exported: `phenoma_amplitude`,
  `phenoma_phase`, `phenoma_group_delay`, `phenoma_start_frequency`,
  `inverse_segment`, `channel_catalog`, `draw_extrinsic`, `channel_count`,
  `source_frame`, `project_spectrum`, `project_series`, `catalog_events`,
  `samples_per_batch`, `record_groups`, `whitened_window_snr`.
- `[telemetry] producer_compat` defaults to `"2.6"`, the oldest producer
  whose runs StreamingInference 0.2.0 opens (DeepSpaceTelemetryReader 3.1,
  the reader package of DeepSpaceTelemetry); a value that is not a version
  string, or one below 2.6.0, is refused on load.
- Values that failed only when used are refused on load: `[preprocessing]
  ldc_model` and `[ldc] psd_model` outside the model names of the LDC
  toolbox (`LDC_MODELS`; `"record"` for `psd_model`), and `[preprocessing]
  ldc_observation_years` and `[ldc] observation_years` other than 0 or
  0.25–10 yr. `phenoma_spectrum` takes `nyquist_taper` in [0.3, 1], the
  bound of `[generation] nyquist_taper` (`NYQUIST_TAPER_RANGE`).
- `whitening_psd_from_sidecar` refuses a sidecar that does not record
  `channels`.

### Added
- `[generation] gb_frequency_range_hz` (default `[1e-4, 1e-2]`),
  `emri_frequency_range_hz` (`[1e-3, 5e-3]`), `emri_drift_range_hz_per_s`
  (`[1e-9, 1e-8]`), `coalescence_fraction_range` (`[0.1, 0.9]`) and
  `mbhb_duration_max_fraction` (`0.4`), formerly fixed in the code; the
  defaults reproduce the records of 0.1.0 bit for bit.
- The docstrings of the settings functions tabulate the keys of their
  section with default, unit and allowed values.
- Tests of the default simulator path (`generate_telemetry` on the
  sky-averaged response): the catalogue SNR against the injected samples,
  the label span, reproduction from the seed, the channel set of the
  record, and the 509 windows of the README example.

### Changed
- `samples_per_batch` applies the integrality rule of the producer through
  `RunGeometry` of StreamingInference: a whole number of samples per batch
  (0.2 Hz, 52 s and 10 segments give 104 rows), where a whole number per
  segment was required.
- `channel_record` takes a vector of component objects as `group`, as
  `read_tdi` does.
- `export_telemetry_payload` and `label_truth_stream` check the memory
  before the read, on the dataset extents of the record or the rows of a
  truth CSV.
- `figure_mission_trace` names its second argument `scores`.
- One PSD-kind dispatch, `stretch_whitening_psd`, of which `whitening_psd`
  is the one-stretch case; `analytic_psd` builds the analytic kinds for the
  pre-processor and the sidecar reader, and `michelson_channel_psd` the
  product R(f)·Sₙ(f). One conditioning path for records with and without
  gaps (`record_features`). `detectable_span` of one series forwards to the
  tuple method. The MBHB injectors share `draw_mbhb_intrinsics` and the
  injectors `check_injection_arguments`; the stages share
  `check_outputs_distinct`. The products are unchanged bit for bit.
- Pins: StreamingInference 0.2.0; in the test environment
  DeepSpaceTelemetry 3.1.0 and CurvatureDistinguishability 2.1.1, whose
  `[compat]` entry is `2.1`. The test environment carries `[compat]`
  entries, and the export test runs the producer under a run root of its
  own (`run_mission(...; data_root)`).
- README: the short tree follows the first paragraph, and the status
  section states the state of the components. The manual names the
  installation section "Installation".
- Docstrings, comments and documents: the T channel is "strongly
  suppressed" throughout, and the analytic T PSD is refused on the
  measured departure of the T noise from it; the Sangria threshold
  equivalence is stated for the Sangria blind year; the memory pre-flight,
  the noise PSD and the catalogue schema of `generate_telemetry` under the
  constellation response; that the equal-arm first-generation PSDs are the
  TDI 1.5 of the LDC; identifiers of Rubbo, Cornish & Poujade (2004),
  Marsat & Baker (2018) and Isfan et al. (2025); keywords of this package
  in place of command-line flags of MilliHertzQML.jl; wording.

### Removed
- The dependencies DrWatson and LinearAlgebra, which the package did not
  use.
- An unreachable branch of `label_truth_stream`.

### Fixed
- `.gitignore` ignores `/data/` and `/models/`, where the stages write
  under the default paths; Dependabot watches the `test/` and `docs/`
  environments.

## [0.1.0] — 2026-10-15

### Added
- `[preprocessing] tdi_components` (`preprocessing_settings`,
  `record_groups`): a record read as the sum of several HDF5 component
  streams over their common span (`read_tdi` with a vector of objects;
  equal sampling step and time samples required, a longer component
  trimmed with a warning), the layout of the LDC products distributed as
  component streams (LDC-1b Yorsh); the pre-processing, payload-export and
  labelling stages read the configured components, and the product's
  parameters record the list.
- `[telemetry] alert_confirmation_persistence` (`telemetry_settings`): 0,
  no confirmation tier, or a number of consecutive alarmed windows that
  confirms an alert, above both `alert_persistence` and the overlap
  `window_size ÷ step_size` of the `[preprocessing]` windows; the replay
  passes it to `alert_latency_table` of StreamingInference.
- The labelling stage scans the truth stream against the record's own
  noise: `[ldc] psd_model = "record"` conditions the truth as the
  pre-processing stage conditions the observed record (`[ldc]
  record_file` or the keyword `record_file`, else the file of the truth
  stream) — high-passed, whitened by the record's PSD of the configured
  kind, stretch by stretch between gaps — and takes the norm of the
  whitened signal in every window as its SNR (`record_truth_snr`,
  `whitened_window_snr`), the Galactic foreground included in the noise.
  The analytic rule (`analytic_truth_snr`) remains available; the snapshot
  records the PSD of either (`psd_description`, `record_source`).
- The payload export follows the channel mode (`channels`, default
  `[tdi] channels`): the A channel stays the producer's one `Amplitude`
  column, and the A and E network (`"AE"`, likewise `"AET"`) is written as
  named columns `A`, `E` of `<prefix>_ae_payload.csv` with
  `external_data_columns` in the scenario fragment, which DeepSpaceTelemetry
  2.6 or later carries as one payload under one link accounting — one
  batch, one transfer, one loss for both channels. The fragment records
  the mode and the columns under `[payload]`; the stage returns `columns`.

### Changed
- Producer runs are read by StreamingInference.jl: `open_telemetry_run` is
  StreamingInference's, re-exported here, built on the producer's
  reference run adapter (DeepSpaceTelemetry 2.6 or later), and serves the
  payload columns of a run that carries several by name (`columns`).
  DeepSpaceTelemetry is no longer a weak dependency of this package; its
  test environment keeps it for the export tests against the producer.
- The default labelling rule is the record's own noise at a threshold of
  3 (`[ldc] psd_model = "record"`, `label_snr_threshold = 3`), in place of
  the analytic instrument PSD at 5, whose threshold against the noise the
  detector faces was about 3 for the Sangria blind year and 1–2 at the
  peak; the analytic rule stays available under its name.
- `read_catalog` reads a scalar compound dataset, the one-source catalogue
  of an LDC-2b record (`sky/cat`), as a table of one row.
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
  stage: no features of the T channel are defined. `whitening_psd` takes
  the `channel` and refuses an analytic PSD for T. For the streamed replay
  of several channels: `channel_record` (the channels of a TDI product in single precision, the
  content a `ScheduledRecordRun` serves along the delivery of a mission that
  carried its A channel), `whitening_psd_from_sidecar` returning one PSD
  per channel of a multichannel product, and `mode_events` (the event table
  with the onset of a channel set).
- Records with gaps: `preprocess_record` conditions every stretch between
  samples marked `NaN` on its own (`stretch_whitening_psd`: the Welch
  estimate pooled over the stretches), keeps the windows of the record's
  grid that lie inside a stretch less the edge margin at both ends of
  each, and lists the stretches in the sidecar (`stretches`, `gap_samples`,
  schema 2).

### Changed (relative to the layer inside MilliHertzQML.jl)
- `figure_mission_trace` takes `score_label`, `score_name` and
  `score_range`; its score axis spans the scores and the threshold unless
  `score_range` is given, instead of a classifier probability in [0, 1].
