# Integration test of the payload export with the producer: a TDI record is
# exported on the A channel and on the A and E network, a DeepSpaceTelemetry
# mission on its tick clock ingests each payload, and the runs are read back
# through StreamingInference's extension (`open_telemetry_run`, re-exported)
# and replayed with reference scorers; included by runtests.jl.

# A stateless reference scorer: the RMS of the conditioned window, unity for
# noise whitened by its own PSD.
struct RMSScorer <: AbstractWindowScorer end
StreamingInference.window_score(::RMSScorer, window::AbstractVector{<:Real}, ::Real) =
    Float32(sqrt(sum(abs2, window) / length(window)))
StreamingInference.score_bounds(::RMSScorer) = (0.0, Inf)

# The RMS of the first channel of a multichannel window.
struct FirstChannelRMS <: AbstractWindowScorer end
StreamingInference.window_score(::FirstChannelRMS, window::AbstractMatrix{<:Real}, ::Real) =
    Float32(sqrt(sum(abs2, view(window, :, 1)) / size(window, 1)))
StreamingInference.score_bounds(::FirstChannelRMS) = (0.0, Inf)

"""
A mission of one day on the producer's tick clock over the payload of the
scenario fragment at `fragment_path`, run under `dir`; returns the run
directory.
"""
function tick_mission(dir, run_id, fragment_path)
    fragment = TOML.parsefile(fragment_path)
    physics = fragment["physics"]
    physics["external_data_path"] = resolvepath(physics["external_data_path"])
    scenario = Dict{String,Any}(
        "simulation" => Dict{String,Any}(
            "speed_up" => 3600.0,
            "start_sim_time" => fragment["simulation"]["start_sim_time"],
            "mission_wall_seconds" => 24.0,   # one day at 3600×
            "initial_downtime_days" => 0.0,
            "rng_seed" => 7,
        ),
        "storage" => Dict{String,Any}("max_storage_gb" => 2.0),
        "supervision" => Dict{String,Any}("on_component_failure" => "abort"),
        "telemetry" => Dict{String,Any}(
            "session_start" => "00:00:00",
            "session_duration_hours" => 24.0,
            "bandwidth_profile" => "flat",
            "max_batches_per_hour" => 200.0,
        ),
        "physics" => physics,
        "events" => fragment["events"],
        "packet_loss" => Dict{String,Any}("enabled" => false),
        "dashboard" => Dict{String,Any}(
            "open_live_viewer" => false,
            "open_receiver_log" => false,
            "open_emitter_log" => false,
        ),
        "post_processing" => Dict{String,Any}(
            "generate_mask_timeline" => false,
            "expand_to_pointwise_masks" => false,
            "alert_latency" => false,
            "delivery_delay" => false,
            "hdf5_export" => false,
        ),
    )
    TelemetryCore = DeepSpaceTelemetry.TelemetryCore
    path = joinpath(dir, "$run_id.toml")
    open(io -> TOML.print(io, scenario), path, "w")
    cfg = TelemetryCore.tick_configuration(TelemetryCore.load_config(path))
    previous = TelemetryCore.DATA_ROOT[]
    TelemetryCore.DATA_ROOT[] = joinpath(dir, "producer")
    try
        return DeepSpaceTelemetry.Supervisor.run_mission(
            cfg;
            run_id = run_id,
            orig_stdout = devnull,
        )
    finally
        TelemetryCore.DATA_ROOT[] = previous
    end
end

@testset "Telemetry coupling (exported payload, DeepSpaceTelemetry run)" begin
    fs = 0.2
    n = 17_280                            # one mission day at 0.2 Hz
    mktempdir() do dir
        # A record whose A and E channels are independent noise
        A = synthesize_noise(StableRNG(41), n, fs; f_min = 1e-5, psd = lisa_noise_psd)
        E = synthesize_noise(StableRNG(42), n, fs; f_min = 1e-5, psd = lisa_noise_psd)
        # X, Y, Z of the A, E channels with T = 0 (the inverse of tdi_to_aet)
        X = (-A ./ sqrt(2)) .+ (E ./ sqrt(6))
        Y = -2 .* E ./ sqrt(6)
        Z = (A ./ sqrt(2)) .+ (E ./ sqrt(6))
        h5 = joinpath(dir, "record.h5")
        HDF5.h5open(h5, "w") do file
            g = HDF5.create_group(HDF5.create_group(file, "obs"), "tdi")
            g["t"] = collect((0:(n-1)) ./ fs)
            g["X"] = X
            g["Y"] = Y
            g["Z"] = Z
        end
        start = DateTime(2035, 1, 1)
        config = Dict{String,Any}(
            "paths" => Dict{String,Any}("inputs" => joinpath(dir, "inputs")),
            "preprocessing" =>
                Dict{String,Any}("h5_file" => h5, "tdi_group" => "obs/tdi"),
            "telemetry" => Dict{String,Any}(
                "segment_duration_sec" => 50,
                "batch_size" => 10,
                "start_sim_time" => string(start),
                "output_prefix" => "coupling",
            ),
        )
        single = export_telemetry_payload(config; channels = "A")
        pair = export_telemetry_payload(config; channels = "AE")
        record, _ = channel_record(h5; channels = "AE")
        @test isapprox(record[:, 1], A; rtol = 1e-5) &&
              isapprox(record[:, 2], E; rtol = 1e-5)

        run = open_telemetry_run(
            tick_mission(dir, "single", single.scenario_path);
            producer_compat = "2.6",
        )
        pair_dir = tick_mission(dir, "pair", pair.scenario_path)
        pair_run = open_telemetry_run(pair_dir; columns = ["A", "E"])
        geometry = run_geometry(run)
        @test geometry.start_sim_time == start && geometry.payload_rows == n
        @test run_descriptor(run)["mode"] == "tick"
        # The producer records the commit of a copy installed by commit (2.6.1)
        @test occursin(r"^[0-9a-f]{40}$", run_descriptor(run)["git_commit"])
        delivered = filter(b -> b.state == :ground, list_batches(run))
        b = first(delivered)
        @test read_batch(run, b.name) == record[b.rows, 1]
        @test read_batch(pair_run, b.name) == record[b.rows, :]
        # A run of two payload columns is served only by name
        @test_throws ArgumentError open_telemetry_run(pair_dir)

        conditioning =
            (sample_rate = fs, window_size = 1000, step_size = 100, context_windows = 2)
        windows = replay_run(
            run,
            StreamingDetector(RMSScorer(), 1.0; conditioning..., psd = lisa_noise_psd),
        )
        @test nrow(windows) >= 1 && all(windows.coverage .== 1.0)
        # The producer realises what the one-column mission emulated: both
        # channels in one batch and one transfer. The two-column mission
        # delivers on the same schedule, and its replay is that of the
        # one-column mission with E served from the record
        pair_detector = StreamingDetector(
            FirstChannelRMS(),
            1.0;
            conditioning...,
            psd = (lisa_noise_psd, lisa_noise_psd),
        )
        @test [e.sim_time for e in arrival_events(pair_run)] == [e.sim_time for e in arrival_events(run)]
        @test replay_run(pair_run, pair_detector).score ==
              replay_run(ScheduledRecordRun(run, record), pair_detector).score ==
              windows.score
    end
end
