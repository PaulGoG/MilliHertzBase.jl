# Static QA, LISA noise and IMRPhenomA waveforms, LDC products, settings and figures,
# and the generation, pre-processing, labelling, export and telemetry-replay stages.
include(joinpath(@__DIR__, "activate.jl"))

using Test
using Statistics, TOML, Dates
using FFTW: rfft, rfftfreq
using CSV, DataFrames
using HDF5: HDF5
using StableRNGs
using Aqua, JET, ExplicitImports
using StreamingInference
using MilliHertzBase
using CairoMakie: CairoMakie
using DeepSpaceTelemetry: DeepSpaceTelemetry
using CurvatureDistinguishability: CurvatureDistinguishability

const PROJECT_ROOT = dirname(@__DIR__)
# The pipeline root of the whole run: a sandboxed test environment lies
# outside the repository
ENV["STREAMINGINFERENCE_ROOT"] = PROJECT_ROOT

@testset "Static QA (Aqua)" begin
    # The persistent-tasks check precompiles a wrapper package against the
    # live registry; it is gated off CI, where it fails for environmental
    # reasons, and runs locally.
    Aqua.test_all(MilliHertzBase; persistent_tasks = get(ENV, "CI", "") != "true")
end

@testset "Static QA (ExplicitImports)" begin
    @test ExplicitImports.check_no_stale_explicit_imports(MilliHertzBase) === nothing
    @test ExplicitImports.check_no_implicit_imports(MilliHertzBase) === nothing
    # The figure extension reaches `latexstring` of LaTeXStrings through
    # Makie, the only route open to an extension of this package
    @test ExplicitImports.check_all_explicit_imports_via_owners(
        MilliHertzBase;
        ignore = (:latexstring,),
    ) === nothing
    @test ExplicitImports.check_all_explicit_imports_are_public(
        MilliHertzBase;
        ignore = (:latexstring,),
    ) === nothing
    @test ExplicitImports.check_all_qualified_accesses_via_owners(MilliHertzBase) ===
          nothing
    # `CSV.read`, the HDF5 object types and the readers of the producer's
    # file contract are the documented interfaces of those packages, which
    # declare no public names beyond their exports
    @test ExplicitImports.check_all_qualified_accesses_are_public(
        MilliHertzBase;
        ignore = (
            :read,
            :File,
            :Group,
            :Dataset,
            :filename,
            :load_run_config,
            :load_segment,
            :read_batch_metadata,
        ),
    ) === nothing
    @test ExplicitImports.check_no_self_qualified_accesses(MilliHertzBase) === nothing
end

@testset "Static QA (JET)" begin
    JET.test_package(MilliHertzBase; target_modules = (MilliHertzBase,))
end

@testset "Noise model (Robson, Cornish & Liu 2019)" begin
    # Structural properties of the sensitivity curve
    @test instrument_psd(0.0) == Inf
    @test confusion_psd(-1.0) == Inf
    @test lisa_noise_psd(1e-3) > 0
    # The confusion foreground dominates the instrument term near 1 mHz for the
    # one-year fit and is negligible above 10 mHz
    @test confusion_psd(1e-3; observation_years = 1.0) > instrument_psd(1e-3)
    @test confusion_psd(1e-2; observation_years = 1.0) < 1e-3 * instrument_psd(1e-2)
    # More resolved and subtracted binaries with longer observation
    @test confusion_psd(1e-3; observation_years = 4.0) <
          confusion_psd(1e-3; observation_years = 0.5)
    # The sensitivity has its minimum in the milliHertz band
    @test lisa_noise_psd(1e-2) < lisa_noise_psd(3e-4)
    @test lisa_noise_psd(1e-2) < lisa_noise_psd(1e-1)
    # Reference values evaluated independently from the published formulas
    @test isapprox(instrument_psd(1e-3), 1.634101e-38; rtol = 1e-5)
    @test isapprox(confusion_psd(1e-3; observation_years = 1.0), 1.663516e-37; rtol = 1e-5)
    @test isapprox(instrument_psd(1e-2), 1.443169e-40; rtol = 1e-5)
    @test isapprox(confusion_psd(3e-3; observation_years = 1.0), 5.591648e-40; rtol = 1e-5)
    @test_throws ArgumentError confusion_psd(1e-3; observation_years = 3.0)
    # Far above the knee the direct product would be 0 × Inf; the log-space
    # evaluation vanishes and the sensitivity stays finite up to 10 Hz
    @test confusion_psd(10.0; observation_years = 1.0) == 0.0
    @test all(isfinite, lisa_noise_psd.((0.05, 0.5, 2.0, 10.0)))
    # Agreement with the direct product where both are finite
    p = MilliHertzBase.confusion_fit(1.0)
    f = 2e-3
    direct =
        MilliHertzBase.CONFUSION_AMPLITUDE *
        f^(-7 / 3) *
        exp(-f^p.α + p.β * f * sin(p.κ * f)) *
        (1 + tanh(p.γ * (p.f_k - f)))
    @test isapprox(confusion_psd(f), direct; rtol = 1e-10)
