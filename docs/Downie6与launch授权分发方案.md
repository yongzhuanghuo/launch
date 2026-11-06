# Downie6 × launch：macOS 分发、自动更新与统一卡密授权设计方案

> 状态：设计稿，待实施  
> 日期：2026-11-06  
> 涉及仓库：`launch`（SwiftUI 客户端）、`4KDownle`（Flutter 客户端 + FastAPI 后端 + vue-pure-admin 管理后台）

## 背景

两个 macOS 产品要共用一套分发与授权体系：

- **Downie6（4KDownle 项目，Flutter）**：已发布 v2.0.52；已有 FastAPI + MySQL 后端、vue-pure-admin 卡密后台、OSS 分发，以及 14 天试用、邮箱+卡密激活、设备绑定/解绑，**邮箱找回是“发邮件给支持”的人工流程**。
- **launch（原 launch，SwiftUI）**：目前没有任何授权代码；需要 Intel + Apple Silicon 通用包、OSS 分发/自动更新、14 天试用、邮箱+卡密激活、人工邮箱找回、到期硬锁。

目标：在现有后端上加一个 `product` 维度，把 Downie6 已经跑通的授权逻辑直接搬到 launch；后台只做最小改动（加产品、卡密按产品区分）；不做 OTP、不做订单/支付、不做复杂的批次/试用/版本/审计后台。

## 已确认的决策

| 议题 | 决策 |
|---|---|
| 产品 | 卡密后台的产品是 **Downie6** 和 **launch**（不是 4kdownle）；后续可继续加产品，逻辑完全一样（14 天试用 + 卡密） |
| 产品编码 | `downie6`、`launch`；生成卡密前**必须先选产品**，卡密归属产品，跨产品激活返回 `INVALID_CODE` |
| launch 授权 | 直接移植 Downie6 已实现的 Flutter 授权逻辑到 Swift：试用、邮箱+卡密激活、设备管理、心跳/verify、人工找回 |
| 邮箱/找回 | 沿用 Downie6 现有邮箱 `huoyongzhuang@qq.com`；找回 = App 内发邮件给支持，管理员后台按邮箱查卡密/解绑；**不新增 OTP/验证码/发信接口** |
| Downie6 客户端 | 不改造授权流程；只增加 `product` 参数与分发/更新改造 |
| 后台 | **保留现有卡密页**，只加产品筛选/列和生成时的产品选择；另加一个简单的“产品管理”页；不加批次/试用/版本/审计页面 |
| 购买/订单 | 站外销售，只记卡密；不做支付与订单表 |
| 命名 | launch 全部改名（原 launch），Bundle ID、工程、目录、文案、OSS 前缀统一为 launch |
| 网络 | 先复用 Downie6 的 HTTP API；launch 加 ATS 例外；API base 可配置，后续可切 HTTPS |

## 目标架构

```
┌──────────────┐        ┌──────────────┐
│ Downie6.app  │        │ launch.app   │
│ Flutter      │        │ SwiftUI      │
│ 现有授权逻辑  │        │ 移植授权逻辑  │
└──────┬───────┘        └──────┬───────┘
       │ /api/license/*?product= │
       └────────────┬───────────┘
                    ▼
       FastAPI（沿用 8.153.99.239:3000）
       ├─ MySQL：products / licenses / device_bindings /
       │          trials / releases
       └─ 现有 in-memory 限流（不新增 Redis 依赖）
                    │
       ┌────────────┴────────────┐
       ▼                         ▼
 vue-pure-admin 后台         阿里云 OSS 4kdownlebucket
 卡密页 + 产品管理            ├─ releases/Downie6.dmg（旧客户端兼容）
                              ├─ downie6/macos/...（版本化 + latest）
                              └─ launch/macos/...（ZIP/DMG + latest.json）
```

---

## 一、数据库：只加产品维度和试用表

原则：**保留现有表结构和字段语义**，旧客户端/旧 ORM 不受影响；能不加的表就不加。

### 1. 新增 `products`

