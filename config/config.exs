import Config

config :tilde,
  ecto_repos: [Tilde.Storage.Repo],
  devtools: config_env() in [:dev, :test]

config :tilde, Tilde.Storage.Repo,
  uri: System.get_env("TILDE_QUACKDB_URI", "http://[::1]:9494"),
  token: System.get_env("TILDE_QUACKDB_TOKEN")

config :tilde, Tilde.Demo.Endpoint,
  code_reloader: true,
  debug_errors: true

config :volt,
  entry: "assets/js/app.ts",
  outdir: "priv/static/assets",
  root: "assets",
  target: :es2020,
  sourcemap: :hidden,
  sources: ["**/*.{js,ts}"],
  ignore: ["node_modules/**"],
  resolve_dirs: ["node_modules", "deps"],
  tailwind: [
    css: "assets/css/app.css",
    sources: [
      %{base: "lib/", pattern: "**/*.{ex,heex}"},
      %{base: "assets/", pattern: "**/*.{js,ts,css}"}
    ]
  ]

config :volt, :server,
  prefix: "/assets",
  watch_dirs: ["assets/", "lib/"]

config :volt, :format,
  print_width: 100,
  semi: false,
  single_quote: false,
  trailing_comma: :none,
  arrow_parens: :always

config :volt, :lint,
  plugins: [:typescript],
  rules: %{
    "no-debugger" => :deny,
    "eqeqeq" => :deny
  }