end

@testset "IMRPhenomA waveform" begin
    fs = 0.2
    p6 = phenoma_parameters(1e6, 1.0)
    @test p6.η ≈ 0.25
    @test p6.f_merg < p6.f_ring < p6.f_cut
    # Transition frequencies scale inversely with the total mass
    @test phenoma_parameters(2e6, 1.0).f_merg ≈ p6.f_merg / 2
    @test isapprox(p6.f_merg, 8.10e-3; rtol = 1e-2)   # 0.1254 / (π M) for η = 1/4
    # Amplitude continuity at the transitions and zero beyond the cutoff
    @test isapprox(phenoma_amplitude(p6.f_merg, p6), 1.0; atol = 1e-12)
    ε = 1e-9
    @test isapprox(
        phenoma_amplitude(p6.f_ring - ε, p6),
        phenoma_amplitude(p6.f_ring + ε, p6);
        rtol = 1e-6,
    )
    @test phenoma_amplitude(p6.f_cut, p6) == 0
    @test phenoma_amplitude(0.0, p6) == 0

    h, k_m, p = phenoma_waveform(fs, 2 * 86400; total_mass = 1e6, mass_ratio = 1.0)
    n = length(h)
    @test n == 34560
    @test maximum(abs, h) == 1
    # The amplitude peak lands at the target merger time
    T = n / fs
    t_pad = clamp(max(0.05 * T, 20 / (π * p.sigma)), 0.0, 0.5 * T)
    # (the amplitude peak precedes the arrival of the ringdown frequency by
    # some ten total masses; a merger above the Nyquist taper adds a few samples)
    @test abs(k_m - (round(Int, (T - t_pad) * fs) + 1)) / fs <= 20 * p.M_sec + 10 / fs
    # Forward chirp: the zero-crossing frequency rises towards the merger
    function zc_frequency(seg)
        return count(j -> sign(seg[j]) != sign(seg[j-1]), 2:length(seg)) / 2 /
               (length(seg) / fs)
    end
    f_early = zc_frequency(view(h, div(k_m, 4):div(k_m, 2)))
    f_late = zc_frequency(view(h, (k_m-400):k_m))
    @test f_late > 3 * f_early
    # Inspiral spectral slope −7/6 on the realised spectrum
    Hs = abs.(rfft(h))
    fr = rfftfreq(n, fs)
    f_lo = 2 * phenoma_start_frequency(p, (k_m - 1) / fs)
    f_hi = p.f_merg / 2
    band = (fr .>= f_lo) .& (fr .<= f_hi)
    X = log.(fr[band])
    Y = log.(Hs[band])
    @test isapprox(cov(X, Y) / var(X), -7 / 6; atol = 0.15)
    # No power above the Nyquist taper
    @test maximum(Hs[fr .> 0.9*fs/2]) < 1e-3 * maximum(Hs)
    # The segment starts quietly (roll-on and ramp)
    @test maximum(abs, view(h, 1:100)) < 0.05
    # Heavy and light binaries generate and place their peak correctly
    for (M, q) in ((1e7, 4.0), (1e5, 1.0))
        hh, kk, pp = phenoma_waveform(fs, 2 * 86400; total_mass = M, mass_ratio = q)
        Tn = length(hh) / fs
        tp = clamp(max(0.05 * Tn, 20 / (π * pp.sigma)), 0.0, 0.5 * Tn)
        @test abs(kk - (round(Int, (Tn - tp) * fs) + 1)) / fs <= 20 * pp.M_sec + 10 / fs
    end
    @test_throws ArgumentError phenoma_parameters(0.0, 1.0)
    @test_throws ArgumentError phenoma_parameters(1e6, 0.5)
    @test_throws ArgumentError phenoma_waveform(
        fs,
        1000.0;
        total_mass = 1e6,
        mass_ratio = 1.0,
        nyquist_taper = 1.5,
    )