```sql
products (
  id BIGINT PK AUTO_INCREMENT,
  code VARCHAR(32) UNIQUE,          -- 'downie6' / 'launch'
  name VARCHAR(64),                 -- 后台显示名
  trial_days INT DEFAULT 14,
  default_max_devices INT DEFAULT 1,
  purchase_url VARCHAR(512),
  support_email VARCHAR(255),
  status TINYINT DEFAULT 1,
  created_at DATETIME
)
```

种子：

- `1=downie6`，name `Downie6`，14 天、默认 4 设备，支持邮箱 `huoyongzhuang@qq.com`
- `2=launch`，name `launch`，14 天、默认 1 设备，支持邮箱 `huoyongzhuang@qq.com`

后续新增产品只需加一行；生成卡密时自动出现在产品下拉里。

### 2. `licenses` 加一列

```sql
ALTER TABLE licenses ADD COLUMN product_id BIGINT NOT NULL DEFAULT 1;
ALTER TABLE licenses ADD KEY idx_licenses_product_status (product_id, status);
```

- 旧卡密回填 `product_id=1`（Downie6）。
- `code` 仍是全局唯一 20 位；`type`、`max_devices`、`email`、`expire_at`、`status` 全部不动。
- 不需要 batch、email_verified、activated_at、expire_basis 等新字段。

### 3. `device_bindings` 加一列

```sql
ALTER TABLE device_bindings ADD COLUMN product_id BIGINT NOT NULL DEFAULT 1;
ALTER TABLE device_bindings ADD KEY idx_dev_product_fp (product_id, device_fp);
```

按 `licenses.product_id` 回填。保留 `UNIQUE(code, device_fp)`。

### 4. 新增 `trials`

```sql
trials (
  id BIGINT PK AUTO_INCREMENT,
  product_id BIGINT NOT NULL,
  device_fp VARCHAR(64) NOT NULL,
  device_name VARCHAR(255),
  platform VARCHAR(20),
  first_seen DATETIME,
  trial_start DATETIME,
  trial_end DATETIME,
  email VARCHAR(255),
  status ENUM('active','expired','converted','revoked') DEFAULT 'active',
  last_seen DATETIME,
  UNIQUE KEY uq_trial_product_device (product_id, device_fp)
)
```

**关键**：唯一键是 `(product_id, device_fp)`，同一台 Mac 上 Downie6 和 launch 各自有独立的 14 天试用。旧 `trial_devices` 数据迁移后保留为只读备份表。

### 5. 新增 `releases`（给 CI 自动发布用）

```sql
releases (
  id BIGINT PK AUTO_INCREMENT,
  product_id BIGINT NOT NULL,
  platform VARCHAR(20) NOT NULL DEFAULT 'macos',
  version VARCHAR(32),
  build INT,
  artifact_url VARCHAR(1024),
  artifact_sha256 CHAR(64),
  artifact_size BIGINT,
  changelog TEXT,
  force_update TINYINT DEFAULT 0,
  status ENUM('draft','published','revoked') DEFAULT 'draft',
  published_at DATETIME,
  created_at DATETIME,
  UNIQUE KEY uq_release_build (product_id, platform, build)
)
```

不做版本管理后台；CI 发布成功后调用内部接口写这张表，客户端走现有 `/api/version/latest`。

### 6. 迁移

- 新增 `services/api/sql/migrations/20261106_multi_product.sql`，沿用现有 `information_schema + PREPARE` 幂等写法。
- 迁移前 `mysqldump` 备份；回填 `licenses.product_id=1`、`device_bindings.product_id`、`trial_devices` → `trials`。
- 同步更新 `sql/schema.sql` 与 `sql/init_all.sql`；两者重复维护的问题后续再收敛，本次先保持一致。

---

## 二、API：只加可选 product 参数

所有 `/api/license/*`、`/api/version/latest` 新增**可选** `product`，缺省一律 `downie6`；旧字段、错误码、HTTP 状态码全部保留。

