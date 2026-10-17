# AGENTS.md — qd-appt-backend（号源 QueueDepth 后端）

> 本文件是本仓库的项目级 Agent 说明：项目是什么、代码放在哪里、全局必须遵守什么、Agent 应如何工作。
> 业务规则的唯一权威在 `../docs/PRD.md`；实现方案的唯一权威在 `../docs/技术方案.md`；接口形态的唯一权威在 `../docs/api-contract.md`。
> 本文不重复展开业务规则与实现细节，只保留红线与入口。
> 与 ../docs/ 冲突时：业务规则以 PRD 为准、接口形态以契约为准、实现手段以技术方案为准；**冲突本身必须先报告，再由最新明确决定裁决**。
> ⚠️ `../docs/` 下的文件不会被 AI 工具自动加载——关键约束必须落在本文件（§4 红线全集），这是本文存在的理由。

---

## 1. 项目概述

- **号源 QueueDepth** · 医院门诊预约挂号系统后端仓（求职演示项目）。本仓由 **RuoYi-Vue-Plus 6.0.0 上游基线**导入（首条 commit 记录上游来源与 hash），框架提供鉴权 / 租户 / OSS / 代码生成器等基础设施，**业务模块 `appt` 全部自研**。
- 业务模块 `appt`：Java 包 `org.dromara.appt`，表前缀 `appt_`，API 前缀 `/appt/**`，Redis 命名空间 `appt:*`。
- 技术栈：Spring Boot 4.1 / JDK 21 / MyBatis-Plus / MySQL 8 / Redis + Redisson。**模块化单体，不上微服务；不用 MQ、不用 ES**（LIKE 足够）。
- 多租户：**本基线无任何 tenant 配置（默认关闭，已确认，无需改造）**。
- 框架自带 lock4j 分布式锁仅框架内部使用；业务侧号源占位 / 余量缓存 / 幂等键 / 定时任务锁按 §4 红线使用 `StringRedisTemplate` 与 Redisson，**不混用 lock4j 注解**。
- **合规声明**：全部数据虚构，不使用真实医院 / 科室 / 医务人员名称；不问诊不诊断不开放；支付仅 Mock 渠道。各端 README 必须带「技术演示 / 虚构数据 / 不提供医疗服务」声明。
- 与项目一（sd-blog 博客）**完全独立**，不复用其代码、仓库、数据（PRD D9）。

## 2. 模块与目录

| 项 | 值 |
|---|---|
| 业务模块目录 | `ruoyi-modules/appt` |
| 包结构 | `org.dromara.appt.{common, schedule, registration, payment, triage, account, reconcile, notice, job}` |
| Mapper XML | `ruoyi-modules/appt/src/main/resources/mapper/appt/` |
| 启动端口 | 8082（`ruoyi-admin/src/main/resources/application.yml`） |
| SpringDoc 分组 | `5.挂号业务模块`（packages-to-scan: org.dromara.appt） |
| 数据源 | MySQL 库 `appt`（utf8mb4_general_ci；复用现有 `blog-mysql` 容器，与项目一 `ry-vue` 库隔离） |
| Redis | database 1（复用现有 `blog-redis` 容器；key 命名空间 `appt:*`） |

**包职责**（技术方案 §1.2）：common 状态枚举/异常/Redis Key/Lua · schedule 院区科室人员模板排班号源 + 生成器 + 放号任务 · registration 挂号单/限购/黑名单 · payment 支付单/退款单/渠道抽象/Mock 渠道/回调/巡检 · triage 签到/加号/停诊上报 · account 就诊人/收藏 · reconcile 对账 · notice 站内信 · job 定时任务框架。

**三处 Maven 接入点**（模块增删必须同时改）：根 `pom.xml` 的 `<dependencyManagement>`、`ruoyi-modules/pom.xml` 的 `<modules>`、`ruoyi-admin/pom.xml` 的 `<dependencies>`。

- 不需要额外 ComponentScan / MapperScan：启动类扫描 `org.dromara`，Mapper 扫描 `org.dromara.**.mapper`。
- ⚠️ 新增业务模块或改包名后，检查 `application.yml` 的 `springdoc.group-configs` 是否覆盖 `org.dromara.appt`——漏配则接口不出现在 API 文档。

