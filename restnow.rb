cask "restnow" do
  version "1.0.0"
  sha256 "b4f170e155811039d9674d0e42fe03b9b4ea787aa036098af9135d90afbc1783"

  url "https://github.com/krjadhav/Rest-Now/releases/download/v#{version}/RestNow.dmg"
  name "RestNow"
  desc "macOS app to remind you to take breaks and rest your eyes"
  homepage "https://github.com/krjadhav/Rest-Now"

  depends_on macos: ">= :sequoia"

  app "RestNow.app"
end
