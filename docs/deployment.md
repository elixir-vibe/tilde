# Demo deployment

`mix tilde.demo` is intended for supervised local/demo deployments behind a reverse proxy. Temporary development demos should use the `elixir.parts` route helper from `elixir-toys`, not a permanent `elixir.toys` service domain.

## Environment

Create a private `.env` in the project directory:

```env
OPENROUTER_API_KEY=...
TILDE_DEMO_PASSWORD=...
```

The demo loads `.env`, `dev.env`, `.env.local`, and `dev.override.env` before startup.

## Health check

The unauthenticated health endpoint is:

```text
GET /healthz -> 200 ok
```

## systemd example

```ini
[Unit]
Description=Tilde demo
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=dannote
WorkingDirectory=/home/dannote/Development/elixir-vibe/tilde
ExecStart=/home/dannote/.local/bin/mise exec -- mix tilde.demo --web-port 4100 --ssh-port 4122 --host tilde.elixir.parts --hmr
Restart=always
RestartSec=3
Environment=MIX_ENV=dev

[Install]
WantedBy=multi-user.target
```

Expose the local web port through a temporary private route:

```sh
sudo toys-route private tilde 4100 --ttl 7d --note "Tilde dev demo"
```

Use `toys-route preview` only for intentionally public previews. Use `--no-hmr` for non-development demo runs once LiveReload is not needed.
