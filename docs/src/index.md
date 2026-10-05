# MilliHertzBase.jl

Gravitational-wave layer for the analysis of LISA telemetry, built on the
domain-general [StreamingInference.jl](https://github.com/PaulGoG/StreamingInference.jl):
noise models, waveforms and detector response for massive black hole
binaries, the products of the LISA Data Challenge, the pipeline stages that
turn them into labelled, whitened records, and the coupling to the
DeepSpaceTelemetry producer.

| Part | Contents |
|---|---|
| Noise | `lisa_noise_psd`, `instrument_psd`, `confusion_psd` (Robson, Cornish & Liu 2019, doi:10.1088/1361-6382/ab1101); the analytic TDI noise of the LDC toolbox, `ldc_tdi_psd`, `ldc_confusion_psd`; `channel_noise_psd` |
| Waveforms | IMRPhenomA (Ajith et al. 2008, doi:10.1103/PhysRevD.77.104017): `phenoma_parameters`, `phenoma_spectrum`, `phenoma_series`, `phenoma_waveform`, `phenoma_physical_amplitude`, `phenoma_arrival_delay` |
| Detector response | `AbstractDetectorResponse`, `SkyAveragedResponse`, `detector_response`; the constellation response `lisa_response` through the CurvatureDistinguishability extension |
| LDC products | `read_tdi`, `tdi_to_aet`, `read_catalog`, `catalog_events`, `whitening_psd`, `whitening_psd_from_sidecar` |
| Labels | `windowed_snr`, `snr_peaks`, `detectable_span`, `detectable_spans`, `signal_onsets` |
| Stages | `generate_telemetry`, `preprocess_record`, `label_truth_stream`, `export_telemetry_payload`, each driven by a TOML configuration (`generation_settings`, `preprocessing_settings`, `ldc_settings`, `telemetry_settings`, `tdi_settings`) |
| Channel modes | `[tdi] channels = "A" \| "AE" \| "AET"` (`tdi_settings`, `channel_names`, `channel_suffix`), recorded in every product; `channel_record`, `mode_events` for the replay of several channels |
| Extensions | DeepSpaceTelemetry (`open_telemetry_run`: a producer run directory as a StreamingInference run), CurvatureDistinguishability (constellation response), CairoMakie (`figure_mission_trace`, `figure_telemetry_trace`) |

## Channel modes

A TDI record holds the Michelson combinations X, Y, Z; the stages work on
the noise-orthogonal combinations A, E, T ([`tdi_to_aet`](@ref)). The mode
is set once, under `[tdi] channels`, and every product records it in its
sidecar (`[product] channels`).

- `"A"`, the default and the mode of every product made before the modes
  existed: the single channel, under the product names used so far.
- `"AE"`: [`preprocess_record`](@ref) whitens A and E each by its own PSD
  and combines the features of the two channels into as many as the A mode
  has; the product stems gain `_ae`. `[preprocessing] channel_combination`
  selects the combination: `"max"` (default) keeps of every feature the
  value farthest towards a signal — the larger band power and spread, the
  smaller entropy — so that a source one channel sees is not diluted by the
  other; `"mean"` takes the features of the averaged periodogram, the excess
  power of the network, which is the better statistic only for a source
  split equally between the channels. [`label_truth_stream`](@ref) adds the onset of a detector
  that reads both channels, from the network SNR
  ``\\rho_{AE}^2 = \\rho_A^2 + \\rho_E^2`` (orthogonal noise, Prince et al.
  2002, doi:10.1103/PhysRevD.66.122002), as `signal_start_index_ae`.
- `"AET"`: on equal arms T carries no gravitational-wave signal of
  massive-black-hole binaries below about 10 mHz, and its analytic
  equal-arm PSD is wrong below a few mHz, so T is whitened by a measured
  PSD only. No features of T are defined. A veto on its band powers
  against instrumental artefacts was examined on the LDC-2b (Spritz)
  records and not adopted: on arms of unequal length T responds to the
  signal below 1 mHz, and at higher frequencies it did not separate the
  glitches that raise alarms from noise. Pre-processing refuses the mode,
  and the labelling stage sets the three-channel onset to the AE onset and
  records that it did.

The telemetry producer carries one payload column, the A channel
([`export_telemetry_payload`](@ref)). A streamed replay of several channels
takes the delivery of such a mission and serves the channels of every
delivered batch from the TDI record itself ([`channel_record`](@ref) through
StreamingInference's `ScheduledRecordRun`, which refuses a record whose A
channel is not the payload the mission carried): the delivery of a batch is
taken to be common to its channels, and the link of the mission was sized
for one. [`whitening_psd_from_sidecar`](@ref) returns one PSD per channel
for a multichannel product, and [`mode_events`](@ref) the event table with
the onset of the channel set a detector reads.

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

The [API reference](api.md) lists every name; the streaming replay, the
estimator interface and the evaluation are documented in the manual of
StreamingInference.jl.
