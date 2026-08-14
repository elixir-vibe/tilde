[
  layers: [
    core: "Tilde.Core.*",
    application: [
      "Tilde",
      "Tilde.Application",
      "Tilde.Command*",
      "Tilde.Demo.*",
      "Tilde.Dev*",
      "Tilde.Index",
      "Tilde.Index.*",
      "Tilde.Renderer*",
      "Tilde.Runtime.*",
      "Tilde.Session.*",
      "Tilde.Storage*",
      "Tilde.Template*",
      "Tilde.Tool.*",
      "Tilde.Tools*",
      "Tilde.Transport.*",
      "Tilde.View.*",
      "Tilde.Viewable*",
      "Tilde.Workbench*",
      "Mix.Tasks.*"
    ]
  ],
  deps: [
    forbidden: [
      {:core, :application}
    ]
  ],
  checks: [
    layer_coverage: [
      require_all_modules: true,
      forbid_multiple_matches: true
    ]
  ]
]
