# Synology Cloud UI 改版设计文档

> 参考对象：飞牛 fnOS 客户端（`otherProject/appUI/` 下 8 张参考图）
> 设计稿源文件：`docs/ui_redesign/mockup.html`（可浏览器打开查看/微调）
> 设计图：`docs/ui_redesign/01_home.png` ~ `05_search.png`

---

## 一、改版总览

| # | 参考图 | 改版内容 | 设计图 |
|---|--------|---------|--------|
| 1 | homeUI.jpg | 首页 1:1 复刻改版（头像 + 搜索 + 连接状态 + 应用宫格 + 资源监控卡片） | 01_home.png |
| 2 | qidong.jpg / qidong1~3.jpeg | 启动连接页 + 上下拉开动画进首页 | 02_splash.png |
| 3 | 侧边.jpg | 点头像打开侧边抽屉 | 03_drawer.png |
| 4 | settingUI.jpg | 通用 Section 组件（标题+图标宫格卡片，无副标题），改版控制面板 | 04_control_panel.png |
| 5 | search.jpg | 全局搜索（文件名搜索） | 05_search.png |

**设计基调**：延续现有 Material 3 + 主色 `#2563EB`，页面背景改为「淡蓝→浅灰白」垂直渐变（浅色 `#D4E0F2 → #F4F5F7`），卡片纯白、圆角 20，图标网格 iOS 风格圆角彩色方块，无副标题、留白充足。深色模式保持现有 darkModeNotifier 机制，渐变替换为 `#1A1F2B → #121212`。

---

## 二、首页改版（对照 01_home.png）

### 2.1 布局结构（自上而下）

1. **顶部行**（替代现有 AppBar，改为无 AppBar 的沉浸式头部）
   - 左：圆形用户头像（40dp），取账号首字母，背景色由账号名 hash 取色；**点击 → 打开侧边抽屉**
   - 中：白色胶囊搜索框（占满剩余宽度），点击 → 进入全局搜索页
   - 右：铃铛通知按钮（保留现有 NotifyPage 跳转），未读数角标
2. **连接信息区**
   - 第一行小字：`公网连接 | ********👁` 或 `内网连接 | ********👁`
     - 星号处显示当前连接地址（默认打码），点眼睛图标明文/打码切换
   - 第二行大标题：设备名（`_hostname`，无则用 `server.note`/host）+ `›`，点击 → 现有「仪表盘 DashboardPage」查看服务器概览
   - 右侧：NAS 设备图（静态插图资源，可先用内置 SVG/PNG）
3. **应用宫格**（2 行 5 列，iOS 风格圆角彩色图标 + 单行标签，无副标题）
   - 第一行：文件管理(跳文件Tab) / 资源监控 / 存储管理 / 下载任务 / 套件中心
   - 第二行：控制面板 / Docker / 照片备份 / 安全性 / **更多**
   - 「更多」→ 弹出底部面板（Grid 形式），收纳：SSH 终端、通知设置、记事本、我的应用(自定义 WebView 入口)、Tab 排序、添加/管理自定义页面
   - 若存在「我的应用」（openAsTab=false 的 WebViewEntry），追加显示在宫格第二行之后（第 3 行起），长按弹出编辑/删除菜单（保留现有逻辑）
4. **资源监控卡片**（白色圆角卡片，点击标题 → ResourceMonitorPage）
   - 三个圆环：CPU %、内存（GB + 占比弧）、存储（卷用量 %，颜色遵循现有存储百分比颜色规则）
   - 三个子卡片：网络（↑tx ↓rx）、硬盘（读/写）、温度（CPU/硬盘，DSM 有数据则显示）
   - 数据源：沿用现有 `dashboardData()` 批量接口 + 10s 自动刷新；无权限的模块整块隐藏
5. **底部导航**：维持现有 MainTabPage 机制不变（Tab 排序/隐藏/自定义 WebView Tab 全部保留）

### 2.2 公网/内网判定规则

> 不能用「IP vs 域名」判断：IP 可能是公网 IP，域名也可能解析到内网（DDNS 局域网解析、内网 DNS）。

- 取 **实际连接的 `DsmApi().baseUrl`** 中的 host（QuickConnect 登录后存的也是竞速胜出的真实地址）
- host 是 IP 字面量 → 直接判断；是域名 → 先 `InternetAddress.lookup` DNS 解析拿 IP
- IP 落在私网/保留段 → **内网连接**：`10/8`、`172.16/12`、`192.168/16`、`127/8` 回环、`169.254/16` 链路本地、`100.64/10` CGNAT、IPv6 ULA `fc00::/7`
- 其余 → **公网连接**；解析失败 → 显示「已连接」
- 实现：`lib/utils/network_type.dart` 的 `NetworkTypeUtil.detect(url)`（结果按 baseUrl 缓存，切换服务器时 `reset()`）；原 `ServerModel.isQuickConnect`（按 host 含不含点猜测）已删除

