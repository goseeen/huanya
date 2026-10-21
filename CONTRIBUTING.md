# 参与开发

问题与建议请通过 Issues 提交。修复或新功能建议先说明使用场景，保持改动集中。

## 本地检查

在 macOS 13+ 上使用 Apple 开发工具：

```sh
zsh scripts/test.sh
zsh scripts/build.sh
```

`Core.swift` 负责设置、计时和数据结构，`AppModel.swift` 负责运行状态，`SystemIntegration.swift` 负责系统集成，`Views.swift` 负责界面，`BrandArtwork.swift` 提供标识绘图。

更改计时、统计或数据格式时，补充覆盖实际行为的测试，保持旧数据可读。界面可用 README 中的 `--capture` 模式生成演示截图。涉及 Apple 芯片行为的修改需注明是否经过实机测试。

## 提交内容

- 不提交个人 state.json、CSV、备份、安装包、证书、密钥或本机路径。
- 截图使用演示数据，日志先移除个人信息。
- 外部内容注明来源和许可，不添加授权不明的图片、字体或音频。
- 不因空闲或锁屏自动增加完成休息次数，保持统计语义清晰。

代码贡献按 MIT 许可提供。新增图形需另行注明来源与授权范围，见 [ASSETS.md](ASSETS.md)。
