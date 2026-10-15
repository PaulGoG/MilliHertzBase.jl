# MilliHertzBase.jl

Gravitational-wave layer for the analysis of telemetry of the Laser
Interferometer Space Antenna (LISA), built on the domain-general
[StreamingInference.jl](https://github.com/PaulGoG/StreamingInference.jl):
noise models, waveforms and detector response for massive black hole
binaries, the products of the LISA Data Challenge (LDC), the pipeline
stages that turn them into labelled, whitened records, and the payload of
the DeepSpaceTelemetry producer, a simulator of the telemetry downlink of
a spacecraft. LISA observes through time-delay interferometry (TDI),
combinations of its laser links, time-shifted by the light travel times
along the arms, in which the laser frequency noise cancels.

| Part | Contents |
|---|---|
| Noise | `lisa_noise_psd`, `instrument_psd`, `confusion_psd` (Robson, Cornish & Liu 2019, doi:10.1088/1361-6382/ab1101); the analytic TDI noise of the LDC toolbox, `ldc_tdi_psd`, `ldc_confusion_psd`; `channel_noise_psd` |
| Waveforms | IMRPhenomA (Ajith et al. 2008, doi:10.1103/PhysRevD.77.104017): `phenoma_parameters`, `phenoma_spectrum`, `phenoma_series`, `phenoma_waveform`, `phenoma_physical_amplitude`, `phenoma_arrival_delay` |
| Detector response | `AbstractDetectorResponse`, `SkyAveragedResponse`, `detector_response`; the constellation response `lisa_response` through the CurvatureDistinguishability extension |
| LDC products | `read_tdi` (one object, or the sum of the component streams named by `[preprocessing] tdi_components`), `tdi_to_aet`, `read_catalog`, `catalog_events`, `whitening_psd`, `whitening_psd_from_sidecar` |
| Labels | `windowed_snr`, `whitened_window_snr`, `snr_peaks`, `detectable_span`, `detectable_spans`, `signal_onsets` |
| Stages | `generate_telemetry`, `preprocess_record`, `label_truth_stream`, `export_telemetry_payload`, each driven by a TOML configuration (`generation_settings`, `preprocessing_settings`, `ldc_settings`, `telemetry_settings`, `tdi_settings`); the labelling measures the signal onset against the noise of the observed record (`[ldc] psd_model = "record"`, the default) or against an analytic TDI noise model |
| Channel modes | `[tdi] channels = "A" \| "AE" \| "AET"` (`tdi_settings`, `channel_names`, `channel_suffix`), recorded in every product; `channel_record`, `mode_events` for the replay of several channels |
| Telemetry producer | `export_telemetry_payload`: the A channel as one column `Amplitude`, or under `"AE"` and `"AET"` the columns `A`, `E` (and `T`) under one link accounting (DeepSpaceTelemetry 2.6 or later); the runs are read by StreamingInference's DeepSpaceTelemetry extension (`open_telemetry_run`, re-exported, `columns` selecting the payload columns) |
| Extensions | CurvatureDistinguishability (constellation response), CairoMakie (`figure_mission_trace`, `figure_telemetry_trace`) |

## Installation and status

The package requires Julia 1.13 or later, is not registered and has no
release yet (version 0.1.0-DEV on `main`). An environment adds
StreamingInference.jl by URL at the commit recorded under `[sources]` in
`Project.toml`, then this package:

```julia
using Pkg
Pkg.add(url = "https://github.com/PaulGoG/StreamingInference.jl",
        rev = "e6c25c1ad4fdcb5e6e76bfb83b0f83d5ff4945d8")
Pkg.add(url = "https://github.com/PaulGoG/MilliHertzBase.jl")
```

## Channel modes

A TDI record holds the Michelson-type combinations X, Y, Z; the stages
work on the noise-orthogonal combinations A, E, T ([`tdi_to_aet`](@ref)).
The mode is set once, under `[tdi] channels`, and every product records it
in its sidecar (`[product] channels`).

- `"A"`, the default: the single channel A, under product stems without a
  suffix.
- `"AE"`: [`preprocess_record`](@ref) whitens A and E each by its own
  power spectral density (PSD) and combines the features of the two channels into as many as the A mode
  has; the product stems gain `_ae`. `[preprocessing] channel_combination`
  selects the combination: `"max"` (default) keeps of every feature the
  value farthest towards a signal — the larger band power and spread, the
  smaller entropy — so that a source one channel sees is not diluted by the
  other; `"mean"` takes the features of the averaged periodogram, the excess
  power of the network, which is the better statistic only for a source
  split equally between the channels. [`label_truth_stream`](@ref) adds the
  onset of a detector that reads both channels, from the network
  signal-to-noise ratio (SNR) ``\rho_{AE}^2 = \rho_A^2 + \rho_E^2`` (orthogonal noise, Prince et al.
  2002, doi:10.1103/PhysRevD.66.122002), as `signal_start_index_ae`.
- `"AET"`: no features of the T channel are defined, and the
  pre-processing refuses the mode; the labelling stage sets the
  three-channel onset to the AE onset and records that it did, and the
  payload export writes the column `T`. The response of T to gravitational
  waves is strongly suppressed relative to A and E below about 10 mHz.

The signal onset from which alerts are credited is the first window in
which the truth stream reaches `[ldc] label_snr_threshold`, 3 by default.
By default (`psd_model = "record"`) the truth is conditioned as the
pre-processing stage conditions the observed record (`record_file`, else
the file of the truth stream) — high-passed and whitened by the record's
own PSD, the Galactic foreground included — and the SNR of a window is
the norm of the whitened signal in it: the signal as the detector sees
it, against the noise it faces. With the name of an analytic TDI PSD
(`"sangria"`, `"spritz"`, …) the window SNR is the matched-filter SNR of
the raw truth against that instrument noise; a threshold of 5 there
corresponds to about 3 against the record.

A record with gaps — samples marked `NaN`, as in the LDC-2b (Spritz)
products — is pre-processed stretch by stretch: every stretch between two
gaps is high-passed and whitened on its own, the Welch estimate is pooled
over the stretches so that no segment spans a gap, and the windows are
those of the grid of the record that lie inside a stretch, less the edge
margin at both ends of every stretch. The sidecar of such a product lists
the stretches (`stretches`, with `gap_samples`, under schema 2), and
`window_indices` of StreamingInference.jl gives the record window of every
row.

## Telemetry payload and replay

The payload of the telemetry producer ([`export_telemetry_payload`](@ref))
follows the channel mode: the A channel as one column `Amplitude`, or
under `"AE"` and `"AET"` the columns `A`, `E` (and `T`), which the
producer (DeepSpaceTelemetry 2.6 or later) carries as one payload — one
batch, one transfer, one loss for all columns. The delivery of a batch is
then common to its channels by construction, and a replay reads them from
the run (`open_telemetry_run(run_dir; columns = ["A", "E"])`).

A mission that carried the A channel alone can be replayed on A and E.
StreamingInference's `ScheduledRecordRun` serves every delivered batch
from the TDI record ([`channel_record`](@ref)), after checking its A
column against the payload the mission carried. This assumes that E would
have been delivered with A, which holds on LISA, where all TDI
combinations are formed on the ground from the same telemetry; the link of
such a mission was sized for one channel. [`mode_events`](@ref) returns
the event table with the onset of the channel set a detector reads.

[`whitening_psd_from_sidecar`](@ref) returns the whitening PSD recorded
in the sidecar of a feature product, one PSD per channel for a
multichannel product.

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

The [API reference](api.md) lists every name; the streaming replay, the
estimator interface and the evaluation are documented in the
[manual of StreamingInference.jl](https://PaulGoG.github.io/StreamingInference.jl/dev/).
