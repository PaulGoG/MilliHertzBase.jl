"""
    MilliHertzBase

Gravitational-wave layer of the pipeline, built on the domain-general
[`StreamingInference`](@ref) layer. It holds the LISA noise model and
detector response, IMRPhenomA waveforms, the readers of LDC products and
TDI channels, the whitening PSD of a TDI record, and the generation,
pre-processing, labelling and payload-export stages. The payload goes to
the DeepSpaceTelemetry producer, whose runs StreamingInference reads
([`open_telemetry_run`](@ref), re-exported).
"""
module MilliHertzBase

using StreamingInference:
    StreamingInference,
    RunGeometry,
    TIMER,
    analysis_band,
    backup_existing!,
    cfgget,
    check_memory,
    content_digest,
    contiguous_runs,
    feature_names,
    finite_stretches,
    fixed_spans,
    highpass_record,
    interpolated_psd,
    matched_filter_snr,
    new_run_id,
    open_telemetry_run,
    override,
    parameter_digest,
    pipeline_paths,
    place_signal!,
    product_table,
    provenance_path,
    record_memory_estimate_gib,
    resolvepath,
    resource_settings,
    rootrelative,
    scale_to_snr,
    section,
    smooth_psd,
    span_labels,
    synthesize_noise,
    welch_psd,
    whiten_record,
    window_features,
    window_labels,
    write_csv,
    write_toml
using StreamingInference: check_band_edges, edge_margin_windows, window_count
using CSV: CSV
using DataFrames: DataFrames, DataFrame, nrow
using Dates: Dates
using FFTW: irfft, rfftfreq
using HDF5: HDF5, attributes, h5open
using Random: Random, AbstractRNG, Xoshiro
using TOML: TOML
using TimerOutputs: @timeit

export lisa_noise_psd, instrument_psd, confusion_psd, detectable_span, phenoma_parameters
export phenoma_waveform, phenoma_spectrum, phenoma_series
export phenoma_physical_amplitude, phenoma_arrival_delay, AbstractDetectorResponse
export SkyAveragedResponse, GIGAPARSEC_SEC, sky_averaged_response
export channel_noise_psd, lisa_response, detector_response, ldc_tdi_psd
export ldc_confusion_psd, tdi_to_aet, read_tdi, read_catalog, windowed_snr, snr_peaks
export detectable_spans, signal_onsets, generation_settings, preprocessing_settings
export ldc_settings, telemetry_settings, generate_telemetry, preprocess_record
export tdi_settings, channel_names, channel_suffix, CHANNEL_MODES
export channel_record, mode_events
export label_truth_stream, whitening_psd, figure_mission_trace
export figure_telemetry_trace, whitening_psd_from_sidecar, open_telemetry_run
export export_telemetry_payload
public L_ARM, C_LIGHT, F_STAR
# Building blocks of the waveforms, the response, the generator and the
# stages, public but not exported
public phenoma_amplitude, phenoma_phase, phenoma_group_delay, phenoma_start_frequency
public inverse_segment, channel_catalog, draw_extrinsic, channel_count, source_frame
public project_spectrum, project_series, catalog_events, samples_per_batch
public record_groups, whitened_window_snr

include("config.jl")
include("noise.jl")
include("response.jl")
include("waveforms.jl")
include("ldc.jl")
include("whitening.jl")
include("visualization.jl")
include("stages/generation.jl")
include("stages/preprocessing.jl")
include("stages/labeling.jl")
include("stages/export_payload.jl")

end # module
