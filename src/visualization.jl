# Figure interface of the gravitational-wave layer (implemented by the
# CairoMakie extension).

"""
    figure_mission_trace(days, probabilities, threshold; labels = nothing,
                         max_points = 5000, score_label = "Score",
                         score_name = "Window score", score_range = nothing) -> Figure

Window scores against mission time [days] with the decision threshold
and, when `labels` is given, the labelled spans as shaded bands. The score
axis is labelled `score_label`, the trace `score_name` in the legend, and
the axis spans `score_range`, by default the range of the scores and the
threshold widened by 5 %. Long traces are decimated to about `max_points`
samples. Requires CairoMakie.
"""
function figure_mission_trace end

"""
    figure_telemetry_trace(t_days, strain, labels; max_points = 5000, whitened = nothing) -> Figure

Simulated strain record against mission time with the labelled spans as
shaded bands, an axis offset multiplier for the small strain amplitudes,
and, when `whitened` is given, a second panel with the whitened record.
Requires CairoMakie.
"""
function figure_telemetry_trace end
