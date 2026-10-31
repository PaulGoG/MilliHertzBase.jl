# Settings of the gravitational-wave sections: synthetic telemetry
# generation, pre-processing of TDI products, the TDI channel mode, truth
# labelling of LDC products, and the telemetry payload export and replay.

"""
    parameter_range(section, key, default; lower = -Inf, upper = Inf, positive = false)
        -> Tuple{Float64,Float64}

The two-element range `[a, b]` under `key` of a configuration section, with
`lower ≤ a ≤ b ≤ upper`, and `a > 0` when `positive`; `ArgumentError`
naming the key otherwise.
"""
function parameter_range(
    section::AbstractDict,
    key::AbstractString,
    default;
    lower::Real = -Inf,
    upper::Real = Inf,
    positive::Bool = false,
)
    r = cfgget(section, key, default; type = AbstractVector)
    valid =
        length(r) == 2 &&
        all(x -> x isa Real, r) &&
        lower <= r[1] <= r[2] <= upper &&
        (!positive || r[1] > 0)
    valid || throw(
        ArgumentError(
            "configuration key `$key` = $(repr(r)); expected two values a ≤ b with " *
            (positive ? "0 < a" : "$lower ≤ a") *
            (isfinite(upper) ? " and b ≤ $upper." : "."),
        ),
    )
    return (Float64(r[1]), Float64(r[2]))
end

"""
    check_confusion_years(key, years) -> Float64

The observation time [yr] of the confusion term of the LDC noise model: 0,
no confusion term, or a value in the range 0.25–10 yr of the fit
([`ldc_confusion_psd`](@ref)); `ArgumentError` naming the key otherwise.
"""
function check_confusion_years(key::AbstractString, years::Real)
    (years == 0 || 0.25 <= years <= 10) || throw(
        ArgumentError(
            "configuration key `$key` = $years; expected 0 (no confusion term) or a " *
            "value in [0.25, 10] years.",
        ),
    )
    return Float64(years)
end