| 接口 | 变更 |
|---|---|
| `POST /api/license/trial/start` | 可选 `product`；按 `(product_id, device_fp)` 记录试用 |
| `GET /api/license/trial/status` | 可选 `product` |
| `POST /api/license/activate` | 可选 `product`；校验卡密属于该产品；邮箱+卡密逻辑不变 |
| `POST /api/license/unbind` | 可选 `product` |
| `POST /api/license/heartbeat` | 可选 `product` |
| `POST /api/license/verify` | 可选 `product` |
| `GET /api/license/status` | 可选 `product` |
| `GET /api/version/latest` | 可选 `product`、`platform`；优先读 `releases` 表，无数据回退现有 `.env` |

新增（很少的）管理端接口：

- `POST /product/list`、`POST /product/create`、`POST /product/update`：产品管理。
- `POST /card/list|stats|export|generate` 增加 `product` 字段/筛选；不传时按 `downie6`，保持旧后台行为。
- `POST /api/internal/releases/publish`：CI 用 `RELEASE_TOKEN` 调用，写 `releases` 表；校验 build 不回退、URL 为 HTTPS、SHA256 格式。`RELEASE_TOKEN` 加到 `config.py` 与 `.env`，不写进仓库。

**不新增**：OTP、找回、批次、试用管理、版本管理、审计接口。

---

## 三、后台：卡密页保持现状，只加产品

保留 vue-pure-admin 和现有 `/card` 页面，不做大改。

### 卡密页改动（`apps/admin-web/src/views/card/index.vue`）

- 顶部加**产品筛选下拉**（全部 / Downie6 / launch；从 `products` 动态加载）。
- 表格加**产品列**。
- 生成卡密弹窗：**第一项选产品**（默认 Downie6），再填现有的类型、数量、设备数、有效期、邮箱。
- 统计卡和导出跟随当前产品筛选；不新增其他统计维度。
- 其余详情、改邮箱、吊销/恢复、设备列表、复制/导出全部保持现有交互。

### 新增“产品管理”页（`apps/admin-web/src/views/product/index.vue`）

- 列表：产品名、code、试用天数、默认设备数、购买链接、支持邮箱、状态。
- 新增/编辑：以上字段；code 有卡密后不可改。
- 保存后卡密生成下拉立即出现；不需要改代码。

### 菜单

在 `scripts/init_db.py` 的 `MENUS` 和 `sql/init_all.sql` 增加“产品管理”（`/product`）；现有“卡密管理”保持不变。

---

## 四、Downie6：通用包 + OSS 自动发布

### 1. 通用包（Intel + Apple Silicon）

Flutter Release 默认会产出双架构，但仓库没有显式校验，且存在 Intel 缺口：

- **node 只有 arm64**：CI 在 arm64 runner 上只下载 `node-v22.13.1-darwin-arm64`，写成单一 `assets/bin/macos/node`；Intel 用户执行抖音签名会失败。
  - 修复：CI 同时下载 `node_arm64` / `node_x86_64`；`binary_locator.dart` 增加 `nodeAssetName`（按 `Abi.current()` 选择）；`binary_initializer.dart` 用 `assetName` 提取，目标仍叫 `node`，并加 `.node-build` 标记。
- **x86_64 SABR yt-dlp**：`build-ytdlp-macos-x64` 目前 `continue-on-error: true`，失败会被静默忽略；改为发布前检查 `yt-dlp_arm64` 和 `yt-dlp_x86_64` 都存在。
- **显式架构**：Release 配置加 `ARCHS = "arm64 x86_64"; ONLY_ACTIVE_ARCH = NO;`；新增 `tools/verify_macos_archs.sh`，用 `lipo -archs` 检查主程序、`FlutterMacOS.framework`、`App.framework`、`Pods_Runner.framework`、`ffmpeg`、`yt-dlp`。

### 2. 签名/公证

现状 ad-hoc 签名，用户需要右键打开/`xattr -cr`。建议复用 launch 已有的 Developer ID Team（`D4KD8XCCL6`）：

