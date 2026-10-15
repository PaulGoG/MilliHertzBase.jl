# Labelling stage: point-wise MBHB labels of an LDC
# product from its signal-only truth stream. The A channel of the truth
# stream is scanned with the windowed matched-filter SNR against the
# analytic TDI PSD or, under psd_model = "record", conditioned as the
# pre-processing conditions the observed record and scanned with the norm
# of the whitened signal per window; mergers come from the source catalogue when the product
# carries one and from SNR peaks otherwise; the positive span of every
# merger is either the fixed window of Isfan et al. (2025) or the union of
# windows in which the source is detectable; with fixed spans the event
# table also records the signal onset from which alerts are credited.

"""
    read_truth_csv(path) -> NamedTuple

Signal-only TDI `(t, X, Y, Z, dt)` from a CSV with columns `t`, `X`, `Y`,
`Z` (the blind-set truth of an LDC release); the sampling step is the
difference of the first two time samples.
"""
function read_truth_csv(path::AbstractString)
    isfile(path) || throw(ArgumentError("truth CSV not found: $path"))
    table = CSV.read(path, DataFrame)
    for c in (:t, :X, :Y, :Z)
        c in propertynames(table) || throw(ArgumentError("$path lacks the column $c."))
    end
    nrow(table) >= 2 || throw(ArgumentError("$path holds fewer than two samples."))
    dt = Float64(table.t[2] - table.t[1])
    dt > 0 || throw(ArgumentError("non-positive sampling step $dt in $path."))
    return (
        t = Float64.(table.t),
        X = Float64.(table.X),
        Y = Float64.(table.Y),
        Z = Float64.(table.Z),
        dt = dt,
    )
end

"""
    merger_indices_from_catalog(catalog, t0, fs, n) -> Vector{Int}

Sample indices of the coalescence times of `catalog` (column
`CoalescenceTime` [s]) in a record of `n` samples starting at `t0` [s] and
sampled at `fs` [Hz], clipped to `1:n`.
"""
function merger_indices_from_catalog(catalog::DataFrame, t0::Real, fs::Real, n::Integer)
    "CoalescenceTime" in names(catalog) ||
        throw(ArgumentError("the catalog lacks the column CoalescenceTime."))
    return [clamp(round(Int, (tc - t0) * fs) + 1, 1, n) for tc in catalog.CoalescenceTime]
end

"""
    merger_indices_from_peaks(A, starts, snr, settings, fs) -> Vector{Int}

Sample indices of the mergers of the truth-stream channel `A` located
without a catalogue: the SNR peaks ([`snr_peaks`](@ref)) of the windowed
scan (`starts`, `snr`) at or above `settings.merger_snr_threshold`,
separated by at least `settings.peak_min_separation_sec`, with inspiral
precursors within `settings.label_before_sec` below
`settings.precursor_ratio` of a larger peak discarded; the merger is the
sample of largest `|A|` inside each peak window.
"""
function merger_indices_from_peaks(
    A::AbstractVector{<:Real},
    starts::AbstractRange{<:Integer},
    snr::AbstractVector{<:Real},
    settings::NamedTuple,
    fs::Real,
)
    peaks = snr_peaks(
        starts,
        snr;
        threshold = settings.merger_snr_threshold,
        min_separation = round(Int, settings.peak_min_separation_sec * fs),
        precursor_window = round(Int, settings.label_before_sec * fs),
        precursor_ratio = settings.precursor_ratio,
    )
    window_size = settings.label_window_size
    return [
        starts[p] - 1 + argmax(abs.(view(A, starts[p]:(starts[p]+window_size-1)))) for
        p in peaks
    ]
end

"""
    span_peak_snr(spans, starts, snr; window_size, step) -> Vector{Float64}

Largest windowed SNR among the windows (of `window_size` samples at the
starts `starts`, stride `step`) overlapping each sample range of `spans`;
0 for a span no window overlaps.
"""
function span_peak_snr(
    spans::AbstractVector{<:AbstractUnitRange{<:Integer}},
    starts::AbstractRange{<:Integer},
    snr::AbstractVector{<:Real};
    window_size::Integer,
    step::Integer,
)
    peak = Vector{Float64}(undef, length(spans))
    for (k, span) in enumerate(spans)
        first_w = max(1, cld(first(span) - window_size, step) + 1)
        last_w = min(length(starts), div(last(span) - 1, step) + 1)
        peak[k] = first_w <= last_w ? maximum(view(snr, first_w:last_w)) : 0.0
    end
    return peak