"""
    generation_settings(config) -> NamedTuple

Validated `[generation]` parameters of the telemetry simulator
([`generate_telemetry`](@ref)). A missing key takes its default; a value
outside its allowed range is refused on load.

| Key | Default | Unit | Allowed values |
|:----|:--------|:-----|:---------------|
| `days` | 30 | d | ≥ 10⁻⁶ |
| `fs` | 0.2 | Hz | ≥ 10⁻⁶ |
| `n_mbhb` | 5 | | ≥ 0 |
| `n_gbs` | 50 | | ≥ 0 |
| `n_emris` | 5 | | ≥ 0 |
| `output` | `"data/inputs/simulated_telemetry_complex.h5"` | | path ending in `.h5` |
| `seed` | 42 | | integer |
| `observation_years` | 1 | yr | 0.5, 1, 2, 4 (confusion fit of [`confusion_psd`](@ref)) |
| `snr_min`, `snr_max` | 8, 50 | | `0.001 ≤ snr_min ≤ snr_max` (MBHB matched-filter SNR) |
| `gb_snr_min`, `gb_snr_max` | 1, 10 | | `0.001 ≤ gb_snr_min ≤ gb_snr_max` (Galactic binaries) |
| `emri_snr_min`, `emri_snr_max` | 2, 10 | | `0.001 ≤ emri_snr_min ≤ emri_snr_max` |
| `gb_frequency_range_hz` | [10⁻⁴, 10⁻²] | Hz | `0 < a ≤ b`; frequencies on a grid of step 10 μHz |
| `emri_frequency_range_hz` | [10⁻³, 5 × 10⁻³] | Hz | `0 < a ≤ b`; start frequencies on a grid of step 0.5 mHz |
| `emri_drift_range_hz_per_s` | [10⁻⁹, 10⁻⁸] | Hz s⁻¹ | `0 ≤ a ≤ b`; drifts on a grid of step 0.1 nHz s⁻¹ |
| `coalescence_fraction_range` | [0.1, 0.9] | | `0 ≤ a ≤ b ≤ 1`; fraction of the record holding the coalescences |
| `mbhb_duration_days` | 2 | d | ≥ 0.001 |
| `mbhb_duration_max_fraction` | 0.4 | | in (0, 1]; cap of the injection length relative to the record |
| `mbhb_total_mass_min`, `mbhb_total_mass_max` | 10⁵, 10⁷ | M⊙ | `1 ≤ min ≤ max` (detector frame) |
| `mbhb_mass_ratio_max` | 10 | | ≥ 1 |
| `mbhb_distance_min_gpc`, `mbhb_distance_max_gpc` | 1, 50 | Gpc | `10⁻⁶ ≤ min ≤ max`; `"lisa"` response only |
| `nyquist_taper` | 0.9 | | in [0.3, 1]; fraction of the Nyquist frequency ([`phenoma_spectrum`](@ref)) |
| `noise_f_min_hz` | 10⁻⁵ | Hz | ≥ 0 |
| `label_span` | `"detectable"` | | `"detectable"`, `"injection"`, `"fixed"` |
| `label_snr_threshold` | 5 | | ≥ 0.001 |
| `label_window_size` | 1000 | samples | ≥ 2 |
| `label_step` | 10 | samples | ≥ 1 |
| `label_before_sec`, `label_after_sec` | 43200, 3600 | s | ≥ 0; `"fixed"` spans only |
| `response` | `"sky_averaged"` | | `"sky_averaged"`, `"lisa"` ([`detector_response`](@ref)) |
| `label_channel` | `"A"` | | `"A"`, `"E"`, `"network"`; `"lisa"` response only |
| `orbit_phase`, `constellation_phase` | 0, 0 | rad | any; `"lisa"` response only |
"""
function generation_settings(config::AbstractDict)
    g = section(config, "generation")
    snr_min = cfgget(g, "snr_min", 8.0; type = Float64, min = 1e-3)
    gb_snr_min = cfgget(g, "gb_snr_min", 1.0; type = Float64, min = 1e-3)
    emri_snr_min = cfgget(g, "emri_snr_min", 2.0; type = Float64, min = 1e-3)
    mass_min = cfgget(g, "mbhb_total_mass_min", 1e5; type = Float64, min = 1.0)
    distance_min = cfgget(g, "mbhb_distance_min_gpc", 1.0; type = Float64, min = 1e-6)
    duration_max_fraction =
        cfgget(g, "mbhb_duration_max_fraction", 0.4; type = Float64, max = 1.0)
    duration_max_fraction > 0 || throw(
        ArgumentError(
            "configuration key `mbhb_duration_max_fraction` = $duration_max_fraction; " *
            "must lie in (0, 1].",
        ),
    )
    return (
        days = cfgget(g, "days", 30.0; type = Float64, min = 1e-6),
        fs = cfgget(g, "fs", 0.2; type = Float64, min = 1e-6),
        n_mbhb = cfgget(g, "n_mbhb", 5; type = Int, min = 0),
        n_gbs = cfgget(g, "n_gbs", 50; type = Int, min = 0),
        n_emris = cfgget(g, "n_emris", 5; type = Int, min = 0),
        output = resolvepath(
            cfgget(
                g,
                "output",
                "data/inputs/simulated_telemetry_complex.h5";
                type = String,
            ),
        ),
        seed = cfgget(g, "seed", 42; type = Int),
        observation_years = cfgget(
            g,
            "observation_years",
            1.0;
            type = Float64,
            choices = (0.5, 1.0, 2.0, 4.0),
        ),
        snr_min = snr_min,
        snr_max = cfgget(g, "snr_max", 50.0; type = Float64, min = snr_min),
        gb_snr_min = gb_snr_min,
        gb_snr_max = cfgget(g, "gb_snr_max", 10.0; type = Float64, min = gb_snr_min),
        emri_snr_min = emri_snr_min,
        emri_snr_max = cfgget(g, "emri_snr_max", 10.0; type = Float64, min = emri_snr_min),
        gb_frequency_range_hz = parameter_range(
            g,
            "gb_frequency_range_hz",
            [1e-4, 1e-2];
            positive = true,
        ),
        emri_frequency_range_hz = parameter_range(
            g,
            "emri_frequency_range_hz",
            [1e-3, 5e-3];
            positive = true,
        ),
        emri_drift_range_hz_per_s = parameter_range(
            g,
            "emri_drift_range_hz_per_s",
            [1e-9, 1e-8];
            lower = 0.0,
        ),
        coalescence_fraction_range = parameter_range(
            g,
            "coalescence_fraction_range",
            [0.1, 0.9];
            lower = 0.0,
            upper = 1.0,
        ),
        label_before_sec = cfgget(
            g,
            "label_before_sec",
            43200.0;
            type = Float64,
            min = 0.0,
        ),
        label_after_sec = cfgget(g, "label_after_sec", 3600.0; type = Float64, min = 0.0),
        mbhb_duration_days = cfgget(
            g,
            "mbhb_duration_days",
            2.0;
            type = Float64,
            min = 1e-3,
        ),
        mbhb_duration_max_fraction = duration_max_fraction,
        noise_f_min_hz = cfgget(g, "noise_f_min_hz", 1e-5; type = Float64, min = 0.0),
        mbhb_total_mass_min = mass_min,
        mbhb_total_mass_max = cfgget(
            g,
            "mbhb_total_mass_max",
            1e7;
            type = Float64,
            min = mass_min,
        ),
        mbhb_mass_ratio_max = cfgget(
            g,
            "mbhb_mass_ratio_max",
            10.0;
            type = Float64,
            min = 1.0,
        ),
        nyquist_taper = cfgget(
            g,
            "nyquist_taper",
            0.9;
            type = Float64,
            min = first(NYQUIST_TAPER_RANGE),
            max = last(NYQUIST_TAPER_RANGE),
        ),
        label_span = cfgget(
            g,
            "label_span",
            "detectable";
            type = String,
            choices = ("detectable", "injection", "fixed"),
        ),
        label_snr_threshold = cfgget(
            g,
            "label_snr_threshold",
            5.0;
            type = Float64,
            min = 1e-3,
        ),
        label_window_size = cfgget(g, "label_window_size", 1000; type = Int, min = 2),
        label_step = cfgget(g, "label_step", 10; type = Int, min = 1),
        response = cfgget(
            g,
            "response",
            "sky_averaged";
            type = String,
            choices = ("sky_averaged", "lisa"),
        ),
        mbhb_distance_min_gpc = distance_min,
        mbhb_distance_max_gpc = cfgget(
            g,
            "mbhb_distance_max_gpc",
            50.0;
            type = Float64,
            min = distance_min,
        ),
        label_channel = cfgget(
            g,
            "label_channel",
            "A";
            type = String,
            choices = ("A", "E", "network"),
        ),
        orbit_phase = cfgget(g, "orbit_phase", 0.0; type = Float64),
        constellation_phase = cfgget(g, "constellation_phase", 0.0; type = Float64),
    )
