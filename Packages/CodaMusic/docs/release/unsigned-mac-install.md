
---

### macOS 安装说明 / Installing on macOS

本版 Mac 应用未经 Apple 公证（ad-hoc 签名）。首次打开时 macOS 会提示无法验证开发者：

1. 解压 `Coda-*.zip`，把 **Coda** 拖到「应用程序」。
2. 双击打开，出现提示后点「完成」。
3. 打开「系统设置 → 隐私与安全性」，在页面下方点「仍要打开」，输入密码确认。

也可以在终端移除下载隔离标记后直接打开：

```sh
xattr -dr com.apple.quarantine /Applications/Coda.app
```

This build is ad-hoc signed and not notarized. After the first launch is blocked, open **System Settings → Privacy & Security** and click **Open Anyway**, or run the command above.