## 3. 信息源优先级与编码规范

实现功能时的取样顺序：

1. 当前仓库真实源码（同模块最近似实现优先）
2. `../docs/` 设计文档
3. 当前锁定版本（RuoYi-Vue-Plus 6.0.0）的官方资料
4. 通用框架知识 / 旧版 RuoYi 教程（最低，**禁止照搬**）

RuoYi 已有基础设施（用户 / 认证 / RBAC / 数据权限 / OSS / 字典 / 日志 / SpringDoc / 代码生成器）优先复用，不重复实现，除非需求明确要求。

冲突时优先相信当前模块真实代码和实际调用点，其次公共基础设施，最后生成器模板。

## 4. 领域红线（任何时刻不可违反）

> 以下 17 条与 `../docs/redlines.md` 逐字一致（条目末尾的【后端】/【公共】标记是 redlines.md 的建仓分仓拆分标注，本仓持有全集）。

1. **`time_point` 必须显式落库**，禁止用「起始时间 + 固定步长」现算（实测间隔 4 / 56 / 67 / 10 分钟都出现过，且被占用的时间点直接从列表消失）。【后端】
2. **一个 Slot = 一个号，没有容量计数器**；Redis 只承担互斥与快速失败，不承担计数。【后端】
3. **三道防线顺序不可省**：Redis `setIfAbsent` 占位（优化层，可摘除）→ DB 行级 CAS（真相层）→ 唯一索引（兜底层）。号源争抢降级时正确性不降。【后端】
4. **禁止对 `registration.slot_id` 建单列唯一索引**（与回池复用冲突，集成测试②必失败，M1）。有效行唯一性用 `UNIQUE(slot_id, active_flag)`：active_flag=1 有效、终态置 NULL（MySQL 唯一索引 NULL 互不冲突）。限购复合规则同理：`(patient_id, dept_id, visit_date, active_flag)`、`(patient_id, time_point, active_flag)`。【后端】
5. **金额快照**：`registration.fee` 挂号时从 slot 快照，支付/退款一律以它为准；`fee_standard` 变更不追溯已生成号源。【后端】
6. **两套状态标签严禁混用**：科室排班页只有「有排班/无排班」；医生主页只有「满诊/无号」。【公共】
7. **回调必须真异步**：验签 → 落 `appt_payment_callback` → ack → 异步入账。mock 与真实渠道共用同一 `PaymentCallbackDispatcher`，差异只在 `PaymentChannel` 适配器。**「钱到了号没了」（回调晚于关单）必须走自动退款 + 告警，不是返回成功就算了。**【后端】
8. **退款规则**：停诊 / 主动退号 / 重复支付 / 对账漏退 → 自动全额退；**爽约不退**；超时未支付不涉及退款且不计黑名单。停诊被动退号不计爽约。【后端】
9. **退号回池**时若 `time_point` 已过 → 置「已过期」而非「可约」；回池后余量缓存同步递增（先 DB 后缓存）。【后端】
10. **服务端强制校验权限与限购，不信任前端任何判断**；四层 API 边界（public / patient / triage / admin）不混用。【公共】
11. **所有状态流转必须经 `*StateService` 单柱**（合法性校验 + 条件 CAS + 台账），禁止任何路径绕过它直接 UPDATE 状态列——这是缓存一致性与对账可审计的根基。【后端】
12. **停诊 / 退款等批量操作**：带批号、CAS 守卫、分批事务（≤100/批），避免长事务。【后端】
13. **定时任务**：Redisson `tryLock(0, -1)`（拿不到跳过本轮并记日志）+ `appt_job_log` 批号 + 启动补偿检查；爽约/过期扫描必须带全量兜底（半开窗口会漏判，M2）。【后端】
14. **限购「同时持有 ≤3」与黑名单统计按账号（user_id）口径**（M13，防黄牛意图）；挂号事务内账号行 `FOR UPDATE` 串行化（M3）。【后端】
15. **PII**：身份证/就诊卡号演示数据可明文，代码预留加密接口位，日志禁止打印证件号（M11）。【公共】
16. **明确不做**（被问及时按「为什么不上」回答，不主动实现）：候补队列、改约、真实渠道签约、医保、问诊/开方/药品、检查治疗预约、报告/账单/地址/评价、多医院、ES、微服务、MQ（PRD §1.4 / §13.2）。【公共】
17. **命名纪律（PRD D10）**：简历用中文名「号源」；仓库 / README 用英文代号 QueueDepth；**演示 UI 仅中文 + 虚构医院名，不得出现 QueueDepth 或任何英文代号**；代码层缩写统一 `appt`（表前缀 `appt_` / 包 `org.dromara.appt` / API `/appt/**` / Redis `appt:*`）。【公共】

