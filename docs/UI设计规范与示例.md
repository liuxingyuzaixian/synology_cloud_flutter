# NasFlow UI 设计规范与示例

> **沉淀来源**：26.11.01 你点头的四组页面——**文件 tab**、**首页**、**运行状态（6 个分类）**、**传输任务页**。
> 这四组是「参考了飞牛、晖云，再逐条改到你验收」的最终形态，所以后面新页面**先抄这里，再谈创新**。
> 文档里每条都带 `文件:行号`。行号是 v0.0.263 工作区（HEAD `3d58c15` 之后的未提交状态）的快照，
> 代码一改行号就会漂；**值不会漂**——对不上就按符号名搜（`_HomeCard`、`_cardHead`、`FnDropdownPicker`）。

---

## 0. 怎么用这份文档

| 你在做什么 | 先看 |
| --- | --- |
| 定尺寸、字号、圆角 | §1 单位法则 + §1.4 阶梯表 |
| 取颜色（含深色） | §2 FnTokens，**禁止写字面量色值** |
| 加一张卡片 / 一个列表 / 一张图 | §3 找最像的那页，整段抄它的配方 |
| 加下拉、徽标、分段器、圆环、弹层 | §4 组件表，**已有唯一入口，不许重复实现** |
| 决定「刷新放哪」「读不到怎么显示」 | §5 交互与信息规则 |
| 想省事走捷径 | §6 反例清单，全是为它返工过的 |

规则分两档：**必须**（违反会被打回，因为已经为它返工过）／**默认**（可以为具体页面偏离，但要在注释里写清为什么）。

---

## 1. 尺寸单位法则

### 1.1 三套单位，各有地盘

`lib/utils/app_adaptive.dart` 是唯一裁决处：

- `designSize = Size(375, 812)`（:6），`maxAdaptWidth = 600`（:12）。
- `.aw`（:45）与 `.asp`（:50）都走同一个 `_clampedScale`（:35-41）：**逻辑宽超过 600dp 就不再放大**。
  这条是 Pad / 横屏不「被横向拉满、图标间距过大」的根因，所以 `.w`/`.sp` 在新代码里基本别用。
- `.wp`/`.hp`（:22-24）是百分比屏宽屏高，只在「按屏幕比例给宽度」时用（曲线、卡片最大宽）。
- 间距现成件：`12.hGap`、`8.wGap`、`6.aGap`（:15-19）。`wGap` 已经用 `.aw`，别自己 `SizedBox(width: 8.aw)` 混着写。
- 挂载点：`lib/app.dart:44-47` `ScreenUtilInit(designSize: AppAdaptive.designSize, minTextAdapt: true, splitScreenMode: true)`。

### 1.2 必须：固定尺寸的「壳」一律裸逻辑像素

顶栏、底栏、锁屏、toast、滚动条、悬浮胶囊这些**不随屏幕宽高变化**的区域用裸 px：

```dart
// lib/pages/home/home_page.dart:595-599（注释就是理由）
// 顶栏全部用固定逻辑像素：横屏 pad 上 .aw/.asp 会把头像撑大、字号反而变大。
Widget _buildHeader(ThemeData theme, FnTokens t) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 14, 12),   // 没有 .aw
    child: Row(children: [ ... NasAvatar(size: 44), ... ] // 44 也是裸值
```

同样口径：`FnBottomBar`（`lib/components/fn_bottom_bar.dart:11` 「底栏属固定尺寸区域，全部使用固定逻辑像素」，图标 28 / 文字 11 / 间距 2 全裸值 :100-112）、`CustomScrollBar`（`_thumbW = 26.5`、`_thumbH = 44` :62-63）、`AppDialog.toast`（`app_dialog.dart:43-46` padding 20/12、radius 12、`fontSize: 14` 全 const）、`FnPill`（`fn_pill.dart:35/42` padding 11/5、radius 13 裸值）。

**判据一句话**：这块东西换手机/换 Pad/转横屏，**应该长得一样大**吗？是 → 裸 px；否（正文、卡片、列表行）→ `.aw`/`.asp`。

### 1.3 卡片与列表：`.aw` 管横向、`.h` 管纵向

定稿卡片（首页 `_HomeCard`，`home_page.dart:2091`）：

```dart
padding: EdgeInsets.fromLTRB(13.aw, 12.h, 12.aw, 14.h),
borderRadius: BorderRadius.circular(22.r),
```

运行状态页的卡（`resource_monitor_page.dart:867`）用同一份意思、略松一档：`margin bottom 12.aw`、`padding 16.aw`、`radius 16.r`。
**同一页内保持一套，跨页不强求相等**——首页 22.r 是设计图 ① 定的，监控页 16.r 是它自己那套的定稿。

### 1.4 实测阶梯表（抄这个，别再随手取数）

字号（`.asp`，除标注裸 px 的）：

