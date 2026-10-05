cask "polinshield" do
  version "1.0.0"
  sha256 "d9a8af9b3fbdf21e7edc4a2ceda4388cb8c66b4ab6d9755b102197ebad470d96"

  url "https://github.com/Louayzouaoui1/polinshield/releases/download/v#{version}/PolinShield-#{version}.dmg"
  name "PolinShield"
  desc "Menu bar defense against npm supply-chain malware"
  homepage "https://github.com/Louayzouaoui1/polinshield"

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