end

"""
    CHANNEL_MODES

The TDI channel modes of `[tdi] channels`: `"A"`, `"AE"`, and `"AET"`.
"""
const CHANNEL_MODES = ("A", "AE", "AET")

"""
    channel_names(mode) -> Tuple of Symbols

The noise-orthogonal TDI combinations of a channel mode, in the order of
the columns of a multichannel record: `(:A,)`, `(:A, :E)` or
`(:A, :E, :T)`.
"""
function channel_names(mode::AbstractString)
    mode == "A" && return (:A,)
    mode == "AE" && return (:A, :E)
    mode == "AET" && return (:A, :E, :T)
    throw(ArgumentError("channels = $(repr(mode)); expected one of $(CHANNEL_MODES)."))
end

"""
    channel_suffix(mode) -> String

Suffix a channel mode adds to the stem of its products: none for `"A"`,
`"_ae"` for `"AE"`, `"_aet"` for `"AET"`.
"""
channel_suffix(mode::AbstractString) =
    length(channel_names(mode)) == 1 ? "" : "_" * lowercase(mode)

"""
    tdi_settings(config) -> NamedTuple

Validated `[tdi]` parameters, the channel mode of every product made from a
TDI record.

| Key | Default | Unit | Allowed values |
|:----|:--------|:-----|:---------------|
| `channels` | `"A"` | | `"A"`, `"AE"`, `"AET"` ([`CHANNEL_MODES`](@ref)) |
"""
function tdi_settings(config::AbstractDict)
    t = section(config, "tdi")
    return (channels = cfgget(t, "channels", "A"; type = String, choices = CHANNEL_MODES),)
