# 应用图标

`AppIcon.icon` 是 Icon Composer 源文件，`Assets/Light.png` 与 `Assets/Dark.png` 分别用于默认、深色外观。图层关闭额外玻璃效果，以保留原稿颜色。

- Xcode 26+ 打包时，`script/build_and_run.sh` 使用 `actool` 生成应用包根资源中的 `Assets.car` 与 `AppIcon.icns`；`CFBundleIconName` 指向 `AppIcon`。
- macOS 26 的 Finder 和未运行应用遵循系统“图标与小组件样式”。选择“深色 → 自动”才会跟随系统深浅色；固定样式属于系统用户偏好。
- 运行中的 Dock 图标由 `ApplicationIconController` 监听 `NSApplication.effectiveAppearance` 更新，兼容 macOS 15+。不修改应用包、不扫描目录。
- Icon Composer 导出的运行时 PNG 是紧边图形；控制器将其绘制到 1024×1024 透明画布内的 824×824 居中区域（四周 100），与系统图标留白一致。不要再次给源 PNG 添加相同留白，以免双重缩小。原生 Assets.car 仍由系统管理边距。
- 旧工具链保留静态 ICNS 回退；旧 macOS 的 Finder 图标为静态浅色。

修改源图后，用 Xcode 的 Icon Composer 导出两种 macOS rendition，更新运行时 PNG：

```bash
ICON_TOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
"$ICON_TOOL" Artwork/AppIcon.icon --export-image --output-file Sources/SpacePilot/Resources/AppIcon/AppIcon-Light.png --platform macOS --rendition Default --width 512 --height 512 --scale 2
"$ICON_TOOL" Artwork/AppIcon.icon --export-image --output-file Sources/SpacePilot/Resources/AppIcon/AppIcon-Dark.png --platform macOS --rendition Dark --width 512 --height 512 --scale 2
```

验证：`swift test --filter ApplicationIconControllerTests` 与 `./script/test_release.sh`，再在系统设置中切换浅色、深色、浅色，检查 Dock，最后恢复原来的系统外观选择。