| 用途 | 值 | 出处 |
| --- | --- | --- |
| 文件 tab 根目录标题 | 26.asp / w700 | `files_page.dart:426` |
| 子目录名 / Tab 入口标题 | 20.asp w600 · 15.asp w600 | `files_page.dart:427`、`transfer_page.dart:776` |
| 用户名 / 卡片标题 / 弹层标题 | 17 **裸 px** w600 · 16.asp · 17 **裸 px** | `home_page.dart:685`、`home_page.dart:2132`、`app_dialog.dart:241` |
| Tab 标签 / 分组标题 / 空态 | 15.asp · 15.asp · 15.asp | `transfer_page.dart:173`、`_sectionHead :400`、`transfer_page.dart:313` |
| 列表主行 / 文件名列 | 14.asp w500 | `files_page.dart:1029`、`transfer_page.dart:481` |
| 键值行的值 / 读数 | 12.5 w600 | `home_page.dart:2158` `_KvRow`、`resource_monitor_page.dart:928` `_reading` |
| 次级小字、字段名、宫格标签 | 11.5 | `home_page.dart:2183`（`_KvRow` label）、`:1933`（`_ItemRow` 副标题）、`fn_ranking_card.dart:199` |
| 列表副标题、底栏文字、pill | 11 | `files_page.dart:1040`、`fn_bottom_bar.dart:111`、`fn_stat_trio.dart:83` |
| 单位、辅助说明 | 10.5 | `fn_ranking_card.dart:109`、`resource_monitor_page.dart:948` `_legend` |
| 曲线左刻度（图内，裸 px） | 9.5 | `fn_spark_chart.dart:133` |

字重：`w700` 只给文件 tab 根目录一处；标题与数值 `w600`；列表主行、pill、分段 `w500`；其余常规。

圆角：`22.r` 首页卡 / `20` 底部面板顶角（`app_dialog.dart:231`、`transfer_page.dart:329`）/ `16-18.r` 卡与弹层 / `17.r` 宫格图块 / `12-14.r` 小控件 / `8-9.r` 徽标 / `2.r` 细进度条 / `13` 全圆 pill / `20` 分段器外壳、`16` 选中滑块。

间距：`4 / 7 / 8 / 12 / 14 / 16 / 20`。**不要出现 10、13、15 这种「差不多」**——首页卡右 12.aw、宫格 tile 间距 14.h、`_HomeCard` 标题短条后 7，都是逐条量过的。

---

## 2. 颜色：只从 `FnTokens` 取

`lib/core/fn_tokens.dart` 是首页改版后**唯一**的语义色定义处，取值一一对应设计稿 `docs/ui_redesign/home_v3_mockup.html` 的 `:root{}`（浅色）与 `.dark{}`（深色）。

| token | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| `pageTop` / `pageBottom` | `D4E0F2` / `F4F5F7` | `1B2532` / `0E1116` | 页面渐变两档 |
| `card` | `FFFFFF` | `1A1E26` | 卡片底 |
| `inner` | `F7F9FC` | `141821` | 卡内小方块（statbox / item / bar） |
| `line` | `EDF0F5` | `252A34` | 分隔线；**深色兼作 1px 描边** |
| `ink` / `ink2` / `label` | `1B1D21` / `767E89` / `98A0AC` | `EDF1F7` / `8B95A4` / `8B95A4` | 正文 / 次要 / 字段名灰 |
| `blue` / `blueSoft` | `3E8BFF` / `EAF2FF` | `4C93FF` / `18263E` | 主色（读方向、图标、交互） |
| `green` / `greenSoft` | `2FC173` / `E7F7EE` | `3CCF81` / `15281F` | 正常 / 写方向 / 健康 |
| `red` / `amber` / `purple` | `F5483B` / `F5A623` / `8B5CF6` | `FF6B61` / `FFB84D` / `A78BFA` | 报警 / 警示 / 进程类 |

派生 token（这些是「后补深色最容易漏」的那几处，全部现成）：`iconTileBorder`、`iconBtnBg`、`badgeBorder`、`chartGrid`、`axisText`、`thresholdText`、`pillMuteBg`、`pillMuteText`、`itemSub`、`barTrack`、`ringTrack`。

三条必须：

1. **取亮暗跟 `Theme.brightness`，不用 `platformBrightness`**（`fn_tokens.dart` 里 `FnTokens.of()` 的注释）。App 能强制深色，用 platform 会让色板和文字色打架。
2. **深色不是换底色**。语义色整体提亮一档（蓝 `3E8BFF→4C93FF`、绿 `2FC173→3CCF81`），底色分三档（页面 / 卡片 / 卡内），阴影改成 1px 内描边：
   ```dart
   // home_page.dart:2103-2112
   border: t.isDark ? Border.all(color: t.line, width: 1) : null,
   boxShadow: t.isDark ? null : [BoxShadow(
       color: const Color(0xFF1C2846).withValues(alpha: 0.055),
       blurRadius: 18, offset: const Offset(0, 6))],
   ```
3. **用量色阈值只有一套**：`p > 0.9` 红、`p > 0.8` 琥珀、否则绿，`null` → `t.label`（`home_page.dart:1993-1994`，存储页/仪表盘同一套阈值）。绿色是「健康」语义，蓝留给交互色。

