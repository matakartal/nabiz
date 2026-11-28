# Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
# Install: brew install --cask matakartal/nabiz/nabiz   (after: brew tap matakartal/nabiz https://github.com/matakartal/nabiz && brew trust matakartal/nabiz)
cask "nabiz" do
  version "1.11.0"
  sha256 "71042f9a38d9014c62ab5779b9c94d915b8b8507d4c07143d69994b500ad51f1"

  url "https://github.com/matakartal/nabiz/releases/download/v#{version}/Nabiz-#{version}.dmg"
  name "Nabız"
  desc "Menu bar system monitor with one-tap fixes, AI chat and developer tools"
  homepage "https://github.com/matakartal/nabiz"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Nabiz.app"

  zap trash: [
    "~/Library/Application Support/Nabiz",
    "~/Library/Caches/app.nabiz.menubar",
    "~/Library/Preferences/app.nabiz.menubar.plist",
  ]
end
