# 群晖 DSM Web API 参考文档

> 本文档基于 `lib/network/dsm_api.dart` 逆向抓包实现整理。DSM 官方文档（`Synology_File_Station_API_Guide`、`Surveillance Station API` 等）只覆盖了很小一部分对外开放接口，绝大多数系统管理接口官方并未公开。本项目通过抓取 DSM Web 桌面（`https://<nas>:5001`）的真实网络请求还原实现，本文的目标是把这些"隐藏 API"的调用规律讲清楚，方便后续无限拓展。
>
> 权威来源：旧版 `refer_demo/dsm_helper/lib/util/api.dart`（137 个方法）+ 新版 `lib/network/dsm_api.dart`（162 个 API 方法）。

---

## 一、总体模型：一个入口打天下

群晖几乎所有 Web API 都走同一个 CGI 入口，通过参数区分具体功能：

| CGI 入口 | 用途 |
| --- | --- |
| `webapi/query.cgi` | 查询有哪些 API 可用、各自版本范围（`SYNO.API.Info`） |
| `webapi/auth.cgi` | 登录 / 登出 / 刷新 token（`SYNO.API.Auth`） |
| `webapi/entry.cgi` | **业务主入口**，99% 的功能都在这里，靠 `api` + `method` + `version` 三元组路由 |

一次典型请求（POST，`application/x-www-form-urlencoded`）的 body：

```
api=SYNO.FileStation.List&method=list&version=2&folder_path="/home"&_sid=xxxx
```

服务端根据 `api` 找到对应 CGI 模块，根据 `method` 找到操作，根据 `version` 选择实现版本，其余字段是该操作的参数。

**理解要点**：`api` / `method` / `version` 是"路由三要素"，缺一不可；`_sid` 是会话票据；其余全是业务参数。抓包时只要抓到这三要素 + 参数，就能在本框架里复刻任何接口。

---

## 二、请求基础设施（`DsmApi` 单例）

`DsmApi` 是全局单例（`DsmApi()` 工厂返回同一实例），持有当前连接的会话状态：

| 字段 | 含义 |
| --- | --- |
| `_server` | 当前 `ServerModel`（地址、端口、是否校验 SSL、DSM 版本等） |
| `_sid` | 登录后拿到的 session id，业务请求都要带 |
| `_cookie` | 登录返回的 Cookie（`id=...`），随 header 发送 |
| `_synoToken` | CSRF token（DSM 7 部分写操作需要，通过 `SYNO.API.Auth token` 刷新） |
| `_dsmVersion` | DSM 大版本（6 / 7），影响部分接口版本与分支（如媒体索引、Photos vs Photo） |
| `_apiRegistry` | `SYNO.API.Info` 查询结果缓存（API → {minVersion, maxVersion, path}） |

### 三个传输原语

所有业务方法最终都调用这三个方法之一：

- **`get(path, {data, host, checkSsl, cookie, cancelToken})`**
  用于 `auth.cgi` 登录（登录响应里解析并保存 Cookie）、`query.cgi` 查询。`data` 作为 query string。
- **`post(path, {data, host, checkSsl, cookie, cancelToken})`**
  业务主力。`data` 作为表单体，`contentType = application/x-www-form-urlencoded`。
- **`upload(path, {params, data, cancelToken, onSendProgress})`**
  文件上传，`data` 转 `FormData`（multipart），支持进度回调；`params` 走 query string。

### 统一的横切能力（写新接口无需重复关心）

- **Dio 实例**：`_createDio` 统一设置超时（连接/接收 20s、发送 60s）、`Cookie`、`Accept-Language`、`origin`/`referer`。
- **SSL**：`checkSsl=false` 时忽略自签证书（家用 NAS 常见）。
- **调试代理**：`AppPreferences` 里的 `debugIpSwitch`/`debugIp`/`debugPort` 打开后走 HTTP 代理（抓包用）。
- **响应解析** `_parseResponse`：字符串自动 `jsonDecode`；顺带做鉴权错误检查。
- **鉴权失效** `_checkAuthError`：识别 `error.code == 119`（含复合请求子结果里的 119），自动 `_handleLogout` 清空会话。
- **网络错误** `_handleDioError`：统一返回 `{success:false, error:{code}, data:null}`，`CERTIFICATE_VERIFY_FAILED` 归类为"SSL/HTTPS 证书有误"。