> 已知欠账：文件 tab 与传输页还有 `Colors.grey.shade100/300/500`、`0xFF1E1E1E`、`0xFF121212` 这类字面量（例：`transfer_page.dart:266/308`、`files_page.dart` 分割线）。§7-1 把它列为下一步收敛项。

---

## 3. 四组定稿页的配方

### 3.1 首页（`lib/pages/home/home_page.dart`）

骨架：**没有 AppBar**，整页是「渐变底 + SafeArea(下不缩进) + 顶栏 + 一个可下拉的 ListView」。

```dart
// :563-583
Scaffold(body: Container(
  decoration: BoxDecoration(gradient: LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    stops: const [0, 0.42], colors: [t.pageTop, t.pageBottom]))),   // 中段就到底色，后面不再渐变
  child: SafeArea(bottom: false, child: Column(children: [
    _buildHeader(theme, t), Expanded(child: _buildBody(theme))]))));
```

正文（`:748-762`）：`AppRefresh` 包 `ListView(padding: EdgeInsets.symmetric(horizontal: 16.aw))`，卡与卡之间用 `12.hGap / 14.hGap / 16.hGap` 呼吸。列表尾部留白 = `16.h + FnOverlayMetrics.contentInsetOf(context)`，给悬浮底栏让位。

卡片底座 `_HomeCard`（`:2056`）——**新加一张首页卡就复用它，不要手搓**：

- 标题行：4×15 `t.blue` 短条（radius 2，`:2113-2119`）→ 7px 缝 → 标题 16.asp w600 `t.ink`（单行 ellipsis）→ 可选 `liveDot`（7×7 绿点）→ 可选 `trailing` → `showChevron` 时 `Icon(chevron_right, 18, t.label)`。
- `childGap` 默认 0 是**有意**的（:2080-2085 注释）：速率卡子节点自带 `top: 12.h`，双卡 `_KvRow` 首行只有 `7.h`，统一给一份必然一边翻倍、一边还挤。**谁需要谁显式传，底座别猜。**
- 键值行 `_KvRow`（`:2158`）：竖 7.h、`Border(bottom: t.line)`、左 label 11.5.asp `t.label`、右 `Expanded` + 右对齐 12.5.asp w600。
- 卡内小方块 `_StatBox`（`:2250`）：`t.inner` + radius 14.r。
- 速率格 `_RateTile`（`:2286`）：padding `LTRB(12.aw, 9.h, 12.aw, 11.h)`、radius 16.r、5×5 圆点 + 11.5.asp 标签 + 18.asp w600 数值。
- 条目行 `_ItemRow`（`:1882`）：容器 padding 对称 `13/11`（**裸 px**）、`t.inner` + radius 16（裸值）+ 深色 1px `t.line` 描边、标题 13.5.asp w600、副标题 11.5.asp `t.itemSub`、细进度条 **64×4（裸值）、radius 2、轨道 `t.barTrack`**、右侧 tag padding `9/5` radius 9、11.asp w500 白字。
- 存储池 tile `_PoolTile`（`:1975`）：环 **78×78、strokeWidth 8、strokeCap round、轨道 `t.ringTrack`**；`percent == null` 时**只画轨道、中间标「—」**（:2021-2029，「那是编出来的读数」）。
- 一排 ≤2 个用 `EqualHeightRow(spacing: 12)`，超过 2 个改成 `SizedBox(height: 132)` 的横向 `ListView`（tile 宽 118）——**别用 `Row` + `Expanded` 硬塞**，第 5 项会挤扁（这条是 #64「首页大片空白」的根因）。

宫格（`:942` `_buildAppGrid`）：

- 数据源只有 `AppCatalog`（`lib/core/app_catalog.dart` 是**唯一**数据源，id/label/icon/color 只在这里改）。
- 顺序 `homeGridOrder` 首位是 `control`（控制面板，26.11.01 第七批反馈第 6 条）；**已在底栏 Tab 上的应用去重**（`_isInTabBar`），第 8 格固定是「应用管理」。
- 排版走 `AppSectionGrid(tile: true, coloredIcons: true, titleInside: true)`：**卡片/标题行/圆角/间距仍是首页那套 tile 档**（浅蓝底板关掉、图标改彩色大图标 40.aw、46.aw 块、与应用管理页逐项一致）。
- 「更多」不再叫更多；标题叫「全部应用」，标题进白卡内（`titleInside`）。
- 标题行右侧只留「添加」一个入口，用 padding 撑点击区而**不是 `IconButton`**（默认 48 高会把标题行顶高、宫格整体下移，`:999` 注释）。

顶栏右侧顺序：**传输（倒数第二）→ 消息（最后）**，这个顺序你 26.10.31 明确过不要动；传输按钮沿用 `TransferSyncIcon` 并关掉自带细圈（`circle: false`），避免与按钮底圈叠成两圈。

### 3.2 运行状态（`lib/pages/home/resource_monitor_page.dart`，「那 6 个页面」）

**6 个分类在同一个 Scaffold 里切 `_cat`**（`enum ResMonCategory` :27：overview/cpu/memory/network/disk/process），不是 6 条路由。这样 §「去刷新按钮」只删一次六页都干净。

这页头部（`:86-110`）写着六条改动规则，**它们同时是全站规范**：