- `ENABLE_HARDENED_RUNTIME=YES`；补 Flutter/Dart 需要的最小 entitlements（`allow-jit`、`allow-unsigned-executable-memory`），嵌入的 yt-dlp/ffmpeg/node 逐个签名。
- 签名 `.app` 和 DMG，`notarytool submit` + `stapler staple`；CI 校验 `codesign --verify --deep --strict`、`spctl --assess`、`stapler validate`。
- 暂不公证也可先发，但保留 SHA256 强校验。

### 3. 自动发布到 OSS

改 `.github/workflows/build.yml`：

1. 打 tag `v*` 触发；校验 tag 与 `pubspec.yaml` 版本一致。
2. 构建 universal `.app` → 架构校验 → 签名/公证 → 生成 DMG。
3. 计算 SHA256；上传：
   - `downie6/macos/<version>/Downie6-<version>.dmg`
   - `downie6/macos/latest/Downie6.dmg`
   - `downie6/macos/latest.json`
   - 旧兼容：`releases/Downie6.dmg`（旧客户端继续可用）
4. 调用 `POST /api/internal/releases/publish` 写 `releases` 表；不再手工改 `.env`。
5. Windows 同样版本化上传，保留 `releases/Downie6-Windows-Setup.exe`。

### 4. Downie6 客户端改动（最小）

- 授权/版本请求带 `product=downie6`；服务端缺省也是它，旧包不受影响。
- `version_check.dart` 解析新增的 `size` 字段；继续用现有 SHA256 校验与 DMG 安装流程。
- 不改试用、激活、邮箱绑定、设备管理、UI。

---

## 五、launch：移植 Downie6 授权 + 自动更新

### 1. 先全部改名（Phase R）

用户确认所有层级统一改名为 `launch`（原 launch）。这是破坏性重命名，单独一个阶段做。

| 层级 | 旧 | 新 |
|---|---|---|
| 产品名/显示名 | launch | launch |
| Bundle ID | `com.roversx.launch` | `com.roversx.launch` |
| Xcode 工程/target/scheme | `launch.xcodeproj` / `launch` | `launch.xcodeproj` / `launch` |
| 源码/测试目录 | `launch/`、`launchTests/` 等 | `launch/`、`launchTests/` 等 |
| 产品 code / OSS 前缀 | `launch` | `launch` |
| 数据/缓存/日志目录 | `.../launch/`、`.../com.roversx.launch` | `.../launch/`、`.../com.roversx.launch` |
| UserDefaults | `com.roversx.launch`、旧 suite `"launch"` | `com.roversx.launch` |
| 文档/README/i18n/网站/更新源 | `yongzhuanghuo/launch`、`closex.org/launch` | 新仓库/网站/OSS |

必须处理：

- 首次启动迁移旧 UserDefaults、`Application Support/launch/Data.store`、自定义图标、备份、updater 配置；写迁移标记，旧目录保留一个版本。
- Bundle ID 变化会让辅助功能/屏幕录制/输入监控等 TCC 权限失效，首次启动引导重新授权；登录项重新注册。
- 旧 Bundle ID 无法静默升级到新 Bundle ID：如还能控制旧更新源，发一个“旧身份桥接版”负责装 `launch.app` 并迁移；否则公告用户手动下载。
- `scripts/release-notarized.sh` 里写死的 bundle id、`launch.app`、lipo 检查全部更新。
- 全仓库 `grep -ri launch` 清干净（迁移代码/旧路径白名单除外）。

### 2. launch 授权模块（照 Downie6 搬）

新增 `launch/License/`：

| 文件 | 职责 |
|---|---|
| `LicenseConfig.swift` | API base、`product = "launch"`、支持邮箱 `huoyongzhuang@qq.com`、离线宽限天数 |
| `DeviceIdentity.swift` | IOKit `IOPlatformUUID` 去横线小写；失败回退持久化安装 ID |
| `LicenseStore.swift` | 本地保存 license/trial/email/最后校验时间；优先 Keychain，失败回退 `Application Support/launch/License/license.json`（0600） |
| `LicenseAPI.swift` | URLSession，调用现有 `/api/license/*`，`product=launch` |
| `LicenseManager.swift` | 状态机：试用中/已授权/已过期锁定；启动、试用、激活、设备管理、verify/heartbeat |
| `LicenseWindow.swift` | 试用欢迎、邮箱+卡密激活、找回（发邮件）、购买入口 |
| `LicenseSettingsView.swift` | 设置页“授权”区 |

