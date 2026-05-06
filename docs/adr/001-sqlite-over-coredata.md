# ADR-001: SQLite 裸 API vs CoreData/GRDB

## 状态
已采纳

## 背景
剪贴板历史数据需要持久化，支持全文搜索（FTS5），记录量级 < 5,000 条。

考察选项：
- **CoreData** — Apple 官方 ORM，Xcode 集成
- **GRDB** — Swift 社区 ORM，类型安全
- **SQLite C API (sqlite3)** — macOS 内置，零依赖

## 决策
使用 SQLite C API (`sqlite3`) 直接操作。

## 理由
- **零外部依赖** — 项目哲学是不引入第三方库；macOS 内置 `libsqlite3`，无需链接额外库
- **完全控制** — 手写 SQL 和迁移逻辑，不依赖 ORM 的隐式行为，适合项目规模
- **FTS5 天然支持** — SQLite 内置全文搜索，`MATCH` 查询直接可用，无需额外索引层
- **性能足够** — < 5,000 条记录，WAL 模式写入，毫秒级响应

## 代价
- 手写 SQL 比 ORM 繁琐（但项目表结构简单，仅 2 表 + FTS 外部内容表）
- 无类型安全查询（通过 `DatabaseManager` 封装层隔离裸 sqlite3 调用）
- 迁移需手写 `ALTER TABLE` 和版本检查

## 备选方案
- **CoreData** — 重依赖，FTS 需桥接 `NSPredicate`，零依赖目标无法满足
- **GRDB** — 优秀但为第三方依赖；项目体积小，收益不明显