end

"""
    check_tdi_components(components) -> Vector{String}

`[preprocessing] tdi_components` validated: every entry a non-empty string,
no entry twice. The empty vector means a record of the single object
`tdi_group`.
"""
function check_tdi_components(components::AbstractVector)
    valid =
        all(c -> c isa AbstractString && !isempty(c), components) && allunique(components)
    valid || throw(
        ArgumentError(
            "configuration key `tdi_components` = $(repr(components)); expected " *
            "distinct non-empty strings.",
        ),
    )
    return String[String(c) for c in components]
end

"""
    preprocessing_settings(config) -> NamedTuple

Validated `[preprocessing]` parameters of the pre-processing stage
([`preprocess_record`](@ref)): input product and TDI group or component
list, window geometry, whitening PSD selection, analysis bands, record
high-pass, and feature set. The other stages read the observed record and
its conditioning from the same section.

| Key | Default | Unit | Allowed values |
|:----|:--------|:-----|:---------------|
| `h5_file` | `"data/inputs/simulated_telemetry_complex.h5"` | | path of the HDF5 TDI product |
| `tdi_group` | `"obs/tdi"` | | group or compound dataset holding `t`, `X`, `Y`, `Z` |
| `tdi_components` | `[]` | | distinct non-empty object names summed into the record ([`record_groups`](@ref)); `[]` reads `tdi_group` |
| `window_size` | 1000 | samples | ≥ 2 |
| `step_size` | 100 | samples | 1 to `window_size` |
| `sample_rate` | absent | Hz | when given, must agree with the file |
| `psd` | `"model"` | | `"model"`, `"channel"`, `"ldc"`, `"welch"`, `"none"` ([`whitening_psd`](@ref)) |
| `observation_years` | 1 | yr | 0.5, 1, 2, 4; `"model"` and `"channel"` |
| `ldc_model` | `"sangria"` | | `"MRD_MFR"`, `"MRDv1"`, `"Proposal"`, `"SciRDv1"`, `"sangria"`, `"spritz"`; `"ldc"` only |
| `ldc_tdi2` | `false` | | `true`, `false`; `"ldc"` only |
| `ldc_observation_years` | 0 | yr | 0 (no confusion term) or 0.25–10; `"ldc"` only |
| `welch_segment_length` | 65536 | samples | ≥ 2; `"welch"` only |
| `psd_smoothing_dex` | 0 | dex | ≥ 0, 0 disables; `"welch"` only |
| `feature_set` | `"whitened"` | | `"whitened"`, `"paper"`, `"bands"` |
| `band_edges_hz` | [10⁻³, 5 × 10⁻³, 0.1] | Hz | at least two, strictly ascending, > 0; `"bands"` only |
| `low_band_hz` | [10⁻³, 5 × 10⁻³] | Hz | two, ascending, > 0 |
| `high_band_hz` | [5 × 10⁻³, 0.1] | Hz | two, ascending, > 0 |
| `channel_combination` | `"max"` | | `"max"`, `"mean"`; modes of several channels only |
| `highpass_cutoff_hz` | 5 × 10⁻⁴ | Hz | ≥ 0, 0 disables |
| `highpass_order` | 8 | | ≥ 1 (Butterworth order) |
| `edge_margin` | 0 | window lengths | ≥ 0, dropped at each end of every stretch |
| `output_prefix` | `"telemetry"` | | stem of the products |
"""
function preprocessing_settings(config::AbstractDict)
    p = section(config, "preprocessing")
    window_size = cfgget(p, "window_size", 1000; type = Int, min = 2)
    step_size = cfgget(p, "step_size", 100; type = Int, min = 1)
    step_size <= window_size ||
        throw(ArgumentError("step_size = $step_size exceeds window_size = $window_size."))
    return (
        h5_file = resolvepath(
            cfgget(
                p,
                "h5_file",
                "data/inputs/simulated_telemetry_complex.h5";
                type = String,
            ),
        ),
        tdi_group = cfgget(p, "tdi_group", "obs/tdi"; type = String),
        tdi_components = check_tdi_components(
            cfgget(p, "tdi_components", String[]; type = AbstractVector),
        ),
        window_size = window_size,
        step_size = step_size,
        sample_rate = cfgget(p, "sample_rate", nothing; type = Union{Nothing,Float64}),
        psd = cfgget(
            p,
            "psd",
            "model";
            type = String,
            choices = ("model", "channel", "ldc", "welch", "none"),
        ),
        observation_years = cfgget(
            p,
            "observation_years",
            1.0;
            type = Float64,
            choices = (0.5, 1.0, 2.0, 4.0),
        ),
        ldc_model = cfgget(p, "ldc_model", "sangria"; type = String, choices = LDC_MODELS),
        ldc_tdi2 = cfgget(p, "ldc_tdi2", false; type = Bool),
        ldc_observation_years = check_confusion_years(
            "ldc_observation_years",
            cfgget(p, "ldc_observation_years", 0.0; type = Float64),
        ),
        welch_segment_length = cfgget(
            p,
            "welch_segment_length",
            65536;
            type = Int,
            min = 2,
        ),
        psd_smoothing_dex = cfgget(p, "psd_smoothing_dex", 0.0; type = Float64, min = 0.0),
        feature_set = Symbol(
            cfgget(
                p,
                "feature_set",
                "whitened";
                type = String,
                choices = ("whitened", "paper", "bands"),
            ),
        ),
        band_edges_hz = check_band_edges(
            cfgget(p, "band_edges_hz", [1e-3, 5e-3, 1e-1]; type = AbstractVector),
        ),
        channel_combination = Symbol(
            cfgget(
                p,
                "channel_combination",
                "max";
                type = String,
                choices = ("mean", "max"),
            ),
        ),
        highpass_cutoff_hz = cfgget(
            p,
            "highpass_cutoff_hz",
            5e-4;
            type = Float64,
            min = 0.0,
        ),
        highpass_order = cfgget(p, "highpass_order", 8; type = Int, min = 1),
        edge_margin = cfgget(p, "edge_margin", 0.0; type = Float64, min = 0.0),
        low_band_hz = analysis_band(p, "low_band_hz", [1e-3, 5e-3]),
        high_band_hz = analysis_band(p, "high_band_hz", [5e-3, 1e-1]),
        output_prefix = cfgget(p, "output_prefix", "telemetry"; type = String),
    )