> 拓展新接口时，只需写"路由三要素 + 参数"，上述能力自动生效。

---

## 三、API 调用顺序（生命周期）

### 3.1 连接建立标准流程

```
1. queryApis()            // SYNO.API.Info query=all —— 探测该 NAS 支持哪些 API、版本范围
2. login(...)             // SYNO.API.Auth login —— 拿 sid / cookie / (可选) device_token
   └─ 若开启二步验证：先返回需要 otp，再带 otp_code 二次 login
3. refreshSynoToken()     // SYNO.API.Auth token —— DSM7 写操作前刷新 SynoToken（CSRF）
4. <业务请求...>          // entry.cgi，全部携带 _sid
5. logout()               // SYNO.API.Auth logout
```

**为什么第 1 步很重要**：不同型号/DSM 版本支持的 API 与版本范围不同。先 `queryApis()` 拿到 `_apiRegistry`，再对拿不准的接口用 `min(minVersion, 期望版本)` 兜底（旧版 `networkStatus` 就是这么处理 `SYNO.Core.Network` 的版本）。

### 3.2 "任务型"接口的两段式调用（非常常见）

耗时操作（删除、搜索、复制移动、压缩解压、算目录大小、SMART 检测）都拆成 **start → poll status** 两步，靠 `taskid` 关联：

| 场景 | 发起 | 轮询结果 |
| --- | --- | --- |
| 删除 | `deleteTask` (`Delete/start`) | `deleteResult` (`Delete/status`) |
| 搜索 | `searchTask` (`Search/start`) | `searchResult` (`Search/list`) |
| 复制/移动 | `copyMoveTask` (`CopyMove/start`) | `copyMoveResult` (`CopyMove/status`) |
| 压缩 | `compressTask` (`Compress/start`) | `compressResult` (`Compress/status`) |
| 解压 | `extractTask` (`Extract/start`) | `extractResult` (`Extract/status`) |
| 目录大小 | `dirSizeTask` (`DirSize/start`) | `dirSizeResult` (`DirSize/status`) |
| SMART 检测 | `doSmartTest` | `smartTestLog` |
| 套件安装 | `installPackageTask` (`install`) | `installPackageStatus` (`status`) |

**调用模式**：`start` 返回 `taskid` → 定时（1~2s）调 `status`，直到 `finished == true` → 取结果。

### 3.3 详情页/首页的"批量拉取"（复合请求，见第五节）

`dashboardData`（首页）、`userDetail`（用户详情）、`powerStatus`（电源页）、`networkStatus`（网络页）、`fileService`（文件服务页）等，都用 `SYNO.Entry.Request` 一次并/串行拉多个子接口，减少往返。

### 3.4 Photos 的版本分叉

- **DSM 7**：`SYNO.Foto.*`（个人空间）/ `SYNO.FotoTeam.*`（共享空间）。
- **DSM 6**：`SYNO.Photo.*`（如 `photoTimeline`）。

代码里按 `_dsmVersion` 选择调用 `fotoXxx` 还是 `photoXxx`。

---

## 四、API 版本参数（`version`）说明

`version` 不是全局版本，而是**每个 API 各自独立的实现版本**。同一个 `SYNO.Core.System` 在不同调用里用不同 version：

| 调用 | api | version | 说明 |
| --- | --- | --- | --- |
| `systemInfo` | SYNO.Core.System | 1 | 常规系统信息 |
| `networkInfo` | SYNO.Core.System | 1 | `type=network` 取网络信息 |
| `firmwareVersion` | SYNO.Core.System | 3 | `type=firmware` 取固件信息（需要 v3） |

