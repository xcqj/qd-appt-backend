-- ============================================================
-- 号源 QueueDepth · 业务表结构（appt_schema.sql）
--
-- 权威设计文档：qd-appt-docs/database-design.md（字段级唯一权威）
-- 上游：PRD §4.2 / §14.5（M1-M13）· 技术方案 §2（I1-I8）/ §6.1 / §6.2 · API 契约 §2.4 / §2.7
--
-- 执行顺序（在 appt 库上）：
--   1) script/sql/ry_vue.sql          （框架系统表）
--   2) script/sql/appt_schema.sql     （本文件，业务表）
--   3) script/sql/appt_s0_cleanup.sql （演示数据清理）
--
-- 约定（database-design.md §1）：
--   - utf8mb4 / utf8mb4_general_ci
--   - 主键 bigint 雪花（mybatis-plus idType: ASSIGN_ID），不自增
--   - 公共字段五件套，无 del_flag（终态用 status + active_flag 表达）
--   - 契约涉及的状态 = varchar 线值；纯后台启停 = char(1) '0'正常/'1'停用
--   - 金额 decimal(10,2)；时间 datetime；不建外键；不用 @Version（统一条件 CAS）
-- ============================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- 1. 基础数据域
-- ----------------------------

-- ---------- 院区
DROP TABLE IF EXISTS `appt_campus`;
CREATE TABLE `appt_campus` (
  `id`          bigint       NOT NULL COMMENT '主键（雪花）',
  `name`        varchar(64)  NOT NULL COMMENT '院区名（虚构，PRD §11 红线）',
  `address`     varchar(255) DEFAULT NULL COMMENT '地址',
  `cover_url`   varchar(255) DEFAULT NULL COMMENT '封面图（占位图）',
  `sort`        int          DEFAULT NULL COMMENT '排序',
  `status`      char(1)      NOT NULL DEFAULT '0' COMMENT '状态：0正常 1停用',
  `create_dept` bigint       DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint       DEFAULT NULL COMMENT '创建者',
  `create_time` datetime     DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint       DEFAULT NULL COMMENT '更新者',
  `update_time` datetime     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_campus_status_sort` (`status`, `sort`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '院区';

-- ---------- 门诊类型
DROP TABLE IF EXISTS `appt_clinic_type`;
CREATE TABLE `appt_clinic_type` (
  `id`          bigint      NOT NULL COMMENT '主键',
  `code`        varchar(32) NOT NULL COMMENT '类型码：NORMAL普通 NIGHT夜间延时 EXPERT知名专家',
  `name`        varchar(64) NOT NULL COMMENT '类型名',
  `sort`        int         DEFAULT NULL COMMENT '排序',
  `status`      char(1)     NOT NULL DEFAULT '0' COMMENT '状态：0正常 1停用',
  `create_dept` bigint      DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint      DEFAULT NULL COMMENT '创建者',
  `create_time` datetime    DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint      DEFAULT NULL COMMENT '更新者',
  `update_time` datetime    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_clinic_type_code` (`code`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '门诊类型';

-- ---------- 科室三级树（全局统一，不挂院区）
DROP TABLE IF EXISTS `appt_department`;
CREATE TABLE `appt_department` (
  `id`          bigint      NOT NULL COMMENT '主键',
  `parent_id`   bigint      NOT NULL DEFAULT 0 COMMENT '父级id（根节点为0）',
  `name`        varchar(64) NOT NULL COMMENT '科室名（虚构，PRD §11 红线）',
  `level`       tinyint     NOT NULL COMMENT '层级：1/2/3',
  `sort`        int         DEFAULT NULL COMMENT '排序',
  `status`      char(1)     NOT NULL DEFAULT '0' COMMENT '状态：0正常 1停用',
  `create_dept` bigint      DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint      DEFAULT NULL COMMENT '创建者',
  `create_time` datetime    DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint      DEFAULT NULL COMMENT '更新者',
  `update_time` datetime    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_dept_parent_sort` (`parent_id`, `sort`),
  KEY `idx_dept_level_status` (`level`, `status`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '科室三级树（全局）';

-- ---------- 医务人员
DROP TABLE IF EXISTS `appt_medical_staff`;
CREATE TABLE `appt_medical_staff` (
  `id`          bigint        NOT NULL COMMENT '主键',
  `campus_id`   bigint        NOT NULL COMMENT '所属院区（单值；跨院区出诊为已知边界 PRD §14.3 / M7）',
  `dept_id`     bigint        NOT NULL COMMENT '所属科室（叶子节点）',
  `name`        varchar(64)   NOT NULL COMMENT '姓名（虚构）',
  `avatar`      varchar(255)  DEFAULT NULL COMMENT '头像（占位图）',
  `title`       varchar(32)   NOT NULL COMMENT '职称：CHIEF主任医师 ASSOC_CHIEF副主任医师 ATTENDING主治医师 PHYSICIAN医师',
  `degree`      varchar(64)   DEFAULT NULL COMMENT '学位',
  `type`        varchar(16)   NOT NULL DEFAULT 'DOCTOR' COMMENT '类型：DOCTOR医生 NURSE护士',
  `intro`       varchar(2000) DEFAULT NULL COMMENT '简介',
  `sort`        int           DEFAULT NULL COMMENT '排序',
  `status`      char(1)       NOT NULL DEFAULT '0' COMMENT '状态：0正常 1停用',
  `create_dept` bigint        DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint        DEFAULT NULL COMMENT '创建者',
  `create_time` datetime      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint        DEFAULT NULL COMMENT '更新者',
  `update_time` datetime      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_staff_dept_status` (`dept_id`, `status`),
  KEY `idx_staff_campus_dept` (`campus_id`, `dept_id`, `status`),
  KEY `idx_staff_name` (`name`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '医务人员';

-- ---------- 医生收藏
DROP TABLE IF EXISTS `appt_staff_favorite`;
CREATE TABLE `appt_staff_favorite` (
  `id`          bigint   NOT NULL COMMENT '主键',
  `user_id`     bigint   NOT NULL COMMENT '账号id（sys_user）',
  `staff_id`    bigint   NOT NULL COMMENT '医务人员id',
  `create_dept` bigint   DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint   DEFAULT NULL COMMENT '创建者',
  `create_time` datetime DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint   DEFAULT NULL COMMENT '更新者',
  `update_time` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_favorite_user_staff` (`user_id`, `staff_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '医生收藏（唯一键为 database-design.md 补齐）';

-- ---------- 时段模板
DROP TABLE IF EXISTS `appt_slot_template`;
CREATE TABLE `appt_slot_template` (
  `id`           bigint      NOT NULL COMMENT '主键',
  `staff_id`     bigint      NOT NULL COMMENT '医务人员id',
  `period`       varchar(16) NOT NULL COMMENT '午别：AM上午 PM下午 NIGHT夜间',
  `clinic_type`  varchar(32) NOT NULL COMMENT '门诊类型码',
  `start_time`   time        NOT NULL COMMENT '起始时刻',
  `end_time`     time        NOT NULL COMMENT '结束时刻',
  `step_minutes` int         NOT NULL COMMENT '步长（分钟）：4 / 5~6 / 6~7 / 10 均会出现（PRD §4.2-1）',
  `status`       char(1)     NOT NULL DEFAULT '0' COMMENT '状态：0正常 1停用',
  `create_dept`  bigint      DEFAULT NULL COMMENT '创建部门',
  `create_by`    bigint      DEFAULT NULL COMMENT '创建者',
  `create_time`  datetime    DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`    bigint      DEFAULT NULL COMMENT '更新者',
  `update_time`  datetime    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_template_staff_period_type` (`staff_id`, `period`, `clinic_type`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '时段模板（无容量字段，生成量由时长/步长决定 PRD §4.2-4）';

-- ---------- 收费标准
DROP TABLE IF EXISTS `appt_fee_standard`;
CREATE TABLE `appt_fee_standard` (
  `id`          bigint        NOT NULL COMMENT '主键',
  `title`       varchar(32)   NOT NULL COMMENT '职称线值',
  `clinic_type` varchar(32)   NOT NULL COMMENT '门诊类型码',
  `fee`         decimal(10,2) NOT NULL COMMENT '挂号费',
  `status`      char(1)       NOT NULL DEFAULT '0' COMMENT '状态：0正常 1停用（2026-10-18 补）',
  `create_dept` bigint        DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint        DEFAULT NULL COMMENT '创建者',
  `create_time` datetime      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint        DEFAULT NULL COMMENT '更新者',
  `update_time` datetime      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_fee_title_type` (`title`, `clinic_type`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '收费标准（UNIQUE(title, clinic_type)，PRD §4.2-5）';

-- ----------------------------
-- 2. 排班与号源域
-- ----------------------------

-- ---------- 排班
DROP TABLE IF EXISTS `appt_schedule`;
CREATE TABLE `appt_schedule` (
  `id`          bigint      NOT NULL COMMENT '主键',
  `staff_id`    bigint      NOT NULL COMMENT '医务人员id',
  `dept_id`     bigint      NOT NULL COMMENT '科室id',
  `campus_id`   bigint      NOT NULL COMMENT '院区id（冗余自 staff，供停诊按院区筛选）',
  `clinic_type` varchar(32) NOT NULL COMMENT '门诊类型码',
  `visit_date`  date        NOT NULL COMMENT '就诊日期',
  `period`      varchar(16) NOT NULL COMMENT '午别：AM/PM/NIGHT',
  `status`      varchar(16) NOT NULL DEFAULT 'NORMAL' COMMENT 'NORMAL正常 SUSPENDED已停诊',
  `create_dept` bigint      DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint      DEFAULT NULL COMMENT '创建者',
  `create_time` datetime    DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint      DEFAULT NULL COMMENT '更新者',
  `update_time` datetime    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_schedule_staff_date_period` (`staff_id`, `visit_date`, `period`),
  KEY `idx_schedule_date_status` (`visit_date`, `status`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '排班（稀疏，PRD §11）';

-- ---------- 号源（一个 Slot = 一个号）
DROP TABLE IF EXISTS `appt_slot`;
CREATE TABLE `appt_slot` (
  `id`              bigint        NOT NULL COMMENT '主键',
  `schedule_id`     bigint        NOT NULL COMMENT '排班id',
  `staff_id`        bigint        NOT NULL COMMENT '医务人员id（冗余 D-S1-2，服务余量聚合 §3.2）',
  `dept_id`         bigint        NOT NULL COMMENT '科室id（冗余）',
  `campus_id`       bigint        NOT NULL COMMENT '院区id（冗余）',
  `visit_date`      date          NOT NULL COMMENT '就诊日期（冗余，与 time_point 日期部分一致）',
  `period`          varchar(16)   NOT NULL COMMENT '午别（冗余）',
  `time_point`      datetime      NOT NULL COMMENT '就诊时刻（完整 datetime；对外按契约 §2.4 输出 HH:mm）',
  `fee`             decimal(10,2) NOT NULL COMMENT '挂号费（生成时快照 I2，fee_standard 变更不追溯）',
  `status`          varchar(16)   NOT NULL DEFAULT 'AVAILABLE' COMMENT 'AVAILABLE可约 TAKEN已占 SUSPENDED已停诊 EXPIRED已过期',
  `source`          varchar(16)   NOT NULL DEFAULT 'NORMAL' COMMENT '来源：NORMAL正常 EXTRA加号',
  `registration_id` bigint        DEFAULT NULL COMMENT '占用挂号单id（占用回写、回池置 NULL；I1 CAS 目标列）',
  `create_dept`     bigint        DEFAULT NULL COMMENT '创建部门',
  `create_by`       bigint        DEFAULT NULL COMMENT '创建者',
  `create_time`     datetime      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`       bigint        DEFAULT NULL COMMENT '更新者',
  `update_time`     datetime      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_slot_schedule_time` (`schedule_id`, `time_point`),
  KEY `idx_slot_time_status` (`time_point`, `status`),
  KEY `idx_slot_staff_date_period` (`staff_id`, `visit_date`, `period`, `status`),
  KEY `idx_slot_schedule_status` (`schedule_id`, `status`),
  KEY `idx_slot_registration` (`registration_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '号源（一行为一个号）';

-- ---------- 号源台账（append-only）
DROP TABLE IF EXISTS `appt_slot_ledger`;
CREATE TABLE `appt_slot_ledger` (
  `id`              bigint      NOT NULL COMMENT '主键',
  `slot_id`         bigint      NOT NULL COMMENT '号源id',
  `action`          varchar(16) NOT NULL COMMENT 'GENERATE生成 OCCUPY占用 RELEASE释放 REFILL回补 SUSPEND停诊 EXPIRE过期',
  `before_status`   varchar(16) DEFAULT NULL COMMENT '变更前状态（生成时为空）',
  `after_status`    varchar(16) NOT NULL COMMENT '变更后状态',
  `registration_id` bigint      DEFAULT NULL COMMENT '关联挂号单id',
  `batch_no`        varchar(32) DEFAULT NULL COMMENT '任务批号（批量操作倒查）',
  `create_dept`     bigint      DEFAULT NULL COMMENT '创建部门',
  `create_by`       bigint      DEFAULT NULL COMMENT '创建者',
  `create_time`     datetime    DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`       bigint      DEFAULT NULL COMMENT '更新者',
  `update_time`     datetime    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_ledger_slot_time` (`slot_id`, `create_time`),
  KEY `idx_ledger_batch` (`batch_no`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '号源台账（append-only，对账倒查 §3.6）';

-- ----------------------------
-- 3. 交易域
-- ----------------------------

-- ---------- 挂号单
DROP TABLE IF EXISTS `appt_registration`;
CREATE TABLE `appt_registration` (
  `id`                bigint        NOT NULL COMMENT '主键',
  `registration_no`   varchar(32)   NOT NULL COMMENT '挂号单号：R + yyyyMMdd + 6位当日序列（D-S1-4）',
  `user_id`           bigint        NOT NULL COMMENT '账号id（sys_user）；限购与黑名单均按 user_id 统计（M13）',
  `patient_id`        bigint        NOT NULL COMMENT '就诊人id',
  `slot_id`           bigint        NOT NULL COMMENT '号源id',
  `staff_id`          bigint        NOT NULL COMMENT '医务人员id（冗余快照）',
  `dept_id`           bigint        NOT NULL COMMENT '科室id（冗余快照）',
  `campus_id`         bigint        NOT NULL COMMENT '院区id（冗余快照）',
  `visit_date`        date          NOT NULL COMMENT '就诊日期（冗余快照）',
  `period`            varchar(16)   NOT NULL COMMENT '午别（冗余快照）',
  `time_point`        datetime      NOT NULL COMMENT '就诊时刻（冗余快照，完整 datetime）',
  `fee`               decimal(10,2) NOT NULL COMMENT '挂号费金额快照（I2）',
  `active_flag`       tinyint(1)    DEFAULT NULL COMMENT '1=有效 / NULL=终态；三条联合唯一索引的列（M1）',
  `settle_status`     varchar(16)   NOT NULL DEFAULT 'NONE' COMMENT 'NONE无结算 WAIT_REFUND待退费 REFUNDED已退费',
  `status`            varchar(16)   NOT NULL COMMENT 'WAIT_PAY待支付 BOOKED已预约 SIGNED已签到 COMPLETED已完成 CLOSED已关闭 CANCELED_ACTIVE已退号(主动) CANCELED_PASSIVE已退号(被动) NOSHOW已爽约',
  `sign_time`         datetime      DEFAULT NULL COMMENT '签到时间',
  `cancel_type`       varchar(16)   DEFAULT NULL COMMENT 'ACTIVE主动 PASSIVE被动',
  `suspend_batch_no`  varchar(32)   DEFAULT NULL COMMENT '停诊批号（批量流转幂等 I7）',
  `create_dept`       bigint        DEFAULT NULL COMMENT '创建部门',
  `create_by`         bigint        DEFAULT NULL COMMENT '创建者',
  `create_time`       datetime      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`         bigint        DEFAULT NULL COMMENT '更新者',
  `update_time`       datetime      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_reg_no` (`registration_no`),
  UNIQUE KEY `uk_reg_slot_active` (`slot_id`, `active_flag`),
  UNIQUE KEY `uk_reg_patient_dept_date` (`patient_id`, `dept_id`, `visit_date`, `active_flag`),
  UNIQUE KEY `uk_reg_patient_time` (`patient_id`, `time_point`, `active_flag`),
  KEY `idx_reg_user_status` (`user_id`, `status`),
  KEY `idx_reg_status_time` (`status`, `time_point`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '挂号单';

-- ---------- 支付单
DROP TABLE IF EXISTS `appt_payment`;
CREATE TABLE `appt_payment` (
  `id`              bigint        NOT NULL COMMENT '主键',
  `payment_no`      varchar(32)   NOT NULL COMMENT '支付单号：P + yyyyMMdd + 6位当日序列',
  `registration_id` bigint        NOT NULL COMMENT '挂号单id',
  `amount`          decimal(10,2) NOT NULL COMMENT '支付金额（= registration.fee，I2）',
  `channel`         varchar(16)   NOT NULL DEFAULT 'MOCK' COMMENT '渠道：本期仅 MOCK（PRD §12）',
  `status`          varchar(16)   NOT NULL DEFAULT 'WAIT_PAY' COMMENT 'WAIT_PAY待支付 PAID已支付 CLOSED已关闭 REFUNDED已退款',
  `trade_no`        varchar(64)   DEFAULT NULL COMMENT '渠道流水号',
  `expire_time`     datetime      NOT NULL COMMENT '支付截止时间（创建时间 + 15 分钟，PRD §14.2-3）',
  `pay_time`        datetime      DEFAULT NULL COMMENT '支付完成时间',
  `create_dept`     bigint        DEFAULT NULL COMMENT '创建部门',
  `create_by`       bigint        DEFAULT NULL COMMENT '创建者',
  `create_time`     datetime      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`       bigint        DEFAULT NULL COMMENT '更新者',
  `update_time`     datetime      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_pay_no` (`payment_no`),
  KEY `idx_pay_status_expire` (`status`, `expire_time`),
  KEY `idx_pay_registration` (`registration_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '支付单';

-- ---------- 退款单
DROP TABLE IF EXISTS `appt_refund`;
CREATE TABLE `appt_refund` (
  `id`              bigint        NOT NULL COMMENT '主键',
  `refund_no`       varchar(32)   NOT NULL COMMENT '退款单号：F + yyyyMMdd + 6位当日序列',
  `payment_id`      bigint        NOT NULL COMMENT '支付单id',
  `registration_id` bigint        NOT NULL COMMENT '挂号单id',
  `amount`          decimal(10,2) NOT NULL COMMENT '退款金额',
  `status`          varchar(16)   NOT NULL DEFAULT 'WAIT_REFUND' COMMENT 'WAIT_REFUND待退款 REFUNDED已退款',
  `reason`          varchar(255)  DEFAULT NULL COMMENT '退款原因',
  `refund_time`     datetime      DEFAULT NULL COMMENT '退款完成时间',
  `create_dept`     bigint        DEFAULT NULL COMMENT '创建部门',
  `create_by`       bigint        DEFAULT NULL COMMENT '创建者',
  `create_time`     datetime      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`       bigint        DEFAULT NULL COMMENT '更新者',
  `update_time`     datetime      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_refund_no` (`refund_no`),
  KEY `idx_refund_status_time` (`status`, `create_time`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '退款单';

-- ----------------------------
-- 4. 账号与运营域
-- ----------------------------

-- ---------- 就诊人
DROP TABLE IF EXISTS `appt_patient`;
CREATE TABLE `appt_patient` (
  `id`          bigint       NOT NULL COMMENT '主键',
  `user_id`     bigint       NOT NULL COMMENT '归属账号id（sys_user）',
  `name`        varchar(64)  NOT NULL COMMENT '就诊人姓名',
  `id_type`     varchar(16)  NOT NULL COMMENT '证件类型：IDCARD身份证 CARD就诊卡',
  `id_no`       varchar(255) NOT NULL COMMENT '证件号：生产 AES 密文，演示期明文（M11）；日志禁止打印',
  `id_no_hash`  varchar(64)  NOT NULL COMMENT '证件号 HMAC-SHA256 摘要（D-S1-3）；唯一性与等值查询走此列',
  `is_default`  tinyint(1)   NOT NULL DEFAULT 0 COMMENT '是否默认就诊人：1是 0否（每人上限 10，PRD §14.2-9）',
  `status`      char(1)      NOT NULL DEFAULT '0' COMMENT '状态：0正常 1停用',
  `create_dept` bigint       DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint       DEFAULT NULL COMMENT '创建者',
  `create_time` datetime     DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint       DEFAULT NULL COMMENT '更新者',
  `update_time` datetime     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_patient_id_hash` (`id_type`, `id_no_hash`),
  KEY `idx_patient_user_status` (`user_id`, `status`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '就诊人';

-- ---------- 爽约黑名单
DROP TABLE IF EXISTS `appt_blacklist`;
CREATE TABLE `appt_blacklist` (
  `id`          bigint       NOT NULL COMMENT '主键',
  `user_id`     bigint       NOT NULL COMMENT '账号id（账号级统计，M13）',
  `patient_id`  bigint       DEFAULT NULL COMMENT '关联就诊人id（可空）',
  `reason`      varchar(255) DEFAULT NULL COMMENT '列入原因',
  `start_time`  datetime     NOT NULL COMMENT '生效时间',
  `end_time`    datetime     NOT NULL COMMENT '失效时间（半年内退号+爽约合计6次 → 限制半年，PRD §14.2-6）',
  `operator`    varchar(64)  DEFAULT NULL COMMENT '操作人',
  `status`      char(1)      NOT NULL DEFAULT '0' COMMENT '状态：0生效 1已解除',
  `create_dept` bigint       DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint       DEFAULT NULL COMMENT '创建者',
  `create_time` datetime     DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint       DEFAULT NULL COMMENT '更新者',
  `update_time` datetime     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_blacklist_user_status` (`user_id`, `status`),
  KEY `idx_blacklist_end_time` (`end_time`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '爽约黑名单（账号级）';

-- ---------- 站内信
DROP TABLE IF EXISTS `appt_notice`;
CREATE TABLE `appt_notice` (
  `id`          bigint        NOT NULL COMMENT '主键',
  `user_id`     bigint        NOT NULL COMMENT '接收账号id',
  `type`        varchar(32)   NOT NULL COMMENT '通知场景（PRD §6.12）',
  `title`       varchar(200)  NOT NULL COMMENT '标题',
  `content`     varchar(2000) DEFAULT NULL COMMENT '内容',
  `read_flag`   tinyint(1)    NOT NULL DEFAULT 0 COMMENT '已读：1是 0否',
  `create_dept` bigint        DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint        DEFAULT NULL COMMENT '创建者',
  `create_time` datetime      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint        DEFAULT NULL COMMENT '更新者',
  `update_time` datetime      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_notice_user_read` (`user_id`, `read_flag`, `create_time`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '站内信';

-- ----------------------------
-- 5. 支撑域（M10 新增四表）
-- ----------------------------

-- ---------- 定时任务日志
DROP TABLE IF EXISTS `appt_job_log`;
CREATE TABLE `appt_job_log` (
  `id`            bigint        NOT NULL COMMENT '主键',
  `job_name`      varchar(64)   NOT NULL COMMENT '任务名',
  `batch_no`      varchar(32)   NOT NULL COMMENT '批号（I8 不重跑、漏跑可补）',
  `start_time`    datetime      NOT NULL COMMENT '开始时间',
  `end_time`      datetime      DEFAULT NULL COMMENT '结束时间',
  `status`        varchar(16)   NOT NULL DEFAULT 'RUNNING' COMMENT 'RUNNING SUCCESS FAIL',
  `affected_rows` int           DEFAULT NULL COMMENT '影响行数',
  `message`       varchar(2000) DEFAULT NULL COMMENT '结果信息',
  `create_dept`   bigint        DEFAULT NULL COMMENT '创建部门',
  `create_by`     bigint        DEFAULT NULL COMMENT '创建者',
  `create_time`   datetime      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`     bigint        DEFAULT NULL COMMENT '更新者',
  `update_time`   datetime      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_job_batch` (`batch_no`),
  KEY `idx_job_name_time` (`job_name`, `start_time`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '定时任务日志';

-- ---------- 支付回调原始记录（append-only）
DROP TABLE IF EXISTS `appt_payment_callback`;
CREATE TABLE `appt_payment_callback` (
  `id`             bigint      NOT NULL COMMENT '主键',
  `payment_no`     varchar(32) NOT NULL COMMENT '支付单号',
  `trade_no`       varchar(64) DEFAULT NULL COMMENT '渠道流水号',
  `notify_id`      varchar(64) DEFAULT NULL COMMENT '渠道通知唯一id',
  `channel`        varchar(16) NOT NULL COMMENT '渠道',
  `raw_body`       text        COMMENT '原始报文（排查依据）',
  `sign_flag`      char(1)     DEFAULT NULL COMMENT '验签：0通过 1失败',
  `process_status` varchar(16) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING SUCCESS IGNORED重复丢弃 FAILED',
  `create_dept`    bigint      DEFAULT NULL COMMENT '创建部门',
  `create_by`      bigint      DEFAULT NULL COMMENT '创建者',
  `create_time`    datetime    DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`      bigint      DEFAULT NULL COMMENT '更新者',
  `update_time`    datetime    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_callback_dedup` (`payment_no`, `trade_no`, `notify_id`),
  KEY `idx_callback_status_time` (`process_status`, `create_time`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '支付回调原始记录（去重 + 重放 + 排查，§3.5）';

-- ---------- 对账结果
DROP TABLE IF EXISTS `appt_reconcile_result`;
CREATE TABLE `appt_reconcile_result` (
  `id`          bigint        NOT NULL COMMENT '主键',
  `batch_no`    varchar(32)   NOT NULL COMMENT '对账批次号',
  `check_type`  varchar(32)   NOT NULL COMMENT '检查项 R1~R7（技术方案 §3.6）',
  `target_id`   bigint        DEFAULT NULL COMMENT '目标id（slot / registration / payment）',
  `action`      varchar(32)   DEFAULT NULL COMMENT 'AUTO_FIX自动修复 ALERT告警',
  `status`      varchar(16)   NOT NULL DEFAULT 'OK' COMMENT 'OK正常 FIXED已修复 ALERT待人工',
  `detail`      varchar(2000) DEFAULT NULL COMMENT '详情',
  `create_dept` bigint        DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint        DEFAULT NULL COMMENT '创建者',
  `create_time` datetime      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint        DEFAULT NULL COMMENT '更新者',
  `update_time` datetime      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_reconcile_batch` (`batch_no`),
  KEY `idx_reconcile_type_status` (`check_type`, `status`, `create_time`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '对账结果';

-- ---------- 停诊批号
DROP TABLE IF EXISTS `appt_suspend_record`;
CREATE TABLE `appt_suspend_record` (
  `id`          bigint      NOT NULL COMMENT '主键',
  `batch_no`    varchar(32) NOT NULL COMMENT '批号（停诊幂等锚点 I7）',
  `scope_type`  varchar(16) NOT NULL COMMENT '范围：SCHEDULE单排班 STAFF_DATE某医生某日 CAMPUS_DATE院区某日',
  `scope_value` varchar(64) NOT NULL COMMENT '范围值（id 或 campusId:date）',
  `operator`    varchar(64) DEFAULT NULL COMMENT '操作人',
  `create_dept` bigint      DEFAULT NULL COMMENT '创建部门',
  `create_by`   bigint      DEFAULT NULL COMMENT '创建者',
  `create_time` datetime    DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_by`   bigint      DEFAULT NULL COMMENT '更新者',
  `update_time` datetime    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_suspend_batch` (`batch_no`),
  KEY `idx_suspend_scope` (`scope_type`, `scope_value`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '停诊批号（I7 批量操作不重不放）';

SET FOREIGN_KEY_CHECKS = 1;
