cask "restnow" do
  version "1.0.1"
  sha256 "dc1cf33f2532f921d0e91e7880c17f19c4f19ef6ac1db162bd82ba53e3354aae"

  url "https://github.com/krjadhav/Rest-Now/releases/download/v#{version}/RestNow.dmg"
  name "RestNow"
  desc "macOS app to remind you to take breaks and rest your eyes"
  homepage "https://github.com/krjadhav/Rest-Now"

  depends_on macos: ">= :sequoia"

  app "RestNow.app"
end