**不做**：OTP、验证码、Ed25519 签名 token、独立授权后端。直接复用 Downie6 的服务端逻辑。

### 3. 试用 / 激活 / 设备 / 找回

- **试用**：首次启动 `POST /api/license/trial/start`（`product=launch`，设备指纹、设备名、平台、版本）；按 `(product_id, device_fp)` 记录 14 天。到期硬锁。首次启动需联网开始试用；无网时显示“联网开始试用 / 输入激活码”入口，不伪造本地试用。
- **激活**：输入邮箱 + 卡密 → `POST /api/license/activate`（`product=launch`）；服务端校验卡密属于 launch、邮箱匹配、设备槽位，绑定设备；客户端保存邮箱/卡密/状态。和 Downie6 完全一致，没有验证码。
- **设备管理**：`GET /api/license/status` 列出已绑设备，`POST /api/license/unbind` 解绑；和 Downie6 一致。
- **校验**：启动时 `POST /api/license/verify`，之后每 6 小时一次（照 Downie6）；`heartbeat` 刷新 `last_seen`。服务端不可达时用本地缓存 + 宽限（建议 7 天）；缓存过期则锁。
- **找回**：照搬 Downie6 的 `showRecoverLicenseDialog`：点“许可证代码丢失？”→ 打开邮件客户端，收件人 `huoyongzhuang@qq.com`，正文带购买邮箱；管理员在卡密页按邮箱搜索、核对、复制卡密或解绑旧设备。**不新增找回接口**。

### 4. 硬锁与门禁

- 启动：`LaunchpadApp.applicationDidFinishLaunching` 在 `setupWindow` 前加载 `LicenseManager`；试用过期且无有效授权时显示 `LicenseWindow`，不显示 launchpad。
- CLI/headless：`runHeadlessModeIfRequested()` 里校验；允许 `help/example/history/license`，阻止 `list/snapshot/search/create-folder/move/--tui`，退出码 3 + `LICENSE_REQUIRED`。
- 登录项静默启动不弹窗，但用户主动打开（热键/菜单栏）时进入授权窗口。
- 运行中每小时检查；到期立即锁并关闭 launchpad。
- 设置页：加“授权”section（非经典 + 经典），显示状态、剩余试用天数、邮箱、卡密（脱敏）、设备数；按钮：输入激活码、找回（邮件）、刷新、停用当前设备、购买。
- 本地化：`Localization.swift` 新增授权 key；先补 English / 简体中文 / 繁体中文，其他语言回退英文。

### 5. 自动更新

- `AppStore` 更新源从 GitHub 改为 `GET /api/version/latest?product=launch&platform=macos`；模型改为 `ReleaseManifest`（version/build/url/sha256/size/changelog/force）。
- `SwiftUpdater` 支持 `--feed-url`，下载时校验 SHA256，解压后校验 `codesign --verify --deep --strict`、TeamIdentifier `D4KD8XCCL6`、bundle id `com.roversx.launch`、`spctl --assess`；失败保留旧版本。
- 安装包同时出 ZIP（更新器用）和 DMG（新用户下载）。
- 发布：复用 `scripts/release-notarized.sh` 的构建/公证逻辑，新增 DMG 打包与签名/公证/staple；上传：
  - `launch/macos/<version>/launch-<version>.zip`
  - `launch/macos/<version>/launch-<version>.dmg`
  - `launch/macos/latest/launch.zip`
  - `launch/macos/latest/launch.dmg`
  - `launch/macos/latest.json`
  - 调用 `/api/internal/releases/publish`。

### 6. DMG 安装引导页（与 Downie6 一致）

Downie6 现有 DMG 布局在 `apps/desktop/macos/installer/`：

