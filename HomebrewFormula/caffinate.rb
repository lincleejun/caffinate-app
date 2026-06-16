# 把本文件放进你的 tap 仓库（如 lincleejun/homebrew-tap 的 Casks/caffinate.rb）后,
# 即可 `brew install --cask lincleejun/tap/caffinate`。
# 发新版本时更新 version；如需校验和把 :no_check 换成真实 sha256。
cask "caffinate" do
  version "0.0.1"
  sha256 :no_check

  url "https://github.com/lincleejun/caffinate-app/releases/download/v#{version}/Caffinate.app.zip"
  name "Caffinate"
  desc "防休眠 + 番茄钟 + 系统 Focus 联动的 macOS 菜单栏小工具"
  homepage "https://github.com/lincleejun/caffinate-app"

  app "Caffinate.app"

  caveats <<~EOS
    未签名应用。若提示「无法打开」,右键 App → 打开,或执行:
      xattr -dr com.apple.quarantine "#{appdir}/Caffinate.app"

    可选命令行 caf:从 Releases 下载后 `sudo cp caf /usr/local/bin/`。
  EOS
end