### 2.3 功能保全清单（现有功能 → 新位置）

| 现有功能 | 新位置 |
|----------|--------|
| 通知（NotifyPage） | 顶部铃铛 |
| 控制面板/资源监控/存储/下载/套件/Docker/照片备份/安全性 | 应用宫格 |
| SSH 终端 / 通知设置 / 记事本 | 「更多」面板 |
| 我的应用（WebViewEntry 非 Tab 项 + 长按编辑删除） | 宫格第 3 行 |
| Tab 排序 / 添加自定义页面 / 管理自定义页面 | 「更多」面板 |
| 下拉刷新 / 10s 自动刷新 / 权限降级不报错 | 保留 |

---

## 三、启动流程改版（对照 02_splash.png + qidong1~3 动画）

### 3.1 新增 SplashConnectPage（`/splash`）

**触发条件**：App 启动时本地存在 `sid + host + auto_login`（即"不确定登录是否过期"的场景）。无会话 → 直接进登录页（现状不变）。

**页面内容**（浅蓝渐变背景）：
- 顶部：`正在连接...` 标题
- 中部：NAS 设备插图
- 下部：`账号名  ●●●●●(蓝点流动动画)  设备名`
- 底部：`退出登录` 文字按钮（点击清除会话 → 登录页，兜底逃生口）

**校验逻辑**（复用现有代码，从 login_page `_restoreLastSession` 迁移）：
1. `DsmApi().shareList()` 探活会话
2. 成功 → 权益校验（LicenseManager.refresh）→ 播放拉开动画 → 进 `/`（或 Banned/Paywall）
3. sid 失效 → 用保存的账号密码静默重登（现有 `_doLogin` 逻辑）→ 成功同上；失败 → 跳登录页
4. 超时（如 15s）→ 提示 + 保留退出登录按钮

### 3.2 「中间向上下拉开」转场动画

从 qidong1~3 截图分析：**首页在启动页下层，启动页从中间分裂为上下两半，分别向上/向下滑出**，露出首页（qidong2 中可见首页中部内容先露出来）。

实现方案（无需额外依赖）：
- 校验通过后，对 SplashConnectPage 当前画面 `RepaintBoundary.toImage()` 截图
- push 首页（无转场），首页之上盖一个 Overlay：上半屏图片 + 下半屏图片
- `AnimationController`（450ms，Curves.easeInOutCubic）驱动：上半 `translateY: 0 → -50%屏高`，下半 `translateY: 0 → +50%屏高`，同时轻微 `opacity 1→0.9`
- 结束后移除 Overlay

### 3.3 路由调整

- `main.dart` 保留 `_restoreSession()`（先注入 sid 让拦截器放行）
- 初始路由：有会话 → `/splash`；无会话 → `/login`（由 LoginInterceptor 兜底）
- `LoginInterceptor` 增加放行 `/splash`

---

## 四、侧边抽屉（对照 03_drawer.png）

点首页头像 → 从左滑出 Drawer（宽 78% 屏宽，同渐变背景，右侧首页压暗 25%）。

**结构**：
- 顶部右侧：`⚙ 设置` 胶囊按钮 → PersonalSettingsPage
- 用户块：大头像 + 账号名 + `管理员 · 设备名`（是否管理员取自现有系统信息）
- 卡片组 1：个人设置
- 卡片组 2：我的权益 / 仪表盘 / 公告 / 意见反馈 / 关于
- 卡片组 3：切换账号（→ AccountsPage，登录成功替换会话）/ 退出登录（红字，复用现有 `_logout` 确认流程）

**与"我的"Tab 的关系**：本期「我的」Tab 保留不动（深色模式开关、清理缓存、调试入口 5 连击仍在那里），抽屉是快捷入口层。后续可评估是否合并砍掉「我的」Tab。

**实现**：MainTabPage 的 Scaffold 挂 `drawer:`，HomePage 头像点击 `Scaffold.of(context).openDrawer()`；抽屉仅在首页 Tab 可用。

---

## 五、通用 Section 组件（对照 04_control_panel.png）

