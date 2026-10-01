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
| Stages | `generate_telemetry`, `preprocess_record`, `label_truth_stream`, `export_telemetry_payload`, each driven by a TOML configuration (`generation_settings`, `preprocessing_settings`, `ldc_settings`, `telemetry_settings`) |
| Extensions | DeepSpaceTelemetry (`open_telemetry_run`: a producer run directory as a StreamingInference run), CurvatureDistinguishability (constellation response), CairoMakie (`figure_mission_trace`, `figure_telemetry_trace`) |

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