**版本选择原则**：

1. **以抓包为准**：DSM Web 前端用哪个版本，就抄哪个版本，别自己猜。低级模型之前臆造版本号导致大量接口失效（如把 `DownloadStation2.Task.List get v2` 写成 `Task list v1`）。
2. **拿不准时用 `_apiRegistry` 兜底**：`min(_apiRegistry[api].maxVersion, 期望版本)`。
3. **version 可以是数字也可以是字符串**：复合请求的子 API 里群晖前端有时写 `"version": "3"`（字符串），本框架忠实保留（如 `fileServiceSave` 的 FTP 子项）。

### 4.1 参数引号包裹约定（易踩坑）

群晖 `entry.cgi` 的很多字符串/JSON 参数期望**带引号的字符串字面量**。本框架沿用旧版约定，用两种写法表达：

- `'"$name"'` —— 生成形如 `"abc"` 的值（**值本身带一对双引号**），用于需要 JSON 字符串的字段（`name`、`device`、`id` 等）。
- `jsonEncode(list)` / `jsonEncode(map)` —— 生成 JSON 文本，用于数组/对象参数（`additional`、`compound`、`shareinfo` 等）。
- 裸值（`true`/数字/`listId`）—— 布尔、数字、以及服务端按裸串接收的字段。

> 注意：这套"引号里再套引号"的写法看起来别扭，但它是抓包实测的服务端期望格式，**不要擅自去掉**。加错/去错引号是接口 400/参数错误的头号原因。

---

## 五、共性与拓展指南（重点）

### 5.1 单接口的标准骨架

```dart
/// <一句话说明>
Future<Map> myApi(String someArg) async {
  return await post('entry.cgi', data: {
    'api': 'SYNO.Xxx.Yyy',      // 路由：抓包拿到
    'method': 'do_something',    // 路由：抓包拿到
    'version': 1,                // 路由：抓包拿到，拿不准用 _apiRegistry 兜底
    'some_field': '"$someArg"',  // 业务参数：字符串按需加引号
    'list_field': jsonEncode(x), // 业务参数：数组/对象用 jsonEncode
    '_sid': _sid,                // 会话票据（写操作/私有接口必带）
  });
}
```

照抄这个骨架 + 抓包结果，即可新增任意接口。

### 5.2 复合请求（Compound / `SYNO.Entry.Request`）——一次拉多个

当一个页面需要多个子接口的数据时，用复合请求合并往返：

```dart
Future<Map> myCompound() async {
  final apis = [
    {'api': 'SYNO.Core.A', 'method': 'get', 'version': 1},
    {'api': 'SYNO.Core.B', 'method': 'list', 'version': 2, 'extra': 'x'},
  ];
  return await post('entry.cgi', data: {
    'api': 'SYNO.Entry.Request',
    'method': 'request',
    'mode': '"sequential"',      // 或 '"parallel"'
    'compound': jsonEncode(apis),// 子请求数组序列化成 JSON
    'version': 1,
    'stop_when_error': false,    // 可选：某子项失败不中断其余
    '_sid': _sid,
  });
}
```

- **`mode`**：`"parallel"`（并行，子项互不依赖，最快，如 `dashboardData`/`publicAccessInfo`）；`"sequential"`（串行，如 `userDetail`/`powerStatus`/`fileService`）。
- **`stop_when_error`**：`false` 时单个子项失败不影响其他子项返回。
- **返回结构**：`data.result` 是数组，顺序与 `apis` 一致，每项含各自的 `success`/`data`/`error`。
- **鉴权检查**：`_checkAuthError` 会遍历 `data.result` 检查子项 119 错误。

