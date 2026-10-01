include(joinpath(@__DIR__, "activate.jl"))

using Documenter
using DocumenterInterLinks
using MilliHertzBase

# Cross-references to the domain-general layer resolve against its manual.
links = InterLinks(
    "StreamingInference" => "https://PaulGoG.github.io/StreamingInference.jl/dev/",
)
fallbacks = ExternalFallbacks(; automatic = true)

makedocs(
    sitename = "MilliHertzBase.jl",
    authors = "Paul-Adrian Gogîță",
    repo = Remotes.GitHub("PaulGoG", "MilliHertzBase.jl"),
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://PaulGoG.github.io/MilliHertzBase.jl",
        size_threshold_ignore = ["api.md"],
    ),
    modules = [MilliHertzBase],
    plugins = [links, fallbacks],
    pages = ["Home" => "index.md", "API reference" => "api.md"],
)

# Deployment to the gh-pages branch: `main` under dev/, release tags under
# their version and stable/. Outside GitHub Actions this is a no-op.
deploydocs(
    repo = "github.com/PaulGoG/MilliHertzBase.jl.git",
    devbranch = "main",
    push_preview = false,
)