end

@testset "Detectable span" begin
    fs = 0.2
    n = 20000
    t = (0:(n-1)) ./ fs
    placed = zeros(n)
    covered = 8001:9000
    placed[covered] .= cos.(2π * 3e-3 .* t[covered])
    # Scale so that a window holding the whole burst has SNR 20
    ρ_full = matched_filter_snr(view(placed, 8001:9000), fs; psd = lisa_noise_psd)
    placed .*= 20 / ρ_full
    span = detectable_span(placed, covered, fs, 1000, 5.0; step = 10)
    @test span !== nothing
    @test first(span) < first(covered) && last(span) > last(covered)
    @test first(span) >= first(covered) - 999 && last(span) <= last(covered) + 999
    # A higher threshold narrows the span, an unreachable one empties it
    narrow = detectable_span(placed, covered, fs, 1000, 15.0; step = 10)
    @test narrow !== nothing && length(narrow) < length(span)
    @test detectable_span(placed, covered, fs, 1000, 1e6; step = 10) === nothing
    @test detectable_span(placed, 5:4, fs, 1000, 5.0) === nothing
    @test_throws ArgumentError detectable_span(placed, covered, fs, 1, 5.0)
    @test_throws ArgumentError detectable_span(placed, covered, fs, 1000, 0.0)
end