本项目复合请求接口：`dashboardData`、`publicAccessInfo`、`firmwareVersion`、`firmwareUpgrade`、`networkStatus`、`externalDevice`、`powerStatus`、`powerSet`、`userDetail`、`userSave`、`fileService`、`fileServiceSave`、`mediaIndexStatus`、`mediaIndexSet`、`utilization`/`systemInfo`（部分）。

### 5.3 文件上传骨架

```dart
Future<Map> myUpload(String path, String filePath) async {
  final file = File(filePath);
  final data = {
    'api': 'SYNO.FileStation.Upload', 'method': 'upload', 'version': 3,
    'path': path, 'overwrite': true,
    'mtime': file.lastModifiedSync().millisecondsSinceEpoch,
    'size': file.lengthSync(),
    'file': MultipartFile.fromFileSync(filePath, filename: file.path.split('/').last),
    '_sid': _sid,
  };
  return await upload('entry.cgi', data: data);
}
```

Photos 备份上传（`fotoBackupUpload`）还可附带 `thumb_sm`/`thumb_xl` 缩略图 MultipartFile。

### 5.4 返回值与错误处理共性

- 成功：`{success: true, data: {...}}`。
- 失败：`{success: false, error: {code: <int>}}`；`code=119` 表示会话失效（自动登出）。
- 任务型：`start` 返回 `{data:{taskid}}`；`status` 返回 `{data:{finished, ...}}`。
- 网络层异常：统一 `{success:false, error:{code:<描述>}, data:null}`。

### 5.5 拓展一个新接口的标准流程（Checklist）

1. 浏览器打开 DSM 桌面，操作目标功能，F12 抓 `entry.cgi` 请求。
2. 记录 `api` / `method` / `version` 三要素 + 全部业务参数（注意哪些带引号、哪些是 JSON）。
3. 在 `DsmApi` 里按 5.1 / 5.2 骨架新增方法，字符串参数用 `'"$x"'`，数组/对象用 `jsonEncode`。
4. `_sid` 带上；写操作若 DSM7 报 CSRF，检查是否需 `_synoToken`。
5. `flutter analyze` 校验，联调核对返回结构。

---

## 六、完整 API 清单（按模块）

> 版本号以代码实测为准。复合请求标注 [复合]，其 `version` 指外层 `SYNO.Entry.Request` 的版本，子项版本见源码。

### 6.1 认证 / 探测（auth.cgi / query.cgi）
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `queryApis` | SYNO.API.Info | query | 1 |
| `login` | SYNO.API.Auth | login | 7 |
| `refreshSynoToken` | SYNO.API.Auth | token | 6 |
| `logout` | SYNO.API.Auth | logout | 6 |
| `quickConnect` / `quickConnectCn` / `pingpong` | QuickConnect / SYNO.API.Info | - | 1 |

### 6.2 FileStation 文件管理
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `shareList` | SYNO.FileStation.List | list_share | 2 |
| `fileList` | SYNO.FileStation.List | list | 2 |
| `createFolder` | SYNO.FileStation.CreateFolder | create | 2 |
| `rename` | SYNO.FileStation.Rename | rename | 2 |
| `deleteTask` / `deleteResult` | SYNO.FileStation.Delete | start / status | 2 |
| `searchTask` / `searchResult` | SYNO.FileStation.Search | start / list | 2 |
| `copyMoveTask` / `copyMoveResult` | SYNO.FileStation.CopyMove | start / status | 3 |
| `compressTask` / `compressResult` | SYNO.FileStation.Compress | start / status | 3 / 2 |
| `extractTask` / `extractResult` | SYNO.FileStation.Extract | start / status | 2 / 1 |
| `uploadFile` / `uploadWeb` | SYNO.FileStation.Upload | upload | 3 / 2 |
| `createShare` / `listShare` / `deleteShare` / `editShare` | SYNO.FileStation.Sharing | create / list / delete / edit | 3 |
| `favoriteList` / `favoriteAdd` / `favoriteDelete` / `favoriteRename` | SYNO.FileStation.Favorite | list / add / delete / edit | 2 |
| `dirSizeTask` / `dirSizeResult` | SYNO.FileStation.DirSize | start / status | 1 |
| `backgroundTask` | SYNO.FileStation.BackgroundTask | list | 3 |
| `checkPermission` | SYNO.FileStation.CheckPermission | write | 3 |
| `smbFolder` / `remoteLink` | SYNO.FileStation.VirtualFolder | list | 2 |
| `remoteUnConnect` | SYNO.FileStation.VFS.Connection | delete | 1 |
| `mountFolder` / `unMountFolder` | SYNO.FileStation.Mount | mount_remote / unmount | 1 |

