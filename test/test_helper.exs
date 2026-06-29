ExUnit.start()

Application.put_env(
  :jidoka,
  :snapshot_signing_secret,
  "tilde-test-snapshot-signing-secret-00000000"
)

unless System.get_env("TILDE_QUACKDB_INTEGRATION") in ["1", "true"] do
  ExUnit.configure(exclude: [quackdb_integration: true])
end

for support <- [
      "../test_helpers/assertions/session.ex",
      "../test_helpers/assertions/interaction.ex",
      "../test_helpers/assertions/widget.ex",
      "../test_helpers/fakes/runtime.ex",
      "../test_helpers/cases/base.ex",
      "../test_helpers/drivers/driver.ex",
      "../test_helpers/cases/transport.ex",
      "../test_helpers/cases/browser.ex"
    ] do
  Code.require_file(support, __DIR__)
end

for support <- Path.wildcard(Path.expand("../test_helpers/drivers/**/*.ex", __DIR__)) do
  Code.require_file(support)
end