@testset "LDC noise model and readers" begin
    # Doctest of the ldc package: SciRDv1 X-channel PSD at five frequencies
    f5 = 10.0 .^ range(-5, 0; length = 5)
    x_ref = [7.13597299e-40, 2.76990908e-42, 9.52379492e-43, 1.92645601e-40, 1.15359813e-36]
    @test all(
        isapprox(ldc_tdi_psd(f; channel = :X, model = "SciRDv1"), r; rtol = 1e-8) for
        (f, r) in zip(f5, x_ref)
    )
    # A = E for equal arms; T is quieter than X in band; TDI 2 rescales by 4 sin²(2x)
    @test ldc_tdi_psd(2e-3; channel = :A) == ldc_tdi_psd(2e-3; channel = :E)
    @test ldc_tdi_psd(2e-3; channel = :T) < ldc_tdi_psd(2e-3; channel = :X)
    x = 2π * 2e-3 * MilliHertzBase.L_ARM / MilliHertzBase.C_LIGHT
    @test isapprox(
        ldc_tdi_psd(2e-3; channel = :A, tdi2 = true),
        4 * sin(2x)^2 * ldc_tdi_psd(2e-3; channel = :A);
        rtol = 1e-12,
    )
    @test ldc_tdi_psd(0.0) == Inf
    @test ldc_tdi_psd(1e-3; observation_years = 1.0) > ldc_tdi_psd(1e-3)
    @test ldc_confusion_psd(1e-3; channel = :A) ==
          1.5 * ldc_confusion_psd(1e-3; channel = :X)
    @test ldc_confusion_psd(1e-3; observation_years = 4.0) <
          ldc_confusion_psd(1e-3; observation_years = 0.5)
    @test_throws ArgumentError ldc_tdi_psd(1e-3; model = "unknown")
    @test_throws ArgumentError ldc_tdi_psd(1e-3; channel = :B)
    @test_throws ArgumentError ldc_confusion_psd(1e-3; observation_years = 20.0)

    # A/E/T is an orthonormal combination
    rng = StableRNG(5)
    X, Y, Z = randn(rng, 100), randn(rng, 100), randn(rng, 100)
    A, E, T = tdi_to_aet(X, Y, Z)
    @test isapprox(
        sum(A .^ 2 .+ E .^ 2 .+ T .^ 2),
        sum(X .^ 2 .+ Y .^ 2 .+ Z .^ 2);
        rtol = 1e-12,
    )
    @test A == (Z .- X) ./ sqrt(2)
    @test_throws DimensionMismatch tdi_to_aet(X, Y, Z[1:99])

    # Compound and group HDF5 layouts read identically; catalogues become tables
    mktempdir() do dir
        n = 64
        t = collect(0.0:5.0:(5.0*(n-1)))
        rows = [(t = t[i], X = 1.0 * i, Y = 2.0 * i, Z = 3.0 * i) for i in 1:n]
        cat = [(Mass1 = 1e6, Mass2 = 5e5, CoalescenceTime = 100.0)]
        compound = joinpath(dir, "ldc.h5")
        HDF5.h5open(compound, "w") do f
            f["obs/tdi"] = rows
            HDF5.attributes(f["obs/tdi"])["dt"] = 5.0
            f["sky/mbhb/cat"] = cat
        end
        grouped = joinpath(dir, "sim.h5")
        HDF5.h5open(grouped, "w") do f
            f["obs/tdi/t"] = t
            f["obs/tdi/X"] = [1.0 * i for i in 1:n]
            f["obs/tdi/Z"] = [3.0 * i for i in 1:n]
        end
        a = read_tdi(compound)
        b = read_tdi(grouped)
        @test a.t == b.t == t && a.X == b.X && a.Z == b.Z && a.dt == b.dt == 5.0
        @test a.Y == 2.0 .* (1:n) && b.Y == zeros(n)
        table = read_catalog(compound)
        @test nrow(table) == 1 && table.CoalescenceTime[1] == 100.0
        @test_throws ArgumentError read_tdi(compound; group = "missing")
        @test_throws ArgumentError read_tdi(joinpath(dir, "absent.h5"))
    end

    # Windowed SNR of a placed sinusoid burst peaks on the burst, and the
    # labelling helpers locate it
    fs = 0.2
    n = 20_000
    sig = zeros(n)
    burst = 8001:9000
    sig[burst] .= 1e-20 .* sin.(2π * 5e-3 .* (0:999) ./ fs)
    starts, ρ = windowed_snr(sig, fs; window_size = 1000, step = 100, psd = lisa_noise_psd)
    @test length(starts) == length(ρ) == div(n - 1000, 100) + 1
    @test starts[argmax(ρ)] == 8001
    @test ρ[argmax(ρ)] > 5 && all(ρ[starts .> 9000] .== 0)
    peaks = snr_peaks(starts, ρ; threshold = 5.0, min_separation = 5000)
    @test peaks == [argmax(ρ)]
    # A small local maximum shortly before a large one is an inspiral
    # fluctuation, not a merger; two comparable peaks stay distinct
    series = zeros(50)
    series[10] = 6.0
    series[20] = 600.0
    series[30] = 500.0
    grid = 1:100:5000
    @test snr_peaks(grid, series; threshold = 5.0, min_separation = 500) == [10, 20, 30]
    @test snr_peaks(
        grid,
        series;
        threshold = 5.0,
        min_separation = 500,
        precursor_window = 1500,
    ) == [20, 30]
    @test_throws ArgumentError snr_peaks(
        grid,
        series;
        threshold = 5.0,
        min_separation = 0,
        precursor_ratio = 2.0,
    )
    spans = detectable_spans(starts, ρ, 1000; threshold = 5.0)
    @test length(spans) == 1 && first(spans[1]) <= 8001 && last(spans[1]) >= 9000
    # Signal onsets: the first window from the lower bound that reaches the
    # threshold, the merger sample when none does before it
    @test signal_onsets(starts, ρ, [9000], [1]; threshold = 5.0) == [first(spans[1])]
    @test signal_onsets(starts, ρ, [9000], [first(spans[1]) + 1]; threshold = 5.0)[1] >
          first(spans[1])
    @test signal_onsets(starts, ρ, [2000], [1]; threshold = 5.0) == [2000]
    @test_throws ArgumentError signal_onsets(starts, ρ, [100], [200]; threshold = 5.0)
    @test_throws ArgumentError signal_onsets(starts, ρ, [100], [1]; threshold = 0.0)
    @test_throws DimensionMismatch signal_onsets(
        starts,
        ρ,
        [100, 200],
        [1];
        threshold = 5.0,
    )
    # The generator's onset of one injection: a window reaching the threshold
    # between the label start and the coalescence, its predecessor below it
    onset_settings = (
        label_span = "fixed",
        label_window_size = 1000,
        label_step = 100,
        label_snr_threshold = 5.0,
    )
    k_on = MilliHertzBase.signal_onset(
        onset_settings,
        (sig,),
        burst,
        8900,
        7001,
        9100,
        fs,
        lisa_noise_psd,
    )
    @test 7001 <= k_on <= 8900
    @test matched_filter_snr(view(sig, k_on:(k_on+999)), fs; psd = lisa_noise_psd) >= 5
    @test matched_filter_snr(view(sig, (k_on-100):(k_on+899)), fs; psd = lisa_noise_psd) < 5
    @test MilliHertzBase.signal_onset(
        onset_settings,
        (zeros(n),),
        burst,
        8900,
        7001,
        9100,
        fs,
        lisa_noise_psd,
    ) == 8900
    @test MilliHertzBase.signal_onset(
        merge(onset_settings, (label_span = "detectable",)),
        (sig,),
        burst,
        8900,
        7500,
        9100,
        fs,
        lisa_noise_psd,
    ) == 7500
    @test_throws ArgumentError windowed_snr(
        sig,
        fs;
        window_size = 1,
        step = 1,
        psd = lisa_noise_psd,
    )
    @test isempty(snr_peaks(starts, ρ; threshold = 1e9, min_separation = 0))
