# Whitening PSD of a TDI record by its kind: the Robson–Cornish–Liu model,
# that model times the sky-averaged response, the analytic LDC TDI PSD, a
# Welch estimate, or none; and the PSD recorded in a feature sidecar.

"""
    analytic_psd(kind, parameters; channel = :A) -> callable

The analytic whitening PSD of the kind `kind` with the parameters of the
NamedTuple `parameters` (the `[preprocessing]` settings, or the values a
feature sidecar records): the Robson–Cornish–Liu sensitivity with the
confusion fit of `observation_years` (`"model"`), that sensitivity times
the sky-averaged response ([`michelson_channel_psd`](@ref), `"channel"`),
or the analytic TDI PSD of `channel` in the `ldc` package with
`ldc_model`, `ldc_tdi2` and `ldc_observation_years` (`"ldc"`,
[`ldc_tdi_psd`](@ref)). The pre-processor and the sidecar reader build
their PSD here.
"""
function analytic_psd(kind::AbstractString, parameters::NamedTuple; channel::Symbol = :A)
    if kind == "model" || kind == "channel"
        years = parameters.observation_years
        sensitivity = f -> lisa_noise_psd(f; observation_years = years)
        return kind == "model" ? sensitivity : michelson_channel_psd(sensitivity)
    elseif kind == "ldc"
        model = parameters.ldc_model
        tdi2 = parameters.ldc_tdi2
        years = parameters.ldc_observation_years
        return f -> ldc_tdi_psd(
            f;
            channel = channel,
            model = model,
            tdi2 = tdi2,
            observation_years = years,
        )
    end
    throw(
        ArgumentError(
            "psd = $(repr(kind)) is not an analytic PSD; expected model, channel or ldc.",
        ),
    )
end

"""
    analytic_psd_description(kind, parameters; channel = :A) -> String

The account of the analytic PSD of [`analytic_psd`](@ref) that the sidecar
of a product records.
"""
function analytic_psd_description(
    kind::AbstractString,
    parameters::NamedTuple;
    channel::Symbol = :A,
)
    kind == "model" && return "Robson–Cornish–Liu 2019 strain sensitivity, confusion fit " *
           "$(parameters.observation_years) yr"
    kind == "channel" &&
        return "Robson–Cornish–Liu 2019 Michelson-channel PSD (sensitivity times the " *
               "sky-averaged response), confusion fit $(parameters.observation_years) yr"
    return "LDC analytic $channel-channel PSD, model $(parameters.ldc_model), TDI " *
           "$(parameters.ldc_tdi2 ? 2 : 1.5), confusion $(parameters.ldc_observation_years) yr"
end

"""
    whitening_psd_from_sidecar(sidecar_path) -> Union{Nothing, Function, Vector}

The whitening PSD recorded in a feature sidecar written by the
pre-processor; for a product of several channels, a vector with the PSD of
each in the order of [`channel_names`](@ref). Each is the Robson–Cornish–Liu
model (`"model"`), that model times the sky-averaged response
(`"channel"`), the LDC analytic model (`"ldc"`), the persisted Welch table
(`<stem>_psd.csv` beside the features), or `nothing` for `psd = "none"`.
The channel mode, the kind and the parameters of an analytic PSD
(`observation_years`; `ldc_model`, `ldc_tdi2`, `ldc_observation_years`)
must be recorded in the sidecar; a missing one is refused, since a default
may differ from the PSD the features were whitened with.
"""
function whitening_psd_from_sidecar(sidecar_path::AbstractString)
    isfile(sidecar_path) || throw(ArgumentError("feature sidecar not found: $sidecar_path"))
    features = get(TOML.parsefile(sidecar_path), "features", Dict{String,Any}())
    function recorded(key, type)
        haskey(features, key) || throw(
            ArgumentError(
                "the sidecar $sidecar_path does not record `$key`, which the whitening " *
                "PSD of its features depends on; regenerate the product.",
            ),
        )
        return cfgget(features, key, nothing; type = type)
    end
    kind = recorded("psd", String)
    channels = channel_names(recorded("channels", String))
    psds = [
        sidecar_channel_psd(sidecar_path, kind, recorded, c, length(channels)) for
        c in channels
    ]
    # `psd = "none"` means no whitening, for one channel or several
    return length(channels) == 1 ? only(psds) : all(isnothing, psds) ? nothing : psds
end

# The whitening PSD of one channel of a product whitened by the PSD `kind`,
# with `recorded(key, type)` the value the sidecar records under `key`
function sidecar_channel_psd(sidecar_path, kind, recorded, channel::Symbol, n_channels)
    if kind == "model" || kind == "channel"
        return analytic_psd(
            kind,
            (observation_years = recorded("observation_years", Float64),),
        )
    elseif kind == "ldc"
        parameters = (
            ldc_model = recorded("ldc_model", String),
            ldc_tdi2 = recorded("ldc_tdi2", Bool),
            ldc_observation_years = recorded("ldc_observation_years", Float64),
        )
        return analytic_psd(kind, parameters; channel = channel)
    elseif kind == "welch"
        stem = replace(sidecar_path, r"_features\.toml$" => "")
        table_path = stem * "_psd.csv"
        isfile(table_path) || throw(
            ArgumentError("Welch PSD table not found beside the sidecar: $table_path"),
        )
        table = CSV.read(table_path, DataFrame)
        # One column `psd` for a single channel, `psd_<channel>` for several
        column = n_channels == 1 ? "psd" : "psd_$channel"
        column in names(table) ||
            throw(ArgumentError("the PSD table $table_path lacks the column $column."))
        return interpolated_psd(
            Vector{Float64}(table.frequency_hz),
            Vector{Float64}(table[!, column]),
        )
    elseif kind == "none"
        return nothing
    end
    throw(
        ArgumentError(
            "sidecar psd = $(repr(kind)); expected model, channel, ldc, welch, or none.",
        ),
    )
