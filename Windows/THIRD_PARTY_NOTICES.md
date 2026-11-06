# Windows 客户端依赖与素材

项目自有代码与图形使用根目录 LICENSE 中的 MIT 许可。图形制作方式见根目录 ASSETS.md。

Windows 客户端使用：

- Avalonia / Avalonia.Desktop / Avalonia.Themes.Fluent 11.3.22 — MIT，https://github.com/AvaloniaUI/Avalonia/blob/master/licence.md
- Avalonia.Headless 11.3.22 — MIT，仅测试依赖，不随客户端发布。
- .NET 10 — MIT，https://github.com/dotnet/runtime/blob/main/LICENSE.TXT
- SkiaSharp、HarfBuzzSharp 及其原生组件 — 各包包含的 MIT、BSD 许可和第三方声明适用，https://github.com/mono/SkiaSharp

具体传递依赖由各项目 packages.lock.json 固定。发布包必须随附依赖提供的许可证及第三方声明；依赖升级后重新核对。

应用不打包 Apple 字体、SF Symbols 或 macOS 音效。Windows 优先使用系统 Microsoft YaHei UI；其他平台预览使用系统字体回退。Windows 通知和音效由系统提供。

`ThirdPartyLicenses/` 保留了 Avalonia、MicroCom、Tmds.DBus、ANGLE、SkiaSharp、HarfBuzzSharp、System.IO.Pipelines 和 .NET Runtime 的版权、许可及第三方声明；构建时复制到运行包的 `licenses/` 目录。文件来自对应 NuGet 包或上游公开许可证，未改写授权条款。