end

@testset "Whitening PSD of a feature sidecar" begin
    # Every analytic kind is rebuilt from its recorded parameters, and a
    # sidecar that lacks them is refused rather than defaulted
    mktempdir() do dir
        function sidecar(name; entries...)
            path = joinpath(dir, "$(name)_features.toml")
            open(
                io -> TOML.print(
                    io,
                    Dict("features" => Dict(string(k) => v for (k, v) in entries)),
                ),
                path,
                "w",
            )
            return path
        end
        model = sidecar(
            "model";
            window_size = 1000,
            step_size = 100,
            sample_rate = 0.2,
            psd = "model",
            observation_years = 1.0,
            highpass_cutoff_hz = 5e-4,
            highpass_order = 8,
            low_band_hz = [1e-3, 5e-3],
            high_band_hz = [5e-3, 1e-1],
            feature_set = "whitened",
        )
        @test whitening_psd_from_sidecar(model)(1e-3) == lisa_noise_psd(1e-3)
        channel = sidecar("channel"; psd = "channel", observation_years = 2.0)
        @test whitening_psd_from_sidecar(channel)(3e-3) ==
              sky_averaged_response(3e-3) * lisa_noise_psd(3e-3; observation_years = 2.0)
        ldc = sidecar(
            "ldc";
            psd = "ldc",
            ldc_model = "SciRDv1",
            ldc_tdi2 = false,
            ldc_observation_years = 0.0,
        )
        @test whitening_psd_from_sidecar(ldc)(3e-3) ==
              ldc_tdi_psd(3e-3; channel = :A, model = "SciRDv1")
        @test whitening_psd_from_sidecar(sidecar("none"; psd = "none")) === nothing
        @test_throws ArgumentError whitening_psd_from_sidecar(sidecar("m"; psd = "model"))
        @test_throws ArgumentError whitening_psd_from_sidecar(
            sidecar("l"; psd = "ldc", ldc_model = "SciRDv1"),
        )
        @test_throws ArgumentError whitening_psd_from_sidecar(
            sidecar("n"; window_size = 1000),
        )
        @test_throws ArgumentError whitening_psd_from_sidecar(joinpath(dir, "absent.toml"))
    end
