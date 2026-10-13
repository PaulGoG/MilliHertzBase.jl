# Coupling to the DeepSpaceTelemetry producer (implemented by the package
# extension).

"""
    open_telemetry_run(run_dir; producer_compat = "1.0") -> AbstractTelemetryRun

Open a DeepSpaceTelemetry run directory through the producer's own API.
Implemented by the package extension that loads with DeepSpaceTelemetry;
`producer_compat` is the accepted lower bound of the producer version
recorded in the run's configuration snapshot. A run that carries several
payload columns (`[provenance] external_data_columns`, DeepSpaceTelemetry
2.6.0) is refused: the extension serves the one-column payload the export
stage writes.
"""
function open_telemetry_run end
