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
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_dist_keychord_VERSION_dmg_sha256"

  url      "https://github.com/ydongy/keychord/releases/download/v#{version}/keychord-#{version}.dmg"
  name     "keychord"
  desc     "macOS menubar Git SSH multi-account manager"
  homepage "https://github.com/ydongy/keychord"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "keychord.app"

  zap trash: [
    "~/.config/keychord",
    "~/Library/Caches/com.yangflow.keychord",
    "~/Library/Preferences/com.yangflow.keychord.plist",
  ]
end