end

@testset "Configuration (gravitational-wave sections)" begin
    # An empty configuration yields the documented, validated defaults
    empty = Dict{String,Any}()
    @test generation_settings(empty).snr_max == 50.0
    @test_throws ArgumentError generation_settings(
        Dict{String,Any}("generation" => Dict{String,Any}("observation_years" => 3.0)),
    )
    @test preprocessing_settings(empty).psd == "model"
    @test preprocessing_settings(empty).feature_set == :whitened
    @test preprocessing_settings(empty).band_edges_hz == [1e-3, 5e-3, 1e-1]
    @test preprocessing_settings(empty).edge_margin == 0.0
    @test_throws ArgumentError preprocessing_settings(
        Dict{String,Any}("preprocessing" => Dict{String,Any}("edge_margin" => -1.0)),
    )
    @test preprocessing_settings(empty).psd_smoothing_dex == 0.0
    @test_throws ArgumentError preprocessing_settings(
        Dict{String,Any}("preprocessing" => Dict{String,Any}("psd_smoothing_dex" => -0.01)),
    )
    @test preprocessing_settings(
        Dict{String,Any}(
            "preprocessing" => Dict{String,Any}(
                "feature_set" => "bands",
                "band_edges_hz" => [5e-4, 2e-3, 8e-3],
            ),
        ),
    ).band_edges_hz == [5e-4, 2e-3, 8e-3]
    @test_throws ArgumentError preprocessing_settings(
        Dict{String,Any}(
            "preprocessing" => Dict{String,Any}("band_edges_hz" => [5e-3, 1e-3]),
        ),
    )
    @test_throws ArgumentError preprocessing_settings(
        Dict{String,Any}("preprocessing" => Dict{String,Any}("step_size" => 2000)),
    )
    @test ldc_settings(empty).label_before_sec == 4 * 86400.0
    @test telemetry_settings(empty).alert_persistence == 3
    @test telemetry_settings(empty).alert_crediting == "signal"
    @test_throws ArgumentError telemetry_settings(
        Dict{String,Any}("telemetry" => Dict{String,Any}("alert_crediting" => "merger")),
    )
    @test telemetry_settings(empty).psd_mode == "sidecar"
    @test telemetry_settings(empty).psd_segment_length == 65536
    @test telemetry_settings(
        Dict{String,Any}("telemetry" => Dict{String,Any}("psd_mode" => "trailing")),
    ).psd_mode == "trailing"
    @test_throws ArgumentError telemetry_settings(
        Dict{String,Any}("telemetry" => Dict{String,Any}("psd_mode" => "full_record")),
    )
    @test_throws ArgumentError telemetry_settings(
        Dict{String,Any}("telemetry" => Dict{String,Any}("alert_persistence" => 0)),
    )
end

