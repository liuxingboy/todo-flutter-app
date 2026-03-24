# 🚀 GTD-Master: 基于 Flutter 的现代跨平台个人效能管理系统

![Flutter](https://img.shields.io/badge/Frontend-Flutter-45D1FD.svg)
![Dart](https://img.shields.io/badge/Dart-3.11+-blue.svg)
![Material 3](https://img.shields.io/badge/UI-Material%203-7B1FA2.svg)
![Dio](https://img.shields.io/badge/Network-Dio-red.svg)

## 📖 项目简介
GTD-Master 客户端是一个基于 **Flutter** 构建的现代化跨平台个人效能管理（Getting Things Done）应用。
它为用户提供了一个优雅、流畅且高度响应的界面，用于管理每日任务、灵感便签以及共享云盘资源。本项目深度对接高性能 C++20 后端，实现了从任务规划到文件共享的完整闭环体验。

---

## 🛠️ 前端技术栈 (Frontend Tech Stack)

*   **核心框架**: Flutter (Dart 3.x) - 提供丝滑的跨平台（Android / iOS / Web / Windows）原生性能体验。
*   **网络引擎**: **Dio** - 深度定制的异步请求客户端。
    *   集成全局拦截器 (Interceptors)。
    *   支持 JWT 双令牌（Access/Refresh Token）无感刷新。
    *   针对 Web 端的代理自适应逻辑。
*   **状态管理**: **Provider** - 响应式编程模型，确保数据流向清晰且 UI 实时同步。
*   **本地持久化**: **SharedPreferences** - 存储用户凭证、服务器配置及“记住密码”状态。
*   **布局艺术**: 使用 `flutter_staggered_grid_view` 实现动态瀑布流布局。

---

## ✨ 核心特性与前端亮点 (Key Features & Highlights)

### 1. 🛡️ 智能鉴权与安全增强
*   **无感登录体验**: 实现 401 拦截器逻辑，当 Access Token 过期时自动调用 Refresh 接口，用户在操作过程中无需重新登录。
*   **凭据持久化**: 支持“记住密码”功能，利用本地加密存储（或安全偏好设置）优化二次登录流程。

### 2. ✅ GTD 任务流转引擎
*   **“我的一天”系统**: 专注于当下。通过 Material 3 风格的交互，将复杂的任务池模板一键“实例化”到今日清单。
*   **任务池管理**: 直观的瀑布流卡片展示，支持级联式任务分类与管理。
*   **实时状态反馈**: 每一项操作（如任务切换、删除）均配有精准的 SnackBar 提示与 UI 动效反馈。

### 3. ☁️ 跨平台文件管理
*   **云盘共享中心**: 专为大文件吞吐优化。支持通过 `file_picker` 选择任意类型文件并上传至 C++ 后端存储。
*   **预览与权限控制**: 界面直观区分“上传者”与“普通查看者”，严格控制文件的删除权限，确保数据共享安全。

### 4. 📝 灵感便签
*   极简设计的随手记模块，按更新时间戳动态倒序排列，支持长文本实时编辑与自动保存。

---

## 🏗️ 项目架构 (Project Architecture)

项目遵循标准的 Flutter 领域驱动设计理念：
*   `lib/models/`: 数据实体模型，严格映射后端 JSON 结构。
*   `lib/services/`: 核心业务服务层（如 `ApiService`），封装底层的 RESTful 调用。
*   `lib/providers/`: 业务逻辑中心，处理状态变更与 UI 驱动。
*   `lib/pages/`: 视图层，包含响应式 UI 组件与页面路由。

---

## 🚀 快速开始 (Getting Started)

### 1. 环境要求
*   Flutter SDK: `^3.11.1`
*   Dart SDK: `^3.11.1`

### 2. 获取依赖
```bash
flutter pub get
```

### 3. 配置后端地址
在应用设置页面或 `ApiService` 默认配置中指定你的 C++ 后端 IP 与端口。

### 4. 运行应用
```bash
# 运行到 Android 设备
flutter run -d <device_id>

# 运行 Web 端
flutter run -d chrome
```

---

## 🤝 贡献与支持
如果您觉得这个项目对您有帮助，欢迎点击页面上的“打赏作者”按钮，支持独立开发！

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