end

"""
    whitening_psd(settings, A, fs; channel = :A) -> (psd, description, table)

Callable one-sided PSD whitening the record `A` of the TDI channel
`channel` (`:A`, `:E` or `:T`) sampled at `fs` [Hz] for the mode
`settings.psd` of the `[preprocessing]` section
([`preprocessing_settings`](@ref)): `"model"` (Robson–Cornish–Liu strain
sensitivity with the confusion fit of `observation_years`, for
sky-averaged simulator products), `"channel"` (that sensitivity times the
sky-averaged response ``R(f)``, the Michelson-channel PSD of the
simulator's constellation-response products), `"ldc"` (analytic TDI PSD of
the channel in the `ldc` package, in fractional-frequency units, with
`ldc_model`, `ldc_tdi2` and `ldc_observation_years`, for LDC products),
`"welch"` (median-averaged estimate from the record itself over segments
of `welch_segment_length` samples, smoothed in log-frequency by
`psd_smoothing_dex` dex when that is positive; [`smooth_psd`](@ref)), or
`"none"` (no whitening; `psd` is `nothing`). `description` is the
human-readable account persisted in the sidecar; `table` is the estimated
PSD as a `DataFrame` (`frequency_hz`, `psd`) for `"welch"` and `nothing`
otherwise. The T channel takes a measured PSD or none: the analytic kinds
are refused for it. This is [`stretch_whitening_psd`](@ref) of the record
as its one stretch.
"""
function whitening_psd(
    settings::NamedTuple,
    A::AbstractVector{<:Real},
    fs::Real;
    channel::Symbol = :A,
)
    return stretch_whitening_psd(settings, [A], fs; channel = channel, pooled = false)
end

"""
    stretch_whitening_psd(settings, stretches, fs; channel = :A, pooled = true)
        -> (psd, description, table)

Whitening PSD of a record with gaps, given the stretches between its gaps
(each high-passed already) of the TDI channel `channel` sampled at `fs`
[Hz], with the return values of [`whitening_psd`](@ref). For `"welch"` it
is the median-averaged estimate pooled over the stretches, over segments of
`welch_segment_length` samples none of which spans a gap, smoothed in
log-frequency by `psd_smoothing_dex` dex when that is positive; `table`
holds that estimate (`frequency_hz`, `psd`), and `description` names the
number of stretches when `pooled`, else the record. The analytic kinds
([`analytic_psd`](@ref)) and `"none"` do not read the record; an analytic
PSD is refused for T.
"""
function stretch_whitening_psd(
    settings::NamedTuple,
    stretches::AbstractVector{<:AbstractVector{<:Real}},
    fs::Real;
    channel::Symbol = :A,
    pooled::Bool = true,
)
    kind = settings.psd
    channel in (:A, :E, :T) ||
        throw(ArgumentError("channel = :$channel; expected :A, :E or :T."))
    # The T noise of the LDC records departs from the analytic equal-arm PSD
    # below 3 mHz (0.14–0.54 times it on Sangria, about 940 times it at low
    # frequency on the unequal arms of Spritz), so T is whitened by a
    # measured PSD only
    channel == :T &&
        kind in ("model", "channel", "ldc") &&
        throw(
            ArgumentError(
                "psd = $(repr(kind)) is an analytic PSD; the T channel takes a measured " *
                "one (psd = \"welch\") or none.",
            ),
        )
    isempty(stretches) && throw(ArgumentError("no stretch given."))
    if kind == "welch"
        segment = settings.welch_segment_length
        freqs, table = welch_psd(stretches, fs; segment_length = segment, average = :median)
        smoothing = settings.psd_smoothing_dex
        description =
            pooled ?
            "median Welch estimate pooled over $(length(stretches)) stretches " *
            "between gaps, segment $segment samples" :
            "median Welch estimate of the record, segment $segment samples"
        if smoothing > 0
            table = smooth_psd(freqs, table, smoothing)
            description *= ", smoothed by $smoothing dex in log-frequency"
        end
        return interpolated_psd(freqs, table),
        description,
        DataFrame(frequency_hz = freqs, psd = table)
    elseif kind in ("model", "channel", "ldc")
        return analytic_psd(kind, settings; channel = channel),
        analytic_psd_description(kind, settings; channel = channel),
        nothing
    elseif kind == "none"
        return nothing, "none", nothing
    end
    throw(
        ArgumentError("psd = $(repr(kind)); expected model, channel, ldc, welch, or none."),
    )
end
