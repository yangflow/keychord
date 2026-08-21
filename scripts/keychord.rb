# Homebrew cask template for keychord.
#
# Install:
#   1. (Owner) Create a tap repo named homebrew-keychord (or similar)
#      and copy this file to Formula/keychord.rb inside it.
#   2. (Owner) After each release, update `version` and `sha256` to
#      match dist/keychord-<version>.dmg.sha256 from scripts/release.sh.
#   3. (User) brew tap ydongy/keychord
#              brew install --cask keychord
#
# When submitting to the canonical homebrew-cask repo instead of a
# personal tap, the artifact MUST be notarized — Homebrew will reject
# anything Gatekeeper would warn on.

cask "keychord" do
  version "0.4.0"
  sha256 "def75eccb6b9a732a8889c8a275cf84838d4232581c057ee3a5ed9fa4f056675"

  url      "https://github.com/yangflow/keychord/releases/download/v#{version}/KeyChord-#{version}.dmg"
  name     "KeyChord"
  desc     "macOS menubar Git SSH multi-account manager"
  homepage "https://github.com/yangflow/keychord"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "KeyChord.app"

  zap trash: [
    "~/.config/keychord",
    "~/Library/Caches/com.yangflow.keychord",
    "~/Library/Preferences/com.yangflow.keychord.plist",
  ]
end
