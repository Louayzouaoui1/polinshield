cask "polinshield" do
  version "1.0.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/Louay24/polinshield/releases/download/v#{version}/PolinShield-#{version}.dmg"
  name "PolinShield"
  desc "Menu bar defense against npm supply-chain malware"
  homepage "https://github.com/Louay24/polinshield"

  app "PolinShield.app"

  zap trash: [
    "~/Library/Application Support/PolinShield",
    "~/Library/LaunchAgents/dev.polinshield.scan.plist",
    "~/Library/LaunchAgents/dev.polinshield.force-push.plist",
  ]

  caveats <<~EOS
    PolinShield runs as a menu bar item. After install:
      • Click the shield icon in your menu bar
      • Run the welcome wizard (first launch)
      • Grant notification permission when prompted
      • Enter your admin password ONCE for /etc/hosts setup

    For force-push detection, install GitHub CLI: brew install gh && gh auth login
  EOS
end
