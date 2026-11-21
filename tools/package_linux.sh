#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
cd "$root"
version=$(sed -n 's/^version: *//p' "$root/pubspec.yaml" | head -n1)
bundle="$root/build/linux/x64/release/bundle"
dist="$root/dist"
name="dart_servo_studio-linux-x64-v${version}"
archive="$dist/${name}.tar.gz"
checksum="$archive.sha256"

if [[ "${1:-}" != --no-build ]]; then
  flutter=${FLUTTER:-"$root/.tools/flutter/bin/flutter"}
  if [[ ! -x "$flutter" ]]; then
    flutter=$(command -v flutter || true)
  fi
  [[ -n "$flutter" ]] || {
    echo "未找到 Flutter SDK，请设置 FLUTTER=/path/to/flutter/bin/flutter" >&2
    exit 1
  }
  "$flutter" build linux --release
fi
[[ -x "$bundle/dart_servo_studio" && -f "$bundle/lib/libapp.so" ]] || {
  echo "找不到完整的 Linux x64 Release bundle" >&2
  exit 1
}

stage=$(mktemp -d "${TMPDIR:-/tmp}/dart-servo-studio-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
package_root="$stage/$name"
mkdir -p "$package_root"
cp -a "$bundle/." "$package_root/"

cat >"$package_root/start.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
jlink_dir=${JLINK_DIR:-"$PWD/jlink"}
if [[ -x "$jlink_dir/JLinkExe" && -r "$jlink_dir/libjlinkarm.so" ]]; then
  export PATH="$(cd "$jlink_dir" && pwd):$PATH"
fi
exec ./dart_servo_studio "$@"
EOF
chmod 0755 "$package_root/start.sh"

cat >"$package_root/GRAY_TESTING.md" <<'EOF'
# Dart Servo Studio · Linux x64 灰度包

## 启动

```bash
./start.sh
```

此包是离线桌面应用，不需要 Flutter SDK、Dart 或 Python。目标机器需要
Linux x64 图形桌面及 GTK 3 运行时。包内不包含固件、J-Link Commander、
J-Link 动态库或舵机硬件。

连接 J-Link 探针时，请从 SEGGER 官网下载并安装 Linux x86-64 软件包，
确保 `JLinkExe` 在 PATH 中。也可以将官方 TGZ 解压后，以
`JLINK_DIR=/path/to/JLink_Linux_x86_64 ./start.sh` 启动，或将解压目录
命名为 `jlink` 放在 `start.sh` 旁。保留同一版本的 `JLinkExe` 和
`libjlinkarm.so*`，不要混用不同版本。

下载：https://www.segger.com/downloads/jlink/

默认启动为离线预览；连接真实设备前，请先阅读项目 README 中的安全说明，
确认板上运行协议 v8 固件，并断开发射动力、保持舵机空载。

TCP RTT 服务只应在受控调试网络中使用，不要暴露到公网。

## 反馈信息

请附上 Linux 发行版、图形环境、复现步骤，以及应用 RTT Console 中的原始
信息。不要上传固件、密钥或其他敏感文件。
EOF

mkdir -p "$dist"
tar -C "$stage" -czf "$archive" "$name"
(
  cd "$dist"
  sha256sum "$(basename "$archive")" >"$(basename "$checksum")"
)
printf '已生成:\n%s\n%s\n大小: ' "$archive" "$checksum"
du -h "$archive" | cut -f1