end

"""
    analytic_truth_snr(A, E, fs, settings, mode) -> (starts, snr, snr_ae, description)

Windowed matched-filter SNR ([`windowed_snr`](@ref)) of the A channel of a
truth stream against the analytic TDI PSD ([`ldc_tdi_psd`](@ref)) of
`settings.psd_model` ([`ldc_settings`](@ref)) and, for a mode other than
`"A"`, the network SNR of A and E, ``\\rho_{AE}^2 = \\rho_A^2 + \\rho_E^2``
(orthogonal noise; Prince et al. 2002, doi:10.1103/PhysRevD.66.122002),
with E scanned against its own PSD; `snr_ae` is `nothing` for the mode
`"A"`. `description` names the PSD for the snapshot.
"""
function analytic_truth_snr(
    A::AbstractVector{<:Real},
    E::AbstractVector{<:Real},
    fs::Real,
    settings::NamedTuple,
    mode::AbstractString,
)
    window_size = settings.label_window_size
    step = settings.label_step
    psd_of(channel::Symbol) =
        f -> ldc_tdi_psd(
            f;
            channel = channel,
            model = settings.psd_model,
            tdi2 = settings.tdi2,
            observation_years = settings.observation_years,
        )
    starts, snr =
        windowed_snr(A, fs; window_size = window_size, step = step, psd = psd_of(:A))
    snr_ae = if mode == "A"
        nothing
    else
        _, snr_e = windowed_snr(E, fs; window_size = window_size, step = step, psd = psd_of(:E))
        sqrt.(snr .^ 2 .+ snr_e .^ 2)
    end
    description =
        "LDC analytic TDI PSD, model $(settings.psd_model), TDI " *
        "$(settings.tdi2 ? 2 : 1.5), confusion $(settings.observation_years) yr"
    return starts, snr, snr_ae, description
end

"""
    record_truth_snr(A, E, fs, config, record_path, mode) -> (starts, snr, snr_ae, description)

Window SNR of a truth stream conditioned as the pre-processing stage
conditions the observed record at `record_path` (the `[preprocessing]`
settings of `config`, [`preprocessing_settings`](@ref)): the orthogonal
channels of the record are high-passed stretch by stretch between its gaps
([`highpass_record`](@ref)) and give the whitening PSD of the configured
kind ([`stretch_whitening_psd`](@ref); for `"welch"` the median estimate
pooled over the stretches, smoothed as configured); the truth channel is
high-passed by the same filter, whitened by that PSD
([`whiten_record`](@ref)), and the SNR of every window is the norm of the
whitened signal ([`whitened_window_snr`](@ref)): the signal as the
detector sees it, against the noise it faces, the Galactic foreground
included. The network SNR of A and E for a mode other than `"A"` is formed
as in [`analytic_truth_snr`](@ref). The record must share the sampling
frequency `fs` of the truth stream; `[preprocessing] psd = "none"` is
refused.
"""
function record_truth_snr(
    A::AbstractVector{<:Real},
    E::AbstractVector{<:Real},
    fs::Real,
    config::AbstractDict,
    record_path::AbstractString,
    mode::AbstractString,
)
    settings = ldc_settings(config)
    pre = preprocessing_settings(config)
    pre.psd == "none" && throw(
        ArgumentError(
            "psd_model = \"record\" whitens the truth stream by the PSD of the " *
            "observed record; [preprocessing] psd = \"none\" provides none.",
        ),
    )
    tdi = read_tdi(record_path; group = pre.tdi_group)
    isapprox(1 / tdi.dt, fs; rtol = 1e-9) || throw(
        ArgumentError(
            "the record $record_path is sampled at $(1 / tdi.dt) Hz, " *
            "the truth stream at $fs Hz.",
        ),
    )
    stretches = finite_stretches(tdi.X, tdi.Y, tdi.Z)
    record = NamedTuple{(:A, :E, :T)}(tdi_to_aet(tdi.X, tdi.Y, tdi.Z))
    highpass(x::AbstractVector{<:Real}) =
        pre.highpass_cutoff_hz > 0 ?
        highpass_record(
            x,
            fs;
            cutoff = pre.highpass_cutoff_hz,
            order = pre.highpass_order,
        ) : Vector{Float64}(x)
    function whitened(channel::Symbol, truth::AbstractVector{<:Real})
        passed = [highpass(record[channel][r]) for r in stretches]
        psd, kind, _ = stretch_whitening_psd(pre, passed, fs; channel = channel)
        psd === nothing &&
            throw(ArgumentError("no whitening PSD for the $channel channel."))
        return whiten_record(highpass(truth), fs; psd = psd), String(kind)
    end
    window_size = settings.label_window_size
    step = settings.label_step
    w_a, description = whitened(:A, A)
    starts, snr = whitened_window_snr(w_a; window_size = window_size, step = step)
    snr_ae = if mode == "A"
        nothing
    else
        w_e, _ = whitened(:E, E)
        _, snr_e = whitened_window_snr(w_e; window_size = window_size, step = step)
        sqrt.(snr .^ 2 .+ snr_e .^ 2)
    end
    return starts,
    snr,
    snr_ae,
    description *
    " of the observed record; the truth stream high-passed and whitened as the record is"