@testset "Product identity (pre-processing)" begin
    mktempdir() do dir
        fs = 0.2
        n = 12_000
        h5 = joinpath(dir, "record.h5")
        function write_record(seed)
            noise =
                synthesize_noise(StableRNG(seed), n, fs; f_min = 1e-5, psd = lisa_noise_psd)
            HDF5.h5open(h5, "w") do file
                tdi = HDF5.create_group(HDF5.create_group(file, "obs"), "tdi")
                tdi["t"] = collect((0:(n-1)) ./ fs)
                tdi["X"] = zeros(n)
                tdi["Y"] = zeros(n)
                tdi["Z"] = sqrt(2.0) .* noise
            end
        end
        write_record(1)
        digest = content_digest(h5)
        config = Dict{String,Any}(
            "paths" => Dict{String,Any}("inputs" => joinpath(dir, "inputs")),
            "preprocessing" => Dict{String,Any}(
                "h5_file" => h5,
                "tdi_group" => "obs/tdi",
                "psd" => "none",
                "output_prefix" => "identity",
                "edge_margin" => 1.0,
            ),
        )
        product = preprocess_record(config)
        @test !product.skipped
        sidecar = TOML.parsefile(product.sidecar_path)
        @test sidecar["product"]["kind"] == "features" &&
              sidecar["product"]["channels"] == "A"
        @test sidecar["product"]["parents"] == Dict{String,Any}("source" => digest)
        # An input touched but unchanged keeps the identity of the product;
        # an input with other content makes a new one
        touch(h5)
        @test preprocess_record(config).skipped
        write_record(2)
        @test content_digest(h5) != digest
        @test !preprocess_record(config).skipped
    end
end

@testset "Figures (CairoMakie extension)" begin
    @test Base.get_extension(MilliHertzBase, :MilliHertzBaseCairoMakieExt) !== nothing
    rng = StableRNG(21)
    n = 2000
    days = collect(range(0, 10; length = n))
    labels = zeros(Int, n)
    labels[400:500] .= 1
    labels[1200:1350] .= 1
    probs = clamp.(0.3 .+ 0.08 .* randn(rng, n) .+ 0.3 .* labels, 0, 1)
    @test figure_mission_trace(days, probs, 0.55; labels = labels) isa CairoMakie.Figure
    @test figure_mission_trace(days, probs, 0.55) isa CairoMakie.Figure
    # Scores beyond the unit interval stay inside the score axis
    trace = figure_mission_trace(days, 2 .* probs .+ 1, 2.1; score_label = "RMS")
    ax_trace = only(filter(a -> a isa CairoMakie.Axis, trace.content))
    @test ax_trace.ylabel[] == "RMS"
    @test ax_trace.limits[][2][1] < 1 + 2 * minimum(probs) &&
          ax_trace.limits[][2][2] > 1 + 2 * maximum(probs)
    @test_throws DimensionMismatch figure_mission_trace(days[1:10], probs, 0.5)
    strain = synthesize_noise(rng, 4000, 0.2; f_min = 1e-5, psd = lisa_noise_psd)
    t_days = ((0:3999) ./ 0.2) ./ 86400
    lab = zeros(Int, 4000)
    lab[1500:1800] .= 1
    @test figure_telemetry_trace(t_days, strain, lab) isa CairoMakie.Figure
    @test figure_telemetry_trace(
        t_days,
        strain,
        lab;
        whitened = whiten_record(strain, 0.2; psd = lisa_noise_psd),
    ) isa CairoMakie.Figure
    # The sidecar records the base single-panel canvas actually exported
    mktempdir() do dir
        save_figure(figure_mission_trace(days, probs, 0.55), joinpath(dir, "single"))
        @test TOML.parsefile(joinpath(dir, "single.toml"))["figure"]["size_pt"] ==
              [900, 600]
    end
end

include("export_payload_tests.jl")
include("telemetry_integration_tests.jl")
include("labeling_tests.jl")
include("response_tests.jl")