1. 轮询写死最高档（这页定位就是「实时」，图上要看得出波动）。
2. 进页面不转圈：首页批量请求已经取到 `SYNO.Core.System.Utilization`，用 `seedUtilization/seedNetwork/seedDisk` 当种子，点进来就是满的曲线。
3. 每个分类都有图；概览是四张带图的卡，点卡进子页看大图与明细。
4. 每个能排的维度都有排行卡 + 进程页排得动；**网络那一维做不出来就明说为什么没有榜，不编假榜**。
5. **AppBar 右上角不放刷新按钮**（`actions: const []` :1430，注释 :2167）——已有下拉刷新（`AppRefresh`）+ 1 秒档轮询两条路，按钮是第三条重复入口。
6. **换整屏内容就回到最上面**：一个 Scaffold 里换 `_cat`，`ScrollPosition` 不会自己归零，所以换分类/换段都换正文 `ListView` 的 key（`_listKey`）。

零件（新页面照抄）：

- `_card` :867（`margin bottom 12.aw`、`padding 16.aw`、`radius 16.r`、深色 1px `t.line` 描边；**有 `onTap` 就整卡包 `InkWell(borderRadius: radius)`**）。
- `_cardHead` :893（标题 14.asp w600 + 右侧读数 `Expanded > Wrap(alignment: end, spacing: 10, runSpacing: 2)`）。**:910 那行是关键**：`if (rights.isEmpty) Flexible(child: titleWidget) else titleWidget`——标题**只在右边没读数时**才允许收缩；有读数时标题占自然宽度，否则对半分会把读数挤到换行。长标题卡（进程列表 + 排序按钮）反过来让标题可 `clip`。
- `_goChevron` :942：`chevron_right_rounded` 18 `t.ink2`——**箭头只是提示，不吃 onTap，整卡是 `InkWell`**（热区只有一个）。
- `_reading` :928（12.5/11.asp w600）、`_legend` :948（7×7 圆点 + 10.5.asp）。
- `_kvRow` :983：`Expanded` 分栏，**上标签 10.5.asp、下数值 12.5.asp w500，左对齐**。
  注意这和首页 `_KvRow`（左标签右数值、单行）是**两种模式**：多列并排读数值用这页那种，字段名+单值用首页那种。选一个，别混。
- `_processRow` :1132：状态点 8.aw（R/S/D/Z 各有色）、名 13.asp w500、明细 `' · '` 11.asp、pill padding `8.aw/3.aw` + `t.pillMuteBg` radius 8.r 11.asp。
- 更多按钮 `_procMoreButton` :1228：`more_horiz` 20.r `grey.shade500` + **`padding: EdgeInsets.zero, constraints: const BoxConstraints()`**（:1249-1250，默认 48 点击区会把行高顶起来）；被拦住不能用时同一位置换 `error_outline_rounded` + `t.amber`，并把原因写进 `tooltip`。
- 筛选行 `_processListCard` :1828 头部**用 `Wrap(spacing: 8.aw, runSpacing: 6.aw, alignment: spaceBetween)` 而不是 `Row + Spacer`**（:1838-1841）；分段用 `FnSegmented`、下拉用 `FnDropdownPicker`。
- 关键词框 `_kwField` :1906：`SizedBox(height: 34)`（裸逻辑）+ `t.inner` + radius 10.r；controller 必须挂 State（:177 注释）。
- 空态 `_emptyFilterText` :1947 **区分「被筛没了」与「本来没数据」**。
- 取数失败但已有数据 → `_staleBanner` :2119（`t.amber@0.12`、radius 12.r、info 图标 15、文案「刷新失败：xxx（下面显示的是上一次成功取到的数据）」）。
- 全失败 → `_errorView` :2138：先 `NoPermissionWidget.isPermissionErrorText` 判权限，否则 `error_outline` 48.aw `t.red`。
- 顶栏切分类 `_categorySelector` :2097 用 `FnDropdownSize.title`。

### 3.3 文件 tab（`lib/pages/files/files_page.dart`）

- `PopScope` + **`KeyboardInsetScaler`（:329）** + `Scaffold(backgroundColor: isDark ? 0xFF121212 : 0xF4F5F7)`，**无 AppBar**：页头是自绘大标题行。
- 页头 padding `LTRB(16.aw, 10.h, 16.aw, 8.h)`；根目录 26.asp w700，子目录 20.asp w600 + `'(N项)'` 13.asp（:426 一带）。
- 页头按钮统一 `_headBtn`（:478-494）：`Tooltip + GestureDetector(opaque) + Padding(水平 7 / 垂直 4 裸 px)`——**无圆圈底、细线大图标**。要圆圈底（首页那种）才用 `IconCircleButton`。
- 排序 chip：文字 14.asp w500 在前、箭头 16.r 后置，竖 padding 6.h。
- 菜单弹层：radius 14.r，`_menuColor` 深色 `0xFF2A2A2A`/浅色 white，行高 46.h，选中项徽标 padding `8.aw/3.h` + 主色 `@0.10` radius 8.r。
- 底部面板：`borderRadius: vertical(top: 20.r)`，深色 `0xFF1E1E1E`。
- 列表：`SlidableAutoCloseBehavior > CustomScrollBar > ListView.builder`（:944-945）；行 padding 横 16.aw 竖 10.h、分割线 `grey.shade100` 0.5、图标 36、名 14.asp w500、副标题 11.asp、尾部 `more_horiz` 20.r（零 padding）。
- 手势：**长按 = 多选**、双击 = 特殊入口、侧滑 = `Slidable` `DrawerMotion` 快捷操作。
- 加载中返回 `SizedBox.shrink()`（`_buildBody` :884-887）：**已有缓存就不再转圈**，转圈只出现在真空窗。

