ExUnit.start()

Code.require_file("../test_helpers/tilde_driver.ex", __DIR__)

for support <- Path.wildcard(Path.expand("../test_helpers/tilde_driver/**/*.ex", __DIR__)) do
  Code.require_file(support)
end
