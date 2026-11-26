# Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
# Install: brew install --cask matakartal/nabiz/nabiz   (after: brew tap matakartal/nabiz https://github.com/matakartal/nabiz)
cask "nabiz" do
  version "1.10.0"
  sha256 "a8dd6d252608093f62bcbfca76cf263b90916da09ce84806f502da05e1df2cab"

  url "https://github.com/matakartal/nabiz/releases/download/v#{version}/Nabiz-#{version}.dmg"
  name "Nabız"
  desc "Menu bar system monitor with one-tap fixes, AI chat and developer tools"
  homepage "https://github.com/matakartal/nabiz"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Nabiz.app"

  zap trash: [
    "~/Library/Application Support/Nabiz",
    "~/Library/Caches/app.nabiz.menubar",
    "~/Library/Preferences/app.nabiz.menubar.plist",
  ]
end