## 5. 分层与事务

- Controller：接参、校验、权限入口、调用 Service、返回 `R<T>`；不堆复杂业务。
- Service：业务规则、状态转换（**必须经 `*StateService` 单柱**）、业务权限判断、事务边界、跨表协调。
- 四层 API 边界通过 Controller 划分（`/appt/public|patient|triage|admin`），多个 Controller 可复用同一领域 Service。
- 多表原子操作显式 `@Transactional(rollbackFor = Exception.class)`，典型场景：挂号（账号行锁 → 插入挂号单 → slot CAS → 支付单）、关单三步 CAS、退号 + 退款单、停诊分批流转。
- 不要机械地给所有 Service 方法加事务。
- 跨模块（schedule / registration / payment / triage / account / reconcile / notice / job）**仅通过 Service 接口交互，禁止跨模块 Mapper 联表**；对账等需要多方数据的场景由调用方分别取数在内存关联。

## 6. 代码生成器原则与已验证坑

Generator 定位是生成 RuoYi 风格骨架，不是完成业务。Entity/BO/VO/Mapper/Service/Controller/基础 CRUD 可生成；状态机、权限校验、业务规则必须生成后按契约改造，**不要让 Generator 默认 CRUD 反过来决定业务设计**。

已验证的坑（务必遵守）：

- 生成器字段配置里，主键列必须勾选「查询」：BO 模板只为勾选了「查询/新增/修改」的列生成字段，而 ServiceImpl 模板无条件引用主键回填，漏勾会直接编译错误。
- 导入表时 `packageName` 填 `org.dromara.appt`、`moduleName` 填 `appt`。
- 生成只支持下载 zip，需人工解压放入模块；菜单 SQL 需手动执行。
- 修改表结构后先用「同步」功能刷新字段配置再重新生成。
- 管理端实体端点路径与 public 层对齐（`dept` / `staff` / `slot` / `campus` / `clinicType` / `feeStandard` / `slotTemplate`），不沿用生成器默认命名。

## 7. 构建与排障

- 构建只在 `backend/` 仓内执行，**不在父目录跑 `mvn`**（父目录不受 .gitignore 保护，游离产物长期残留）。
- 环境：WSL2 Ubuntu；JDK 21 / Maven 由 sdkman 管理，非交互 shell 需先 `source "$HOME/.sdkman/bin/sdkman-init.sh"`。
- 任何代码修改后至少验证：Maven 构建通过、`ruoyi-admin` 可启动、涉及 API 可访问、权限边界正确、关键数据库状态正确。
- **mapstruct-plus 的转换器类是编译期生成的**：运行时报 `ConvertException: cannot find converter` 大概率不是代码问题，而是增量编译与 Maven 产物混用导致生成类缺失——先 `mvn clean` 全量重编，再排查源码。
- **`mvn clean compile` 全量构建有间歇性竞态失败（实测约 70% 失败率）**：表现为随机文件 `error reading target/generated-sources/annotations/**/*MapperImpl.java`（集中在首个 mapstruct 重模块 ruoyi-system；失败后文件本身完好，属瞬时读失败）。根因判断：Lombok + mapstruct-plus + lombok-mapstruct-binding 注解处理栈与 javac 读生成文件的时序竞态；**项目一未踩到是因为其构建走 IDEA 增量编译而非全量 clean build**。**做法：重试至多 5 次**（`for i in 1..5; do mvn clean compile > build.log 2>&1 && break; done`，已实测重试第 1 次即过）；IDE 内增量构建不受影响。已排除：磁盘空间 / fd 上限 / 文件权限 / 增量编译开关 / maven-compiler-plugin 版本（3.13.0 同样失败，已回退上游 3.15.0）/ `-q` 标志（与失败的相关性为巧合）/ 宿主盘余量（D 盘 108G）。若失败率恶化或 CI 需要确定性构建，优先排查 mapstruct-plus-processor 升级。
- 复制模块目录不要带上 `target/` 残留；模块改名后必须 clean。
- IDEA Maven 同步报错（未解析插件等）时，先对齐 IDEA 与命令行的 Maven home / settings.xml，再判断是不是代码问题。