- 左侧 `安装说明.png`（`install-guide.png`）教程图；
- 右侧 `Downie6.app` + `Applications` 快捷方式；
- 背景图上方是软件标题/图标（`dmg-layout/.background/background.png`）；
- `.DS_Store` 控制图标位置，工作流用 `hdiutil create -volname "Downie6" ...` 生成。

launch 的 DMG 直接沿用这套结构，只换品牌和文案：

1. 新增 `launch/scripts/dmg/`：`background.png`（上方放 launch 标题 + 图标）、`install-guide.png`（左侧教程图）、`.DS_Store`（左侧教程、右侧 `launch.app` + `Applications` 的位置）。
2. 教程图内容：① 把 `launch.app` 拖到 Applications；② 首次打开如被拦截，右键打开/系统设置放行；③ 14 天试用或输入激活码；④ 找回/支持邮箱 `huoyongzhuang@qq.com`。
3. 打包：staging 目录放 `launch.app`、`安装说明.png`、`Applications` 符号链接、`.background`、`.DS_Store`；`hdiutil create -volname "launch" -srcfolder ... -format UDZO`。
4. DMG 签名 → 公证 → `stapler staple`；保留 `hdiutil verify`。
5. Downie6 现有 DMG 布局不改，只在签名/公证步骤中确保不破坏 `.DS_Store` 和背景图。

---

## 六、OSS 布局与版本

```text
oss://4kdownlebucket/
  downie6/macos/<version>/Downie6-<version>.dmg
  downie6/macos/latest/Downie6.dmg
  downie6/macos/latest.json
  downie6/windows/<version>/Downie6-Windows-Setup-<version>.exe
  downie6/windows/latest/Downie6-Windows-Setup.exe
  downie6/windows/latest.json
  launch/macos/<version>/launch-<version>.zip
  launch/macos/<version>/launch-<version>.dmg
  launch/macos/latest/launch.zip
  launch/macos/latest/launch.dmg
  launch/macos/latest.json
  releases/Downie6.dmg                 # 旧客户端兼容
  releases/Downie6-Windows-Setup.exe   # 旧客户端兼容
```

- 版本化路径：`Cache-Control: public,max-age=31536000,immutable`。
- `latest/` 和 `latest.json`：`no-cache`。
- Bucket 保持私有，仅这些前缀匿名只读；CI 用 RAM 子账号只授权对应前缀的 `PutObject/GetObject`。

`latest.json` 字段：`product/platform/version/build/url/sha256/size/changelog/force/published_at`。CI 上传后调用发布接口；客户端优先走 API，API 不可达时可直接读 OSS manifest。

---

## 七、网络与邮箱

- **网络**：launch 先复用 `http://8.153.99.239:3000`，与 Downie6 一致。URLSession 访问 HTTP 需要在 Info.plist 加 `NSAppTransportSecurity → NSAllowsArbitraryLoads = YES`（HTTP + IP 无法用 `NSExceptionDomains` 精确放行）。API base 放在 `LicenseConfig.swift` 一处；后续换 HTTPS 只改这里并去掉 ATS 例外。
- **邮箱**：不新增任何邮件服务。找回就是打开邮件客户端发到 `huoyongzhuang@qq.com`，与 Downie6 现在的 `showRecoverLicenseDialog` 完全一样；管理员用卡密页的搜索/设备详情人工处理。
- **注意**：邮箱没有验证码验证，和 Downie6 当前行为一致；拿到卡密的人可以绑定任意邮箱。这是用户明确要求的复用方案。

---

## 八、分阶段实施