### 3.4 传输任务页（`lib/pages/transfer/transfer_page.dart`）

- `TabBar`（:170）标签 15.asp（选中 w600，:172-174）；三个 tab = 下载 / 上传 / 其它（`_buildTaskTab` ×2 + `_buildOtherTab`，:186-194）。
- 白面板 `Container(margin LTRB(12.aw, 8.h, 12.aw, 0), padding LTRB(16.aw, 6.h, 16.aw, 0), radius vertical top 20.r)`（:324-330）。
- **底部固定条两种内容共用同一份几何**：速度条 `_buildSpeedBar`（:253-271）与多选操作栏 `_buildSelectActionBar`（:206-218）都是 `padding LTRB(16.aw, 10.h, 16.aw, padding.bottom/2 + 10.h)` + 顶部 0.5 分割线（深色 `white12`／浅色 `0xFFEDEFF2`）、底 `0xFF1E1E1E`／white——**进多选时列表不跳一下**。
- 速度条内容（:273-286）：居中一行——下载 `arrow_downward` 14.r 主色蓝 + `${formatSize(down)}B/s` 12.asp hintColor，`20.wGap`，上传同理着 `green`；数值只汇总 **running** 状态的任务（:256-261），静止时照常显示 `0B/s`（`formatSize(0) → '0'`，`lib/network/dsm_api.dart:3453`）而不是把整条隐藏——**底栏高度恒定**。
- 任务行 `_activeRow`：缩略底板 `_thumb`（:431-441）**44.aw 见方、radius 10.r、主色 `@0.08`、图标 22.r 主色**；名 14.asp w500（:481）；进度 = `LinearProgressIndicator(minHeight: 4.h)` 外套 `ClipRRect(borderRadius: 2.r)`（:484-491，**细条必须圆角**，轨道 `EDEFF2`／深色 `white12`）；下方左右小字 11.asp `theme.hintColor`（:497-500）。
- 功能入口卡 `_entryCard`（:745-790）：padding `16.r`、radius `16.r`、底 `0xFF1E1E1E`／white，图标底板 44.aw + radius 12.r + 主色蓝 `@0.1` + 图标 22.r，标题 15.asp w600、副标题 12.asp hintColor、右侧 `chevron_right` hintColor。
- 分区标题 `_sectionHead`（:400）15.asp w600，右侧动作（全部暂停/取消全部）。
- 空态：图标 `64.r grey.shade300` + 文案 15.asp「暂无下载任务 / 暂无上传任务」（:298-318）。

---

## 4. 共享组件清单（唯一入口，禁止重复实现）