## 8. 认证链路（RuoYi-Vue-Plus 6.0.0 实测，2026-10-18 冒烟验证）

与旧版 RuoYi 差异很大，接入 / 调试 / 写冒烟时必读：

- **登录端点**：`POST /auth/login`（AuthController 类级 `@RequestMapping("/auth")`，不是旧版的 `/login`）。请求体 `{clientId, grantType, username, password}`——`clientId` + `grantType` 必须匹配 `sys_client` 种子（本地库 `e5cd7e4891bf95d1d19206ce24a7b32e`，grant_type=`password,social`），否则报客户端认证异常。
- **`@ApiEncrypt` 与 api-decrypt**：`api-decrypt.enabled=true` 是上游默认且**已确认保持**（项目一同款决策）。开启时 CryptoFilter（`@ConditionalOnProperty(api-decrypt.enabled=true)` 注册，urlPatterns `/*` 最高优先级）对 POST/PUT：带 `encrypt-key` 请求头 → 按配置 RSA 私钥解密 body；**不带头且方法带 `@ApiEncrypt`（如 /auth/login）→ 直接 403**。响应默认不加密（`@ApiEncrypt.response()` 默认 false）。本地调试走明文：启动参数 `--api-decrypt.enabled=false`（仅本进程生效，**勿改配置文件**）。
- **认证请求双头**：`Authorization: Bearer <token>`（`token-prefix: Bearer` 配在 `ruoyi-common/ruoyi-common-satoken/src/main/resources/common-satoken.yml`，不在 application.yml）+ `clientid: <clientId>`。SecurityConfig 比对请求头/参数里的 clientid 与 token 内嵌值，**缺 clientid 头 → 401「客户端ID与Token不匹配」**。前端 `admin/src/utils/request.ts` 用 `axios.defaults.headers['clientid']` 统一注入，接口联调时勿忘。
- **登录响应结构（2026-10-18 实测）**：`R<LoginVo>` → `{code:200, msg, data:{access_token, expire_in, client_id, refresh_token, ...}}`。`LoginVo` 逐字段 `@JsonProperty`，**data 内是蛇形**，且 **token 在 `data.access_token`、不在顶层**；框架无全局命名策略，其余响应仍是标准**驼峰**——契约 §2 的驼峰约定不变，勿被登录响应带偏。
- **前后端加密对齐（2026-10-18 端到端实测通过）**：admin 侧 `.env.development` 的 `VITE_APP_ENCRYPT` 与后端 `api-decrypt.enabled` **必须同开同关**，默认都是 true。加密方案（见 `admin/src/utils/crypto.ts` + `jsencrypt.ts`，写联调脚本时照抄）：随机 32 字符 AES-256 key → 请求头 `encrypt-key` = RSA(公钥, base64(key))，body = base64(AES/ECB/PKCS7(JSON))；仅当请求头 `isEncrypt: 'true'` **且** 方法为 POST/PUT 时才加密。响应默认不加密（`@ApiEncrypt.response()` 默认 false）。开关错配的表现：前端开后端关 → 后端收到密文、JSON 解析失败；前端关后端开 → 带 `@ApiEncrypt` 的接口直接 403。
- **当前登录信息**：`GET /system/user/getInfo`（SysUserController 类级 `/system/user`，不在 /auth 下）。
- **验证码**：`captcha.enable=true` 默认开；本地调试启动参数 `--captcha.enable=false`。
- **已验证的冒烟（两条）**：
  1. **明文**（省事）：`java -jar ruoyi-admin/target/ruoyi-admin.jar --spring.profiles.active=dev --captcha.enable=false --api-decrypt.enabled=false` → POST /auth/login → 带双头 GET /system/user/getInfo → GET /v3/api-docs/{分组}。
  2. **全链路加密**（贴近真实，2026-10-18 全绿）：后端默认配置（captcha + api-decrypt 都开）→ admin `VITE_APP_PORT=8081 pnpm dev` → 经 vite 代理 `/dev-api` 走完 验证码 → RSA+AES 加密登录 → 双头 getInfo → SpringDoc 分组。