| 阶段 | 内容 | 退出标准 |
|---|---|---|
| Phase R 改名 | Bundle ID、Xcode 工程/target/scheme、源码目录、产品 code、OSS 前缀、文案/README/i18n/网站、数据目录全部改 `launch`；数据迁移与旧版桥接方案 | 全新安装 + 旧数据迁移通过；`grep -ri launch` 无残留；构建/公证通过 |
| Phase 1 后端 | `products`、`licenses.product_id`、`device_bindings.product_id`、`trials`、`releases`；迁移脚本；license/version API 加 product；产品管理接口 | 旧 Downie6 v2.0.x 全流程通过；迁移可重复执行；产品隔离正确 |
| Phase 2 后台 | 卡密页加产品筛选/列、生成时选产品；新增产品管理页；菜单 | 按产品生成/筛选/导出；旧卡密页功能不回归 |
| Phase 3 launch 授权 | 移植 Downie6 授权逻辑：试用、激活、设备、verify/heartbeat、人工找回、硬锁、CLI/登录项门禁、设置/onboarding | 14 天试用、激活、设备限制、解绑、找回、硬锁、断网宽限全部通过 |
| Phase 4 Downie6 分发 | node 双架构、ARCHS/lipo 校验、签名/公证、版本化 OSS、发布接口 | Intel/ARM 真机启动；lipo 全绿；旧包仍可更新 |
| Phase 5 launch 分发 | DMG/ZIP、公证、OSS 上传、latest.json、SwiftUpdater 校验 | tag 全自动发布；客户端从 OSS 更新；SHA/签名错误被拒绝 |
| Phase 6 收尾 | 监控旧 3000 端口、文档、下载页、购买链接 | 两个产品可正常试用/激活/找回/更新 |

**顺序**：先改名，再后端产品维度，再后台，再 launch 授权，最后分发/更新。launch 硬锁上线必须晚于激活/设备/找回流程验证。

---

## 九、验证清单

1. **旧 Downie6 兼容**：安装 v2.0.52，`trial/start|status`、`activate`、`heartbeat`、`verify`、`unbind` 响应字段与旧版一致；旧 `/card/*` 不传 product 仍正常。
2. **迁移幂等**：空库 `init_db.py`；生产副本跑迁移两次，第二次无变更；`licenses.product_id=1`、`trials` 行数与 `trial_devices` 一致。
3. **产品隔离**：同一台 Mac 先开 Downie6 试用再开 launch，两个 `trial_end` 独立；launch 卡密在 Downie6 激活返回 `INVALID_CODE`。
4. **激活**：邮箱+卡密可激活；邮箱不匹配返回 `EMAIL_MISMATCH`；设备满返回 `DEVICE_LIMIT_REACHED`；重复激活幂等；解绑后名额恢复。
5. **人工找回**：点“许可证代码丢失”打开邮件到 `huoyongzhuang@qq.com`；后台按邮箱搜到卡密、看到设备、能解绑。
6. **硬锁**：把 `trial_end` 改到过去，重启后 launchpad 不可打开；CLI `list` 退出码 3；登录项静默启动不绕过。
7. **离线**：断网 7 天内可用；超过宽限锁定；联网后恢复；系统时间回拨触发重新校验。
8. **更新**：Downie6 从旧版检测到 OSS 新版；SHA 错误拒绝安装；launch ZIP 篡改/TeamID 不匹配拒绝；`latest.json` build 小于当前不提示。
9. **Universal**：`lipo -archs` 检查主程序、Flutter/App/Pods 框架、ffmpeg、yt-dlp、node；Intel 与 Apple Silicon 真机冷启动、下载、更新。
10. **公证**：`codesign --verify --deep --strict`、`spctl --assess`、`stapler validate`、`hdiutil verify` 全过。
11. **DMG 安装引导页**：挂载 launch.dmg，上方标题/图标正确，左侧教程图显示，右侧 `launch.app` + Applications 快捷方式可拖动安装；Downie6 DMG 布局无回归。
12. **后台**：按产品生成/筛选/导出；产品管理新增后卡密页立即出现；旧卡密页功能不回归。
13. **改名迁移**：全新安装 Bundle ID = `com.roversx.launch`；覆盖旧 launch 后布局/隐藏应用/图标/备份/下载历史迁移成功；TCC 重新授权；登录项重新注册。
14. **安全**：完整卡密不写日志；管理端限流；旧 3000 端口访问量可观测。

---

## 十、风险与待办