### 5.1 新组件 `AppSectionGrid`（`lib/components/app_section.dart`）

```
AppSectionGrid(
  title: '文件共享',                 // 上：分组标题（小号灰字）
  items: [
    AppSectionItem(icon, iconColor, label, onTap),  // 无副标题
  ],
  columns: 4,                        // 默认 4 列
)
```

- 视觉：标题 14sp 灰色，下方白色圆角(16)卡片，内部 N 列图标宫格
- 图标：46dp 圆角(12)浅色底（`iconColor` 8% 透明度）+ 彩色图标，标签 12.5sp 单行
- 深色模式：卡片 `surfaceContainerHigh`，图标底色 15% 透明度

### 5.2 控制面板改版

顶部保留 AppBar「控制面板」+ 新增「搜索全部」输入框（本地过滤所有入口项）。分组改用 `AppSectionGrid`：

| 分组 | 入口（全部保留现有跳转） |
|------|--------------------------|
| 文件共享 | 共享文件夹、用户与群组 |
| 连接性 | 网络、连接用户、外部访问、终端机 |
| 系统 | 信息中心、安全性*、通知设置* |
| 服务 | 任务计划、套件中心* |

\* 安全性/通知设置/套件中心为新聚合入口（复用现有页面），与首页宫格重复入口保留——两处都是导航，不冲突。

### 5.3 首页宫格复用

首页应用宫格与「更多」面板同样基于 `AppSectionItem` 数据模型渲染（首页版无分组标题、透明背景、5 列），保证两处样式统一。

---

## 六、全局搜索（对照 05_search.png）— 调研结论 + 设计

### 6.1 可行性调研（已验证）

- `dsm_api.dart` 已有 `searchTask(paths, pattern)` / `searchResult(taskId)`，对应 `SYNO.FileStation.Search`（异步任务式：start → 轮询 list → 需要时 stop/clean）
- 搜索范围：需要共享文件夹列表作为 `folder_path`，可用现有 `shareList()` 取全部共享文件夹递归搜索
- 结果含 `real_path / size / time / type`，图片缩略图可复用文件 Tab 现有缩略图加载方式
- **结论：无需新增后端能力，纯客户端即可实现**

### 6.2 SearchPage 设计（`/search`）

- 入口：首页搜索框（Hero 动画过渡到搜索页输入框）
- 顶部：输入框（自动聚焦、清空按钮）+ `取消`
- 交互：输入后 500ms 防抖发起 searchTask，轮询 searchResult（800ms 间隔，finished 为止）；新输入取消旧任务
- 结果区（白色圆角面板）：
  - `N 个搜索结果` 徽标
  - 工具行：`按文件名 ↑`（可切换 名称/大小/修改时间，升降序）+ 视图切换（列表/网格）+ 多选
  - 列表项：缩略图(52dp) + 文件名（关键词命中部分高亮主题蓝）+ `位置：路径`（超长省略）+ `⋯` 更多菜单（复用文件 Tab 现有操作：下载/分享/收藏/删除等）
  - 点击：图片 → 预览；视频 → 播放器；文件夹 → 跳文件 Tab 对应路径；其他 → 现有打开逻辑
- 空态/搜索中态：居中提示 + 骨架屏（复用 skeletonizer）
- 本期范围：仅文件名搜索；套件中心搜索保持现状（后续可把套件、应用入口聚合进全局搜索）

---

## 七、实施计划（建议分 4 批落地，每批可独立验证）

| 批次 | 内容 | 涉及文件 |
|------|------|----------|
| 1 | `AppSectionGrid` 组件 + 控制面板改版 | `components/app_section.dart`(新)、`control_panel_page.dart` |
| 2 | 首页改版（头部/连接状态/宫格/资源卡片/更多面板） | `home_page.dart`、`server_model.dart`、`app.dart`(渐变) |
| 3 | 侧边抽屉 + 头像入口 | `main_tab_page.dart`、`components/home_drawer.dart`(新) |
| 4 | 启动连接页 + 拉开动画 + 路由调整；全局搜索页 | `pages/login/splash_connect_page.dart`(新)、`pages/common/search_page.dart`(新)、`routes.dart`、`main.dart` |

**风险点**：
- 首页改为沉浸式头部后需处理状态栏图标深浅（渐变背景下浅色模式用深色图标）
- 拉开动画依赖 RepaintBoundary 截图，注意在低端机上的耗时（可降级为淡出）
- FileStation.Search 在大目录递归时较慢，必须做任务取消与超时（避免任务堆积在 NAS 上，结束时调 stop）
