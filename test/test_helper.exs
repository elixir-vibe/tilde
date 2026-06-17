ExUnit.start()

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
