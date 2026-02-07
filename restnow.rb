cask "restnow" do
  version "1.0.1"
  sha256 "24d2a17e1ebcaab4ec7e88c51f2f231157a08e43174b201f263dbd0582bad3ab"

  url "https://github.com/krjadhav/Rest-Now/releases/download/v#{version}/RestNow.dmg"
  name "RestNow"
  desc "macOS app to remind you to take breaks and rest your eyes"
  homepage "https://github.com/krjadhav/Rest-Now"

  depends_on macos: ">= :sequoia"

  app "RestNow.app"
end
