# 静态页面展示

这是一个原生 macOS 应用，用于在局域网中展示静态 HTML 页面。应用内置 HTTP 服务，不依赖 Python、Node.js 或第三方运行库。

## 功能

- 手动启动和停止 HTTP 服务
- 菜单栏常驻控制
- 仅本机、指定网卡或全部网络三种监听范围
- 可选 Basic Auth 访问码
- HTTP Range、ETag 和 Last-Modified 响应
- 自动发现页面目录中的 HTML
- 自动刷新展示首页
- 持久化端口、网卡和自动启动设置

## 构建

```bash
./build-app.sh
```

构建完成后会生成：

```text
dist/静态页面展示.app
dist/静态页面展示.dmg
```

应用包含 `arm64` 和 `x86_64` 两种架构，默认使用本机临时签名。

如需正式签名和公证，可以在构建前设置：

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="notarytool-profile-name"
./build-app.sh
```

## 使用

1. 选择端口、访问范围和网卡。
2. 根据需要启用访问码。
3. 点击“启动服务”。
4. 将应用显示的访问地址发送给同一网络中的其他设备。
5. 关闭主窗口后应用继续在菜单栏运行；退出 App 才会停止服务。

## 添加页面

在应用中点击“打开页面目录”，将 HTML 文件或完整的页面文件夹放入该目录。应用会自动发现变化，也可以点击“刷新”。

支持两种常见结构：

```text
Web/
├── report.html
└── project/
    ├── index.html
    └── assets/
```

页面目录位于：

```text
~/Library/Application Support/安华金和静态页面/Web
```

名称以 `_files` 结尾的辅助资源目录不会出现在展示列表中。

## 页面配置

页面目录中的 `pages.json` 可以配置标题、描述、分组、排序、封面、新窗口打开和显示开关：

```json
{
  "pages": {
    "project/index.html": {
      "title": "项目说明",
      "description": "项目介绍和操作说明",
      "group": "项目",
      "enabled": true,
      "order": 10,
      "cover": "project/cover.png",
      "openInNewWindow": false
    }
  }
}
```

将 `enabled` 设置为 `false` 后，页面不会显示在公开展示首页中。应用主窗口仍会列出该页面，并标记为“已隐藏”。

## 安全

- 展示服务只访问独立的页面目录，不暴露项目源码或 `.git` 数据。
- “仅本机”模式只监听 `127.0.0.1`。
- “指定网卡”模式只绑定所选网络地址。
- 访问码使用 HTTP Basic Auth；在不受信任的网络中建议配合 HTTPS 反向代理使用。