### 6.3 Core 系统 / 监控 / 通知
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `systemInfo` [复合] | SYNO.Core.System | info | 1 |
| `utilization` / `dashboardData` [复合] | SYNO.Core.System.Utilization | get | 1 |
| `firmwareVersion` [复合] | SYNO.Core.System | info(`type=firmware`) | 3 |
| `firmwareUpgrade` [复合] | SYNO.Core.Upgrade.Server | check | 2 |
| `networkInfo` | SYNO.Core.System | info(`type=network`) | 1 |
| `storage` | SYNO.Storage.CGI.Storage | load_info | 1 |
| `power` | SYNO.Core.System | list | 1 |
| `process` / `processGroup` | SYNO.Core.System.Process / ProcessGroup | list / get | 1 |
| `notifyStrings` | SYNO.Core.DSMNotify.Strings | get | 1 |
| `notify` / `clearNotify` | SYNO.Core.DSMNotify | notify | 1 |
| `currentConnection` / `kickConnection` | SYNO.Core.CurrentConnection | list / kick_connection | 1 |
| `initData` | SYNO.Core.Desktop.Initdata | get | 1 |
| `eventRun` | SYNO.Core.EventScheduler | run | 1 |

### 6.4 网络 / DDNS / 公网访问
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `networkStatus` [复合] | SYNO.Core.Network 等 | get / list | 1 |
| `publicAccessInfo` [复合] | SYNO.Core.DDNS.Provider/Record/ExtIP/Synology | list / get_myds_account | 1 |
| `ddnsSave` / `ddnsUpdate` / `ddnsDelete` / `ddnsTest` | SYNO.Core.DDNS.Record | set / update_ip_address / delete / test | 1 |

### 6.5 存储 / 磁盘 / 外接设备
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `volumes` | SYNO.Core.Storage.Volume | list | 1 |
| `diskInfo` | SYNO.Core.Storage.Disk | list | 1 |
| `smart` / `smartData` | SYNO.Storage.CGI.Smart | get_health_info | 1 |
| `diskTestLog` | SYNO.Core.Storage.Disk | disk_test_log_get | 1 |
| `smartTestLog` | SYNO.Core.Storage.Disk | get_smart_test_log | 1 |
| `doSmartTest` | SYNO.Core.Storage.Disk | do_smart_test | 1 |
| `externalDevice` [复合] | SYNO.Core.ExternalDevice.Storage.USB/eSATA | list | 1 |
| `ejectEsata` | SYNO.Core.ExternalDevice.Storage.eSATA | eject | 1 |
| `cleanRecycleBin` | SYNO.Core.RecycleBin | start | 1 |

### 6.6 电源 / 硬件
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `powerStatus` [复合] | SYNO.Core.Hardware.* / UPS / PowerSchedule | get / load | 1 |
| `powerSet` [复合] | SYNO.Core.Hardware.ZRAM/PowerRecovery/BeepControl/FanSpeed/Led | set | 1 |
| `powerScheduleSave` | SYNO.Core.Hardware.PowerSchedule | save | 1 |
| `powerHibernationSave` | SYNO.Core.Hardware.Hibernation | set | 1 |