| 要做的事 | 用这个 | 关键几何（file:line） |
| --- | --- | --- |
| 下拉刷新 | `AppRefresh` | `triggerOffset: 70`（`app_refresh.dart:29`），ClassicHeader 图标 22、文字 13/12（:75-77） |
| 横向拖拽滚动条 | `CustomScrollBar` | 药丸 26.5×44、实心三角、间距 4、`crossAxisMargin 12`、`thumbColor 0x61000000`、1.5s 淡出（`CustomScrollBar.dart:18/19/62-63/85`） |
| 页面返回键 | `PageBackButton` | `arrow_back_ios_new` 20.r，padding right 8.aw（`page_back_button.dart:22-23`）；**不许各页自拼 `IconButton`**（48×48 会漂） |
| 底部 Tab | `FnBottomBar` | 图标 28 + 文字 11 + 间距 2，全裸 px，高 `FnGlass.navHeight`；**选中格套淡蓝胶囊底**：块 = 整格内缩 `navChipInset=5`（四周同一个值），圆角 `navChipRadius = navRadius − inset = 23`（与外框同心），`fn_bottom_bar.dart` `_TabCell`；26.11.09 第 13 批改掉「贴内容尺寸 + padding 4/12 + r14」那版（上下空 2.5、左右空 9.8~18.75，看着边距特别大）；主底栏与相册页底栏同组件，`main_tab_page` 不再传颜色 |
| 玻璃底栏/悬浮胶囊 | `FnGlass` / `FnGlassPill` | nav 56 / **radius 28（= 高度一半的正胶囊）** / 下留白 8 / 边距 16 / **blur 34 + saturate 1.5** / 填充 白@0.46、#1B1B20@0.52 / 阴影 `0 8px 24px 20,30,60@0.14` / 文字 `navInactive` #333A42（深 #C9CED6）、`navActive` #3E8BFF（深 #7FB4FF）；操作 pill 高 44、dock 48、radius 22、边距 12、gap 8、blur 19；chip 高 30（`fn_glass.dart:17-124`） |
| 分段切换 | `FnSegmented` | 外壳 padding 3 radius 20（深 0xFFE7EAF0／浅 `t.inner`），滑块 padding `14/5` radius 16、160ms、**选中蓝字 w600 + 阴影 `1C2846@0.08`（深色不出阴影）**、未选 `t.ink2` w500，文字 13.asp（`fn_segmented.dart:40-82`） |
| 下拉选择（全站唯一） | `FnDropdownPicker` | `PopupMenuPosition.under` 贴下沿展开（`fn_dropdown_picker.dart:66`）；`FnDropdownSize.title` = 图标 15 + 文字 15.asp，pill 档 = 13 + 11.5.asp；菜单行 padding `12.aw`、勾 `check_rounded` 16 主色蓝 |
| 小徽标 / 计数 pill | `FnPill` | padding `11/5`、radius 13、12.asp w500；三档 mute / red / 默认蓝（`fn_pill.dart:35-46`） |
| 占用圆环 | `FnUsageRing` | 默认 size 104、strokeWidth 9、数值 22.asp、单位 10.5.asp、轨道 `t.ringTrack`；**`percent == null` 显示「—」不显示 0%**（`fn_usage_ring.dart:22-25/61/83`） |
| 三联读数 | `FnStatTrio` | padding `14.h/12.aw`、竖分隔线、值 22.asp、标签 11.asp（`fn_stat_trio.dart:48-84`） |
| 占用排行卡 | `FnRankingCard` / `FnRankRow` | 卡 padding `16.aw`、标题 14.asp、跳转动作区 padding 4 + 箭头 18；行竖 `5.aw`、名 12.5.asp、副 11.5.asp `t.itemSub`；**fraction 由调用方按榜首算**（`fn_ranking_card.dart:79-199`） |
| 曲线 / 柱状 | `FnSparkChart` / `FnBarChart` | 默认高 118、左侧 46 裸 px 刻度栏（最大/一半/0 三档）、虚线网格 `t.chartGrid`、刻度字 9.5 `t.axisText`、阈值线 `t.red` + 阈值字 `t.thresholdText`；**量程只由数据决定（历史最大值留 15% 顶边余量），阈值超出量程时不画线、只在右上角标一行文字**（`fn_spark_chart.dart:10-14/83/88`） |
| 宫格分组 | `AppSectionGrid` | 见 §3.1；`tile` / `coloredIcons` / `titleInside` / `plain` 四档开关（`app_section.dart`） |
| toast / loading / 确认 | `AppDialog` | toast：根 Overlay、`Alignment(0,-0.15)`、maxWidth 72%、padding 20/12、radius 12、黑 `@0.8`、14/height 1.4、180ms 淡入 + 0.92→1 缩放、2s 消失（`app_dialog.dart:24-72`）；loading：`DialogRoute` + `PopScope(canPop:false)`、宽 132、radius 8、圈 28 strokeWidth 2.6（:84-121，**用显式 route 才关得掉**）；`confirm` / `dangerConfirm` / `actionSheet`：全宽按钮高 50 radius 14、标题 17 w600、正文 15 height 1.5、蓝底 `@0.10`（深 `@0.22`）、危险红底 `@0.08`（深 `@0.18`）、取消灰底（:178-281） |
| 头像（本机→NAS 三级兜底） | `NasAvatar` / `AvatarSheet` / `LocalAvatar` / `NasAvatarPhoto` | `NasAvatar(size: 44)`（首页顶栏），`AvatarSheet` 内 76（`avatar_sheet.dart`）；读不到回退本机、再回退首字母 |
| 细线双向箭头图标 | `TransferSyncIcon` | size 26、笔形 `strokeWidth: 1.7`、650/420ms 双动画（`transfer_sync_icon.dart:120/27/30`） |
| 一行等高双卡 | `EqualHeightRow` | `IntrinsicHeight + Row(stretch)`，`spacing` 自己传 |
| 无权限态 | `NoPermissionWidget` | `isPermissionErrorText` 先把错误文案归类（见 `resource_monitor_page.dart:_errorView`） |

---

## 5. 交互与信息规则（这些比像素更容易被忽略）

