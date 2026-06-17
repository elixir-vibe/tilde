ExUnit.start()

for support <- [
      "../test_helpers/tilde_driver.ex",
      "../test_helpers/tilde_transport_case.ex",
      "../test_helpers/tilde_browser_case.ex"
    ] do
  Code.require_file(support, __DIR__)
end

for support <- Path.wildcard(Path.expand("../test_helpers/tilde_driver/**/*.ex", __DIR__)) do
  Code.require_file(support)
end