### 6.7 套件（Package）
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `installedPackages` | SYNO.Core.Package | list | 1 |
| `packages` | SYNO.Core.Package.Server | list | 1 |
| `launchPackage` | SYNO.Core.Package.Control | - | 1 |
| `launchedPackages` | SYNO.Core.Polling.Data | get | 1 |
| `installPackageTask` / `installPackageStatus` / `installPackageQueue` | SYNO.Core.Package.Installation | install / status / get_queue | 1 |
| `uninstallPackageInfo` | SYNO.Core.Package | get | 1 |
| `uninstallPackageTask` | SYNO.Core.Package.Uninstallation | uninstall | 1 |

### 6.8 用户 / 群组 / 权限 / OTP
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `users` / `normalUser` | SYNO.Core.User / NormalUser | list | 1 |
| `userDetail` [复合] | SYNO.Core.User 等 8 项 | get / list_by_user 等 | 1 |
| `userSave` [复合] | SYNO.Core.User + Group.Member | set / add / remove | 1 |
| `userGroups` / `userGroup` | SYNO.Core.Group | list | 1 |
| `userQuota` | SYNO.Core.PersonalSettings | quota | 1 |
| `userSetting` | SYNO.Core.UserSettings | apply | 1 |
| `getQrCode` / `saveMail` / `authOtpCode` | SYNO.Core.OTP | get_qrcode / save_mail / auth_tmp_code | 2 |
| `trustDevice` | SYNO.Core.TrustDevice | (get/set) | 1 |

### 6.9 共享文件夹（Core.Share）
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `shareCore` | SYNO.Core.Share | list | 1 |
| `shareDetail` | SYNO.Core.Share | get | 1 |
| `addSharedFolder` | SYNO.Core.Share | create/edit | 1 |
| `deleteSharedFolder` | SYNO.Core.Share | delete | 1 |

### 6.10 文件服务（SMB/AFP/NFS/FTP）
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `fileService` [复合] | SYNO.Core.FileServ.SMB/AFP/NFS/FTP/SFTP + SyslogClient | get | 1 |
| `fileServiceSave` [复合] | 同上 | set | 1 |
| `fileServiceLog` / `fileServiceLogSave` | SYNO.Core.SyslogClient.FileTransfer | get_level / set_level | 1 |

### 6.11 下载（DownloadStation2）
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `downloadStationInfo` [复合] | SYNO.DownloadStation2.Task | list | 2 |
| `downloadTaskAction` / `downloadTaskCreate` | SYNO.DownloadStation2.Task | create | 1 / 2 |
| `downloadLocation` [复合] | SYNO.DownloadStation2.Settings.Location | get | 1 |
| `downloadFileList` | SYNO.DownloadStation2.Task.List | get | 2 |
| `downloadCreate` | SYNO.DownloadStation2.Task.List.Polling | download | 2 |
| `downloadDetail` | SYNO.DownloadStation2.Task | get | 2 |
| `downloadTracker` / `downloadTrackerAdd` | SYNO.DownloadStation2.Task.BT.Tracker | list / add | 2 |
| `downloadPeer` | SYNO.DownloadStation2.Task.BT.Peer | list | 2 |
| `downloadFile` | SYNO.DownloadStation2.Task.BT.File | list | 2 |

### 6.12 Docker / 虚拟机
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `dockerContainerInfo` [复合] / `dockerImageInfo` [复合] | SYNO.Docker.Container / Image | list | 1 |
| `dockerPower` / `dockerDetail` | SYNO.Docker.Container | (start/stop/get 等) | 1 |
| `dockerLog` | SYNO.Docker.Container.Log | list | 1 |
| `cluster` / `vmmPower` | SYNO.Virtualization.Cluster / Guest.Action | pwr_ctl | 1 |
| `checkPowerOn` | SYNO.Virtualization.Guest.Action | check_poweron | 1 |