---

## 9. 测试策略

- **单元测试只覆盖纯逻辑**（不碰数据库、不起 Spring 容器）：状态机流转、爽约网格覆盖、限购计数、号源生成器（起止 + 步长 → 时间点序列）、对账七查判定。这些逻辑必须实现为独立可测类，不得揉进 ServiceImpl 大方法。
- CRUD / HTTP 链路不写 Java 单测，由 Apifox 用例覆盖（正向 / 鉴权失败 / 参数校验 / 资源不存在 / 越权）；Controller 层不做 mock 测试。
- 关键链路集成测试三条（PRD §12）：① 50 并发争抢同一时间点仅 1 笔成功 ② 超时关单 → 号源回补 → 可被再次预约 ③ 支付回调重复 3 次仅入账 1 次。
- 单测与被测代码同模块 `src/test/java`，依赖根 pom 统一的 spring-boot-starter-test（JUnit5 + Mockito）。

## 10. 安全红线

- 不信任前端传入的 `userId` / `patientId` / 权限字段 / 关键状态字段；数据归属与操作权限必须由后端按当前登录用户强制校验，隔离靠服务端过滤而非前端隐藏按钮。
- PII（身份证 / 就诊卡号）：日志禁止打印；列表与详情响应脱敏；存储预留加密接口位（红线 15）。
- 公共接口不得泄露非公开数据；不匹配归属的资源按「不存在」处理，不泄露存在性。
- 不提交或硬编码真实生产 Token、密码、密钥、数据库凭据；本地测试配置不得改变生产安全策略。

## 11. Agent 工作流

中大型 Feature 遵循：

```text
阅读 ../docs/ 相关文档 → 阅读当前真实源码 → 寻找同类实现
→ 只读分析 + 实施计划 → 修改代码 → 编译 → 测试 → Review → Git commit
```

- 一次只实现一个明确 Feature，一个 feature 一个小步 commit；修改代码前建立 Git checkpoint；不要让两个 Agent 同时修改同一工作区；关键权限 / 删除逻辑人工复核。
- 一次 Agent 会话原则上只动**一个仓库**：跨仓联调拆成多步、各自独立提交。
- 发现设计与现有代码冲突时，先明确指出冲突，不要默默改变设计；文档冲突时先识别冲突并报告，由最新明确决定裁决。
- MVP 范围与「明确不做」清单以 PRD §1.4 / §13 为准（§4 红线 16），除需求文档明确加入外不主动实现。
- 新会话上下文组织顺序：本文件全文 → `../docs/README.md` 阅读顺序 → PRD §14 决策记录 → 技术方案对应章节。

## 12. 参考文档

| 文档（相对路径） | 内容 |
|---|---|
| `../docs/PRD.md` | 业务规则 / 状态机 / 接口清单 / 非功能 / 决策记录（产品视角唯一权威，v0.5） |
| `../docs/技术方案.md` | 六难点实现方案 / 核心不变量 / 对账 / 配置 / 索引（实现视角唯一权威，v0.3） |
| `../docs/api-contract.md` | API 契约：四层边界、端点条目、错误码、状态边界矩阵（接口形态唯一权威，v0.1） |
| `../docs/redlines.md` | 红线全集（本文件 §4 的来源，改红线必须同步） |
| `../docs/README.md` | 文档地图与阅读顺序 |

---

> 维护备注：本文 §4 红线与 `../docs/redlines.md` 逐字一致；改任何一条红线，同步 redlines.md、PRD（若涉业务语义）、技术方案（若涉实现手段），三者不一致时以「最新明确决定」裁决并互相回写。