end

"""
    record_groups(settings) -> String or Vector{String}

The HDF5 object(s) a stage reads the observed record from, under the
validated `[preprocessing]` settings: `tdi_components` when that list is
not empty (the record is the sum of the components, [`read_tdi`](@ref)),
else `tdi_group`.
"""
record_groups(settings::NamedTuple) =
    isempty(settings.tdi_components) ? settings.tdi_group : settings.tdi_components

"""
    ldc_settings(config) -> NamedTuple

Validated `[ldc]` parameters of the truth-stream labelling
([`label_truth_stream`](@ref)). `psd_model` is `"record"` (the default):
the whitening PSD of the observed record `record_file` (empty: the file of
the truth stream) under the `[preprocessing]` settings, the noise the
detector faces; or the name of an analytic TDI PSD ([`ldc_tdi_psd`](@ref)),
with which the window SNR is the matched-filter SNR of the raw signal
against that instrument noise; on the Sangria blind year a threshold of 5
there corresponds to about 3 against the record.

| Key | Default | Unit | Allowed values |
|:----|:--------|:-----|:---------------|
| `h5_file` | `""` | | LDC product holding the truth stream; empty: passed to the stage |
| `record_file` | `""` | | observed record of `psd_model = "record"`; empty: the file of the truth stream |
| `truth_group` | `"sky/mbhb/tdi"` | | compound dataset of the signal-only TDI |
| `catalog_group` | `"sky/mbhb/cat"` | | compound dataset of the source catalogue |
| `psd_model` | `"record"` | | `"record"`, or `"MRD_MFR"`, `"MRDv1"`, `"Proposal"`, `"SciRDv1"`, `"sangria"`, `"spritz"` |
| `tdi2` | `false` | | `true`, `false`; analytic PSD only |
| `observation_years` | 0 | yr | 0 (no confusion term) or 0.25–10; analytic PSD only |
| `label_span` | `"fixed"` | | `"fixed"`, `"detectable"` |
| `label_before_sec` | 345600 (4 d) | s | ≥ 0 |
| `label_after_sec` | 1620 (27 min) | s | ≥ 0 |
| `label_snr_threshold` | 3 | | ≥ 10⁻⁶ |
| `label_window_size` | 1000 | samples | ≥ 2 |
| `label_step` | 10 | samples | ≥ 1 |
| `peak_min_separation_sec` | 86400 | s | ≥ 0; mergers located without a catalogue |
| `merger_snr_threshold` | 8 | | ≥ 10⁻⁶; mergers located without a catalogue |
| `precursor_ratio` | 0.1 | | in [0, 1] ([`snr_peaks`](@ref)) |
| `output_prefix` | `"ldc"` | | stem of the products |
"""
function ldc_settings(config::AbstractDict)
    l = section(config, "ldc")
    h5_file = cfgget(l, "h5_file", ""; type = String)
    record_file = cfgget(l, "record_file", ""; type = String)
    return (
        h5_file = isempty(h5_file) ? "" : resolvepath(h5_file),
        record_file = isempty(record_file) ? "" : resolvepath(record_file),
        truth_group = cfgget(l, "truth_group", "sky/mbhb/tdi"; type = String),
        catalog_group = cfgget(l, "catalog_group", "sky/mbhb/cat"; type = String),
        psd_model = cfgget(
            l,
            "psd_model",
            "record";
            type = String,
            choices = ("record", LDC_MODELS...),
        ),
        tdi2 = cfgget(l, "tdi2", false; type = Bool),
        observation_years = check_confusion_years(
            "observation_years",
            cfgget(l, "observation_years", 0.0; type = Float64),
        ),
        label_span = cfgget(
            l,
            "label_span",
            "fixed";
            type = String,
            choices = ("fixed", "detectable"),
        ),
        label_before_sec = cfgget(
            l,
            "label_before_sec",
            4 * 86400.0;
            type = Float64,
            min = 0.0,
        ),
        label_after_sec = cfgget(
            l,
            "label_after_sec",
            27 * 60.0;
            type = Float64,
            min = 0.0,
        ),
        label_snr_threshold = cfgget(
            l,
            "label_snr_threshold",
            3.0;
            type = Float64,
            min = 1e-6,
        ),
        label_window_size = cfgget(l, "label_window_size", 1000; type = Int, min = 2),
        label_step = cfgget(l, "label_step", 10; type = Int, min = 1),
        peak_min_separation_sec = cfgget(
            l,
            "peak_min_separation_sec",
            86400.0;
            type = Float64,
            min = 0.0,
        ),
        merger_snr_threshold = cfgget(
            l,
            "merger_snr_threshold",
            8.0;
            type = Float64,
            min = 1e-6,
        ),
        precursor_ratio = cfgget(
            l,
            "precursor_ratio",
            0.1;
            type = Float64,
            min = 0.0,
            max = 1.0,
        ),
        output_prefix = cfgget(l, "output_prefix", "ldc"; type = String),
    )