| 风险 | 影响 | 缓解 |
|---|---|---|
| 旧 Downie6 契约被破坏 | 已部署用户无法激活/更新 | product 默认 `downie6`、响应只增不减、契约测试、保留旧 OSS 路径 |
| `trial_devices` 迁移丢数据 | 老用户试用重置/500 | 迁移前备份；`INSERT IGNORE` 回填；保留旧表 |
| 在线 DDL 锁表 | 授权接口短时不可用 | `ALGORITHM=INSTANT/INPLACE`、低峰执行、备份、失败回滚 |
| 现有 SMTP 仅用于支持邮件 | 找回依赖人工，响应慢 | 按用户要求复用；后台按邮箱搜索/解绑；量大再评估自动化 |
| HTTP + ATS 例外 | 传输可被中间人篡改 | 短期可接受；正式售卖前切 HTTPS；更新包强制 SHA256 + 代码签名 |
| Downie6 未公证 | Gatekeeper 拦截 | 配置 Developer ID + notarytool；下载页说明 |
| node 双架构增大包体 | DMG 变大 | 先接受；后续评估按需下载或 universal node |
| Bundle ID 改名 | 旧 launch 用户无法静默升级；TCC/登录项失效 | 旧身份桥接版（需控制旧更新源）或手动下载说明；首次启动迁移数据 |
| launch 最低系统 macOS 26.0 | 只能覆盖能升到 macOS 26 的 Intel Mac | 若需更老 Intel，需下调 deployment target 并兼容 SwiftData/26+ API，属于额外大改 |
| launch GPL 源码公开 | 激活可被改源码绕过 | 用户已确认拥有版权；建议商业版仓库转私有，或接受开源绕过风险 |

**需要用户后续提供/确认**：Apple Developer ID 证书是否复用到 Downie6、launch 购买链接、是否最终上 HTTPS、是否还能向旧 `yongzhuanghuo/launch` 更新源发桥接版。

---

## 关键文件

**后端**
- `4KDownle/services/api/sql/schema.sql`、`init_all.sql`、`sql/migrations/`
- `4KDownle/services/api/app/modules/license/{models,service,router}.py`
- `4KDownle/services/api/app/modules/admin/routers/cards.py`
- `4KDownle/services/api/app/main.py`、`config.py`
- `4KDownle/services/api/scripts/init_db.py`

**管理后台**
- `4KDownle/apps/admin-web/src/views/card/index.vue`
- `4KDownle/apps/admin-web/src/api/card.ts`
- 新增 `4KDownle/apps/admin-web/src/views/product/index.vue`、`src/api/product.ts`
- 菜单：`init_db.py` 的 `MENUS` 与 `init_all.sql`

**Downie6 客户端**
- `apps/desktop/lib/core/platform/{binary_locator,binary_initializer}.dart`
- `apps/desktop/lib/core/version/{version_check,update_installer}.dart`
- `apps/desktop/.github/workflows/build.yml`
- `apps/desktop/macos/Runner/Configs/Release.xcconfig`、entitlements
- 新增 `apps/desktop/tools/verify_macos_archs.sh`

**launch**
- 新增 `launch/License/{LicenseConfig,DeviceIdentity,LicenseStore,LicenseAPI,LicenseManager,LicenseWindow,LicenseSettingsView}.swift`
- `launch/LaunchpadApp.swift`（启动门禁、CLI 门禁）
- `launch/AppStore.swift`（onboarding/更新源）
- `launch/SettingsView.swift`、`ClassicSettingsWindow.swift`、`LaunchpadView.swift`
- `launch/Localization.swift`
- `launch.xcodeproj/project.pbxproj`
- `UpdaterScripts/SwiftUpdater/Sources/SwiftUpdater/{Arguments,Config,SwiftUpdater,GitHubAPI,Downloader,Installer}.swift`
- `scripts/release-notarized.sh`、新增 `scripts/dmg/{background.png,install-guide.png,.DS_Store}`、`.github/workflows/release.yml`
- 参考 Downie6 现有 DMG 资产：`4KDownle/apps/desktop/macos/installer/`、`4KDownle/apps/desktop/tools/generate_installer_assets.swift`