end

"""
    label_truth_stream(config; h5_file = nothing, truth_csv = nothing,
                       record_file = nothing, output_prefix = nothing) -> NamedTuple

Labelling stage: the signal-only TDI of an LDC product — the compound
dataset `truth_group` of `h5_file` with the catalogue `catalog_group`
([`read_tdi`](@ref), [`read_catalog`](@ref)), or the columns `t, X, Y, Z`
of `truth_csv` ([`read_truth_csv`](@ref)) — is combined into the A channel
([`tdi_to_aet`](@ref)) and scanned with the windowed matched-filter SNR
([`windowed_snr`](@ref)) against the analytic TDI PSD
([`ldc_tdi_psd`](@ref)) of `psd_model` ([`analytic_truth_snr`](@ref)) —
or, for `psd_model = "record"`, conditioned as the pre-processing stage
conditions the observed record (`record_file`, else the configured
`[ldc] record_file`, else the file of the truth stream) and scanned with
the norm of the whitened signal per window ([`record_truth_snr`](@ref)):
the signal as the detector sees it, against the noise it faces, the
Galactic foreground included. Mergers are the catalogue's
coalescence times when a catalogue is available and SNR peaks otherwise
([`merger_indices_from_peaks`](@ref)); their positive spans are the fixed
window `[-label_before_sec, +label_after_sec]` ([`fixed_spans`](@ref)) or
the union of windows reaching `label_snr_threshold`
([`detectable_spans`](@ref)) according to `label_span`. Every parameter
comes from the `[ldc]`, `[paths]`, and `[resources]` sections of `config`
([`ldc_settings`](@ref)); `h5_file` and `truth_csv` are mutually exclusive
and replace the configured `h5_file`.

Under `[tdi] channels = "AE"` ([`tdi_settings`](@ref)) the event table also
carries the onset of a detector that reads A and E: the E channel is
scanned against its own PSD, the window SNRs are combined as
``\\rho_{AE}^2 = \\rho_A^2 + \\rho_E^2`` (orthogonal noise; Prince et al.
2002, doi:10.1103/PhysRevD.66.122002), and `signal_start_index_ae` and
`label_peak_snr_ae` are found from it as their A counterparts are. Under
`"AET"` the column `signal_start_index_aet` repeats the AE onset, since
the response of T to gravitational waves is strongly suppressed relative to
A and E below about 10 mHz, and the snapshot says so. The labels, the
mergers and the A columns do not depend on the mode.

Writes, under the `inputs` root, `<output_prefix>_labels.csv` (`Label`,
`SNR`: the peak windowed SNR of the event a sample belongs to),
`<output_prefix>_events.csv` (one row per merger with its sample index,
time, window SNR, catalogue parameters, and — for fixed spans — the label
range, its peak SNR, and the signal onset `signal_start_index`, the first
window inside the span and past the preceding event's span that reaches
`label_snr_threshold` ([`signal_onsets`](@ref)), from which alerts are
credited), `<output_prefix>_spans.csv`, and the snapshot
`<output_prefix>_labels.toml` with the labelling parameters and the
provenance sections of [`write_toml`](@ref). Existing files are backed up
first.

Returns `(label_path, events_path, spans_path, snapshot_path, events,
n_label_runs, positive_fraction)` with `events` the event table.
"""
function label_truth_stream(
    config::AbstractDict;
    h5_file::Union{Nothing,AbstractString} = nothing,
    truth_csv::Union{Nothing,AbstractString} = nothing,
    record_file::Union{Nothing,AbstractString} = nothing,
    output_prefix::Union{Nothing,AbstractString} = nothing,
)
    @timeit TIMER "labeling" begin
        settings = ldc_settings(config)
        resources = resource_settings(config)
        mode = tdi_settings(config).channels
        prefix = String(override(output_prefix, settings.output_prefix))
        (h5_file === nothing || truth_csv === nothing) ||
            throw(ArgumentError("h5_file and truth_csv are mutually exclusive."))
        if h5_file === nothing && truth_csv === nothing
            isempty(settings.h5_file) && throw(
                ArgumentError(
                    "no truth source: pass h5_file or truth_csv, or set [ldc] h5_file.",
                ),
            )
            h5_file = settings.h5_file
        end

        # Truth stream and catalogue
        local truth, catalog, source
        if h5_file !== nothing
            source = resolvepath(h5_file)
            truth = read_tdi(source; group = settings.truth_group)
            catalog = read_catalog(source; group = settings.catalog_group)
        elseif truth_csv !== nothing
            source = resolvepath(truth_csv)
            truth = read_truth_csv(source)
            catalog = nothing
        else
            throw(ArgumentError("no truth source: pass h5_file or truth_csv."))
        end
        n = length(truth.t)
        fs = 1 / truth.dt
        t0 = truth.t[1]
        check_memory(record_memory_estimate_gib(n), resources; stage = "labeling")
        A, E, _ = tdi_to_aet(truth.X, truth.Y, truth.Z)
        @info "truth stream" source n_samples = n sample_rate_hz = fs t0 max_abs_A =
            maximum(abs, A)

        # Window SNR of the truth: against the analytic TDI PSD, or as the
        # detector sees it, conditioned by the observed record's whitening
        window_size = settings.label_window_size
        step = settings.label_step
        psd_model = settings.psd_model
        tdi2 = settings.tdi2
        observation_years = settings.observation_years
        record_source = if psd_model != "record"
            ""
        elseif record_file !== nothing
            resolvepath(record_file)
        elseif !isempty(settings.record_file)
            settings.record_file
        elseif h5_file !== nothing
            source
        else
            throw(
                ArgumentError(
                    "psd_model = \"record\" needs the observed record: pass record_file " *
                    "or set [ldc] record_file; a truth CSV carries no record.",
                ),
            )
        end
        isempty(record_source) ||
            check_memory(3 * record_memory_estimate_gib(n), resources; stage = "labeling")
        @info "window SNR of the truth stream" window_size step psd_model tdi2 observation_years record_source
        starts, snr, snr_ae, psd_description =
            isempty(record_source) ? analytic_truth_snr(A, E, fs, settings, mode) :
            record_truth_snr(A, E, fs, config, record_source, mode)

        # Mergers: from the catalogue when available, else from SNR peaks
        merger_indices = if catalog !== nothing
            merger_indices_from_catalog(catalog, t0, fs, n)
        else
            merger_indices_from_peaks(A, starts, snr, settings, fs)
        end
        order = sortperm(merger_indices)
        merger_indices = merger_indices[order]
        catalog !== nothing && (catalog = catalog[order, :])
        isempty(merger_indices) && @warn "no merger found; the label column is all zeros."

        spans = if settings.label_span == "fixed"
            fixed_spans(
                merger_indices,
                fs,
                n;
                before = settings.label_before_sec,
                after = settings.label_after_sec,
            )
        else
            detectable_spans(starts, snr, window_size; threshold = settings.label_snr_threshold)
        end
        labels = span_labels(n, spans)
        peak_snr = span_peak_snr(spans, starts, snr; window_size = window_size, step = step)
        snr_column = zeros(Float32, n)
        for (span, ρ) in zip(spans, peak_snr)
            snr_column[span] .= max.(snr_column[span], Float32(ρ))
        end
        n_label_runs = length(contiguous_runs(labels .== 1))
        positive_fraction = count(==(1), labels) / n

        # Persist
        out_dir = pipeline_paths(config).inputs
        label_path = joinpath(out_dir, "$(prefix)_labels.csv")
        events_path = joinpath(out_dir, "$(prefix)_events.csv")
        spans_path = joinpath(out_dir, "$(prefix)_spans.csv")
        snapshot_path = joinpath(out_dir, "$(prefix)_labels.toml")
        for out in (label_path, events_path, spans_path, snapshot_path)
            abspath(out) == abspath(source) && throw(
                ArgumentError(
                    "output $out coincides with the input; choose another prefix.",
                ),
            )
        end
        write_csv(label_path, DataFrame(Label = labels, SNR = snr_column))

        events = DataFrame(
            event = 1:length(merger_indices),
            merger_index = merger_indices,
            merger_time_s = t0 .+ (merger_indices .- 1) ./ fs,
            merger_window_snr = [
                snr[clamp(div(i - 1, step) + 1, 1, length(snr))] for i in merger_indices
            ],
        )
        if catalog !== nothing
            for c in ("CoalescenceTime", "Mass1", "Mass2", "Redshift", "Distance")
                c in names(catalog) && (events[!, c] = catalog[!, c])
            end
        end
        if settings.label_span == "fixed"
            events.label_start_index = first.(spans)
            events.label_end_index = last.(spans)
            events.label_peak_snr = peak_snr
            # The onset search starts at the span start, or past the preceding
            # event's span when that ends later: the 96-h spans of mergers a
            # day apart overlap, and the earlier source must not supply the
            # onset of the later one.
            lower = [
                min(m, max(first(spans[i]), i == 1 ? 1 : last(spans[i-1]) + 1)) for
                (i, m) in enumerate(merger_indices)
            ]
            events.signal_start_index = signal_onsets(
                starts,
                snr,
                merger_indices,
                lower;
                threshold = settings.label_snr_threshold,
            )
            if snr_ae !== nothing
                events.label_peak_snr_ae = span_peak_snr(
                    spans,
                    starts,
                    snr_ae;
                    window_size = window_size,
                    step = step,
                )
                events.signal_start_index_ae = signal_onsets(
                    starts,
                    snr_ae,
                    merger_indices,
                    lower;
                    threshold = settings.label_snr_threshold,
                )
                # T carries no gravitational-wave signal of these sources below
                # about 10 mHz on equal arms, and its noise would have to be
                # measured: the onset of the three channels is that of A and E
                mode == "AET" &&
                    (events.signal_start_index_aet = copy(events.signal_start_index_ae))
            end
        end
        write_csv(events_path, events)
        write_csv(
            spans_path,
            DataFrame(
                span = 1:length(spans),
                start_index = first.(spans),
                end_index = last.(spans),
                peak_snr = peak_snr,
            ),
        )
        write_toml(
            snapshot_path,
            Dict{String,Any}(
                "product" => product_table(
                    "labels";
                    channels = mode,
                    parents = Dict{String,Any}(
                        "source" => content_digest(source),
                        (
                            isempty(record_source) ? () :
                            ("record" => content_digest(record_source),)
                        )...,
                    ),
                ),
                "labels" => Dict{String,Any}(
                    "source" => provenance_path(source),
                    "truth_group" => settings.truth_group,
                    "psd_model" => psd_model,
                    "psd_description" => psd_description,
                    "record_source" =>
                        isempty(record_source) ? "" : provenance_path(record_source),
                    "tdi2" => tdi2,
                    "observation_years" => observation_years,
                    "label_span" => settings.label_span,
                    "label_before_sec" => settings.label_before_sec,
                    "label_after_sec" => settings.label_after_sec,
                    "label_snr_threshold" => settings.label_snr_threshold,
                    "signal_onset" =>
                        settings.label_span == "fixed" ?
                        "first window reaching label_snr_threshold inside the span and past the preceding span" :
                        "",
                    (
                        mode != "A" && settings.label_span == "fixed" ?
                        (
                            "signal_onset_ae" => "as signal_onset, on the network SNR of A and E, the root of the sum of their squared window SNRs",
                        ) : ()
                    )...,
                    (
                        mode == "AET" && settings.label_span == "fixed" ?
                        (
                            "signal_onset_aet" => "set to the AE onset: T is signal-free below about 10 mHz on equal arms and its noise is not measured here",
                        ) : ()
                    )...,
                    "merger_snr_threshold" => settings.merger_snr_threshold,
                    "precursor_ratio" => settings.precursor_ratio,
                    "peak_min_separation_sec" => settings.peak_min_separation_sec,
                    "label_window_size" => window_size,
                    "label_step" => step,
                    "n_samples" => n,
                    "n_events" => length(merger_indices),
                    "n_label_runs" => n_label_runs,
                    "positive_fraction" => positive_fraction,
                ),
            );
            tag = true,
        )
        @info "labels written" label_path n_events = length(merger_indices) n_label_runs positive_fraction =
            round(positive_fraction; digits = 4)

        (
            label_path = label_path,
            events_path = events_path,
            spans_path = spans_path,
            snapshot_path = snapshot_path,
            events = events,
            n_label_runs = n_label_runs,
            positive_fraction = positive_fraction,
        )
    end
end