end

"""
    telemetry_settings(config) -> NamedTuple

Validated `[telemetry]` parameters of the coupling to a DeepSpaceTelemetry
run: the exported scenario geometry (`segment_duration_sec`, `batch_size`,
`start_sim_time`, `output_prefix`; [`export_telemetry_payload`](@ref)) and
the consumer's replay settings, which the replay scripts of MilliHertzQML.jl
pass to StreamingInference.

| Key | Default | Unit | Allowed values |
|:----|:--------|:-----|:---------------|
| `segment_duration_sec` | 50 | s | ≥ 10⁻⁶ |
| `batch_size` | 10 | segments | ≥ 1 |
| `start_sim_time` | `"2035-01-01T00:00:00"` | | ISO-8601 date and time of the first payload row |
| `output_prefix` | `"telemetry"` | | stem of the payload and the scenario fragment |
| `run_dir` | `""` | | run directory of the producer |
| `mode` | `"replay"` | | `"replay"`, `"live"` |
| `min_coverage` | 1 | | in [10⁻⁶, 1]; delivered fraction of a window's conditioning stretch |
| `tdi_gap_dilation_sec` | 100 | s | ≥ 0; erosion on each side of a lost batch |
| `context_windows` | 4 | window lengths | ≥ 0; delivered context on each side for the whitening |
| `psd_sidecar` | `""` | | feature sidecar of the whitening PSD; empty: that of the training run |
| `psd_mode` | `"sidecar"` | | `"sidecar"`, `"trailing"` |
| `psd_trailing_days` | 30 | d | ≥ 10⁻⁶; delivered record of the `"trailing"` estimate |
| `psd_refresh_days` | 1 | d | ≥ 10⁻⁶; advance after which the `"trailing"` estimate is redone |
| `psd_segment_length` | 65536 | samples | ≥ 2; segment of the `"trailing"` estimate |
| `psd_edge_periods` | 3 | high-pass cutoff periods | ≥ 0; trimmed from each end of a delivered run |
| `poll_interval_sec` | 1 | s | ≥ 10⁻³; `"live"` mode |
| `producer_compat` | `"2.6"` | | version string ≥ 2.6.0, the oldest producer accepted |
| `processing_latency_hours` | 1 | h | ≥ 0; ground processing added to every alert latency |
| `alert_persistence` | 3 | windows | ≥ 1 |
| `alert_confirmation_persistence` | 0 | windows | 0, or above both `alert_persistence` and `window_size ÷ step_size` |
| `alert_crediting` | `"signal"` | | `"signal"`, `"label"` |
| `events_csv` | `""` | | event table of the alert latencies; empty disables |

`alert_confirmation_persistence` is 0 (no confirmation tier) or exceeds
both `alert_persistence` and the overlap `window_size ÷ step_size` of the
`[preprocessing]` windows, so that a confirmed alert rests on alarms of
windows sharing no sample (`alert_latency_table` of StreamingInference).
`producer_compat` is refused below 2.6.0, the oldest producer whose runs
StreamingInference opens.
"""
function telemetry_settings(config::AbstractDict)
    t = section(config, "telemetry")
    start = cfgget(t, "start_sim_time", "2035-01-01T00:00:00"; type = String)
    start_sim_time = tryparse(Dates.DateTime, start)
    start_sim_time === nothing && throw(
        ArgumentError(
            "configuration key `start_sim_time` = $(repr(start)); expected an ISO-8601 datetime.",
        ),
    )
    run_dir = cfgget(t, "run_dir", ""; type = String)
    events_csv = cfgget(t, "events_csv", ""; type = String)
    psd_sidecar = cfgget(t, "psd_sidecar", ""; type = String)
    producer_compat = cfgget(t, "producer_compat", "2.6"; type = String)
    compat_version = tryparse(VersionNumber, producer_compat)
    (compat_version !== nothing && compat_version >= v"2.6.0") || throw(
        ArgumentError(
            "configuration key `producer_compat` = $(repr(producer_compat)); expected a " *
            "version string at or above 2.6.0, the oldest producer whose runs " *
            "StreamingInference opens.",
        ),
    )
    alert_persistence = cfgget(t, "alert_persistence", 3; type = Int, min = 1)
    confirmation = cfgget(t, "alert_confirmation_persistence", 0; type = Int, min = 0)
    if confirmation != 0
        geometry = preprocessing_settings(config)
        overlap = geometry.window_size ÷ geometry.step_size
        confirmation > max(alert_persistence, overlap) || throw(
            ArgumentError(
                "configuration key `alert_confirmation_persistence` = $confirmation must be 0 " *
                "or exceed both `alert_persistence` = $alert_persistence and the window " *
                "overlap window_size ÷ step_size = $overlap.",
            ),
        )
    end
    return (
        segment_duration_sec = cfgget(
            t,
            "segment_duration_sec",
            50.0;
            type = Float64,
            min = 1e-6,
        ),
        batch_size = cfgget(t, "batch_size", 10; type = Int, min = 1),
        start_sim_time = start_sim_time,
        output_prefix = cfgget(t, "output_prefix", "telemetry"; type = String),
        run_dir = isempty(run_dir) ? "" : resolvepath(run_dir),
        mode = cfgget(t, "mode", "replay"; type = String, choices = ("replay", "live")),
        min_coverage = cfgget(
            t,
            "min_coverage",
            1.0;
            type = Float64,
            min = 1e-6,
            max = 1.0,
        ),
        tdi_gap_dilation_sec = cfgget(
            t,
            "tdi_gap_dilation_sec",
            100.0;
            type = Float64,
            min = 0.0,
        ),
        context_windows = cfgget(t, "context_windows", 4; type = Int, min = 0),
        psd_sidecar = isempty(psd_sidecar) ? "" : resolvepath(psd_sidecar),
        poll_interval_sec = cfgget(t, "poll_interval_sec", 1.0; type = Float64, min = 1e-3),
        producer_compat = producer_compat,
        processing_latency_hours = cfgget(
            t,
            "processing_latency_hours",
            1.0;
            type = Float64,
            min = 0.0,
        ),
        alert_persistence = alert_persistence,
        alert_confirmation_persistence = confirmation,
        alert_crediting = cfgget(
            t,
            "alert_crediting",
            "signal";
            type = String,
            choices = ("signal", "label"),
        ),
        psd_mode = cfgget(
            t,
            "psd_mode",
            "sidecar";
            type = String,
            choices = ("sidecar", "trailing"),
        ),
        psd_trailing_days = cfgget(
            t,
            "psd_trailing_days",
            30.0;
            type = Float64,
            min = 1e-6,
        ),
        psd_refresh_days = cfgget(t, "psd_refresh_days", 1.0; type = Float64, min = 1e-6),
        psd_segment_length = cfgget(t, "psd_segment_length", 65536; type = Int, min = 2),
        psd_edge_periods = cfgget(t, "psd_edge_periods", 3.0; type = Float64, min = 0.0),
        events_csv = isempty(events_csv) ? "" : resolvepath(events_csv),
    )
end