1. **刷新只有一个入口：手动下拉。** 页头右上角不放刷新按钮；有轮询的页面就是「下拉 + 轮询」两条路（§3.2 规则 ⑤，`resource_monitor_page.dart:1430`）。同理：同屏出现两个通往同一页的入口（宫格「更多」+ 标题行「管理」）算设计缺陷，26.11.01 就是这么砍掉「管理」的。
2. **热区只有一个。** 整卡 `InkWell`/`GestureDetector(behavior: opaque)`，箭头只是视觉提示不吃 tap（`_goChevron` :942，注释 :934-941 写得很清楚：**「同一页里两颗『可以点进去』的箭头必须长得一样，否则用户会以为其中一颗是装饰」**——所以它和 `FnRankingCard` 标题右侧共用同一枚 `chevron_right_rounded` / 18 逻辑像素 / `t.ink2`）；徽标必须相对**图标块**定位，不能相对 GridView 单元边缘（四列里会飘到角落）。
3. **内容变了就回顶部。** 同一 Scaffold 内换整屏内容必须换 `ListView` 的 key 或显式 `animateTo(0)`（§3.2 规则 ⑥；#109「跳转后不在最上面」就是这么修的）。
4. **读不到就说读不到。** `null` → 「—」，不印 0%、不编假榜、不给没实测过的接口字段画开关。两条现成的狠例子：磁盘排行数据还没取到时**不画一张全 0 的榜**——「全 0 会被读成『所有进程都没在读写磁盘』，而真实情况是『我们还没查』」（`resource_monitor_page.dart:1110-1111`）；某一维做不出来、或者少了一张卡，就**用一张说明卡写在界面上**，「不要只在代码注释里解释——用户看不到注释，只会看到少了一张卡」（`_noteCard` :1055-1057）。文件行同理：文件夹没有大小，就**不显示「--」占位**，只展示时间，时间也没有就不占行（`files_page.dart:1032-1034`）。整块没数据的明细卡**不占位**，避免一屏空白卡（`_detailCard` :1011）。写操作只发「真改过、且 get 时给过的键」（`lib/pages/home/edit_user_page.dart` 的 `buildChanges` + `test/edit_user_form_test.dart` 钉住）。
5. **空态要分两种**：被筛选条件筛没了 vs 本来就没数据（`_emptyFilterText` :1947）。
6. **抗系统大字号**：可换行的操作区用 `Wrap(spacing, runSpacing)`，不用 `Row + Spacer`；所有标题 `maxLines: 1 + ellipsis`；文字放 `Expanded` 里。
7. **固定高度的控件别用缩放单位**（§1.2），也别用 `IconButton`/默认 48 点击区去顶高行（宫格标题行、进程行「更多」都是这么处理的）。
8. **点击区用 padding 撑，不用大组件包**。
9. **高危操作二次确认走 `AppDialog.dangerConfirm`**（红档），杀进程/删除/重启类必须确认。
10. **图标只有一处定义**：应用图标/颜色/名称只改 `AppCatalog`；首页、应用管理、Tab 三处同源，「看着一致」不算验收，测试里是逐项比 `size`/`color`/底板（`test/home_p1_test.dart`）。
11. **文案不承诺没做的东西**：面向用户的说明里不写第三方竞品名；未验证的能力要说「先存本机，NAS 端按接口尝试同步」（`avatar_sheet.dart` 的 `_nasLine` 三档诚实状态）。
12. **页面背景**：首页是渐变（§3.1），监控页 `Scaffold(backgroundColor: t.pageBottom)`，文件 tab 用 `0xF4F5F7`/`0xFF121212`——**新页选「纯色 pageBottom」那一档**，渐变是首页专属。

---

## 6. 反例清单（都为它返工过，别再犯）

| 别做 | 为什么 / 正解 |
| --- | --- |
| `RefreshIndicator` | 早被 `AppRefresh` 取代（触发距离、颜色、文案统一管理） |
| 页头右上角刷新按钮 | §5-1 |
| 卡片底色在浅色分支写死 | 「卡片颜色一旦写死，后补深色必然漏」（`fn_tokens.dart` 文件头的原话） |
| `platformBrightness` 判深浅 | App 可强制深色，跟 `Theme.brightness`（`FnTokens.of`） |
| `Row + Spacer` 放可能换行的按钮 | 系统大字号溢出，用 `Wrap(spaceBetween)`：「Row 会直接顶出溢出红条，Wrap 是换成两行——**宁可不齐也不破版**」（`resource_monitor_page.dart:1838-1841`） |
| `Row + Expanded` 硬塞 3+ 个存储 tile | 挤扁/崩布局，>2 改横向 `ListView`（#64） |
| 给 `LinearProgressIndicator` 不加 `ClipRRect` | 定稿是 2.r 圆角（`transfer_page.dart:484`） |
| 实心填充图标被顺手改成描边 | 「参考组件必须逐项对齐真实配置」，笔形（stroke 1.7）本身也是对齐项 |
| 首页宫格用浅蓝底板 + 25 主色蓝图标 | 第七批第 6 条已定：彩色大图标 40.aw、无底板、与应用管理逐项一致 |
| 布局期同帧读 `RenderBox` | 拿到的是上一帧布局（见记忆「滚动通知里同帧读RenderBox会拿到上一帧布局」），几何判定延到 postFrame |
| 用 `errorWidget`（已废弃） | `CachedNetworkImage` 用 `errorBuilder`，签名一致（`lib/components/nas_avatar.dart`） |
| 直接写 `Colors.grey.shadeXXX` 当语义色 | 见 §7-1 |

---

## 7. 可挖掘的设计理念（按性价比排序）