### 6.13 Photos（DSM7 Foto / FotoTeam，DSM6 Photo）
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `fotoTimeline` | SYNO.Foto.Browse.Timeline | list | 2 |
| `fotoAlbums` / `fotoSharedAlbums` | SYNO.Foto.Browse.Album | list | 2 |
| `fotoFolders` / `fotoRecentlyAdded` / `fotoGeocoding` / `fotoGeneralTag` / `fotoCategory` | SYNO.Foto.Browse.* | list | 1 |
| `fotoBrowseItem` | SYNO.Foto.Browse.Item | list | 1 |
| `fotoDeleteItem` | SYNO.Foto.Browse.Item | delete | 6 |
| `fotoTeam*` | SYNO.FotoTeam.Browse.* | list | 1~2 |
| `photoTimeline` [复合] | SYNO.Photo.Browse.Timeline | list | 2 |
| `fotoBackupCheck` / `fotoBackupUpload` | SYNO.Foto.Upload.Item | backup_check / backup_to_path | 7 |

### 6.14 媒体索引 / 日志 / 安全 / 计划任务 / 终端
| 方法 | api | method | version |
| --- | --- | --- | --- |
| `mediaIndexStatus` [复合] / `mediaIndexSet` [复合] | SYNO.Core.MediaIndexing.ThumbnailQuality 等 | get / set | 1 |
| `mediaReindex` | SYNO.Core.MediaIndexing | reindex | 1 |
| `mediaConverter` | SYNO.Core.MediaIndexing.MediaConverter | latestlog_get | 1 |
| `lastLog` | SYNO.Core.SyslogClient.Status | latestlog_get | 1 |
| `log` / `fileTransferLog` | SYNO.Core.SyslogClient.Log | list | 1 |
| `logHistory` | SYNO.LogCenter.History | list | 1 |
| `securityScanStatus` / `securityRuleGet` / `securitySystemGet` | SYNO.Core.SecurityScan.Status | get / rule_get / system_get | 1 |
| `taskScheduler` / `taskRun` / `taskEnable` / `taskRecord` | SYNO.Core.TaskScheduler | list / run / set_enable / view | 1 |
| `terminalInfo` / `setTerminal` | SYNO.Core.Terminal | get / set | 3 |

---

## 七、迁移记录（旧版 → 新版）

本次已把旧版 `dsm_helper` 的全部 DSM API 方法迁移/核对到新版 `dsm_api.dart`，共 162 个 API 方法。

**本次补迁的 43 个方法**（旧版有、之前新版缺）：
共享/挂载/权限、DDNS/网络/固件、下载（含 `downloadCreate`/`downloadTrackerAdd`）、存储/磁盘、电源硬件、套件安装、用户/OTP、文件服务、媒体索引、桌面/计划任务/虚拟机等。

**已存在（旧版名 → 新版重命名）**，无需重复迁移：
- `api` → `queryApis`
- `currentConnect` → `currentConnection`
- `securityRule` → `securityRuleGet`
- `securitySystem` → `securitySystemGet`

**有意不迁移**（非 DSM API 或已废弃）：
- `reward`：请求外部 App 服务器 `${appUrl}/reward`（打赏），与 NAS 无关。
- `update`：请求第三方 pgyer.com 检查 App 版本；新项目改用 `release/*.json` 自托管更新机制（见 `lib/utils/update_service.dart`）。
- `fileStationInfo`：旧版源码中该方法本就是注释掉的，从未实现。

---

## 附：为什么"抓包实现"是可靠的

群晖 Web 桌面本身就是调用这些 `entry.cgi` 接口，前端参数即服务端契约。只要：
1. 严格照抄抓包的 `api`/`method`/`version` 三要素；
2. 保持参数的引号/JSON 编码格式；
3. 带好 `_sid`（必要时 `_synoToken`）；

就能稳定复刻任意 DSM 功能。**切忌凭经验猜测 method 名或 version 号**——群晖不同模块命名风格不统一（`get`/`load`/`load_info`/`get_health_info` 混用，version 从 1 到 7 都有），猜测几乎必错。