1. **把字面量色赶进 `FnTokens`。** 文件 tab / 传输页还留着 `0xFF1E1E1E`、`0xFF121212`、`grey.shade100/300/500`。做法：给 FnTokens 补 `sheet`（弹层底）、`menu`（菜单底）、`pageSolid`（纯色页底）、`dividerFaint` 四个 token，然后写一条 CI 断言——`lib/pages/**` 里出现 `Color(0xFF` 字面量就报警（现在只有人在 review 时肉眼看）。
2. **`FnTokens` 升成 `ThemeExtension`。** 现在取色要 `FnTokens.of(context)` 手动一行，Material 组件（AppBar、默认文字色）仍在用 `theme.colorScheme`，两套并行。收成一个 extension 之后，`Colors.white` 这种就能从代码里消失，深色也再漏不掉。
3. **几何回归测试覆盖 §4 全表。** 本轮验证了这条路走得通：`test/home_p1_test.dart` 逐项断言 `icon.size == 40.aw`、`icon.color == app.color`、底板不存在；`test/edit_user_form_test.dart` 11 条钉「不骗人」。把同样的写法给每个组件一条（尺寸、圆角、时长），**验收从「看着差不多」变成「等于参照物的参数」**——这是这套规范能被执行的关键，也是别人抄不走的资产。
4. **状态矩阵显式化。** 现在 loading / empty / filtered-empty / stale / error / no-permission 六态散在各页各自实现。抽一个 `PageStates`（或每页一个 `_statusView`），列表里强制选一个，编译器不允许「忘记空态」。首页、监控页、文件 tab 已经各有一套，合并成一套就能全站一致。
5. **动效时长收敛成两档。** 现有 150 / 160 / 180 / 200 / 420 / 650 / 1500ms 七种。定「微反馈 ≤180ms、状态切换 200ms、循环动画不归此管」，其余值要么归档要么注释理由。
6. **组件画廊（调试页）。** 项目已有调试页且正式版保留（你已接受风险）。把 §4 组件在一个 debug 页里全渲染一遍，浅色/深色各一屏。以后改 UI 先看画廊有没有破相，比逐页翻快得多，也是给「设计图必须能在手机上看清」这条准备的对照物。
7. **字号/间距/圆角阶梯表进代码。** §1.4 现在是文档里的表。做成 `FnType.title/card/list/sub` + `FnGap.s4/m12/l16` 常量，新代码引用阶梯值，**「随手 10、13、15」在编译期就没处站**。
8. **深色对比度校验。** 深色是「语义色提亮一档 + 描边代替阴影」的规则可以量化：写个小脚本读 `fn_tokens.dart`，对每对 (ink, card)、(ink2, card)、(label, card) 算 WCAG 对比度，低于阈值就报。目前 `dark.label` 与 `dark.ink2` 同值（都是 `8B95A4`），层级靠字号区分——是否合并、压不压暗，交给数据说话。
9. **「诚实面」设计语言可以再推一层。** 这轮沉淀出三种说法：字段拿不到就「—」、维度做不出来就解释为什么、NAS 同步没验证就写「按接口尝试」。把它们写成一条规范（§5-4 + §5-11），以后凡是接 DSM 的页面都按这个措辞，**用户投诉最多的「显示了但不是真的」会直接消失**。
10. **DSM 字段的「证据注释」约定。** 现在好的代码都写了「抓包里进程表就这五个字段」（`resource_monitor_page.dart:70` 一带）。把「这个字段我在哪份抓包/实测里见过」变成接口的 doc 注释模板，UI 层就能据此决定要不要显示——§7-9 的地基。

---

## 8. 新页面 checklist（开工前 60 秒过一遍）

- [ ] 页底：用 `t.pageBottom` 纯色（首页渐变是首页专属）。
- [ ] 顶栏：需要返回就用 `PageBackButton`；固定尺寸区域全裸 px。
- [ ] 取色：只从 `FnTokens` 取；深色检查描边/轨道/刻度这三处派生 token。
- [ ] 卡片：抄 `_HomeCard`（首页风格）或 `_card`+`_cardHead`（监控页风格），标题前 4×15 短条、能点就 `showChevron` + 整卡热区。
- [ ] 数据：`null` → 「—」；空态分清筛没/没有；取数失败但有旧数据 → 琥珀 banner 而不是全屏 error。
- [ ] 刷新：只有 `AppRefresh` 下拉；不加右上角按钮。
- [ ] 控件：`FnSegmented` / `FnDropdownPicker` / `FnPill` / `FnUsageRing` / `FnRankingCard` / `FnSparkChart`，不新造同类件。
- [ ] 单位：横向 `.aw`、纵向 `.h`、字号 `.asp`；百分比 `.wp`；间距用 `hGap/wGap/aGap`。
- [ ] 文案：单行 `maxLines+ellipsis`；可换行操作用 `Wrap`；不承诺未验证的能力；对外文案不出现竞品名。
- [ ] 验收：给关键几何补一条 widget test（等于哪个参照物的哪几个参数），别只截图。

---

*生成于 26.11.01，对应 v0.0.263 工作区（HEAD `3d58c15` 之后、未提交）。规范来源：文件 tab / 首页 / 运行状态 / 传输任务四组定稿页 + `lib/components` 全量组件 + `docs/首页改版方案.md`、`docs/ui_redesign/home_v3_mockup.html`。*
