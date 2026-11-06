# Todo 后端 API 接口文档

根据 [todo-backend](https://github.com/liuxingboy/todo-backend) 的控制器、中间件和 JWT 实现整理。

- 更新日期：2026-10-25。
- 源码基线：[`12d3311`](https://github.com/liuxingboy/todo-backend/tree/12d33119429e3791d7c04624165f8103d7cc30c1)，包含长期目标与公开文件接口。
- 覆盖范围：源码注册的全部 34 个业务接口，包括浏览器下载凭证、9 个长期目标接口和 2 个公开只读文件接口。
- 验证方式：长期目标及其“我的一天”联动已在隔离的 MySQL 8.0.45 数据库和临时后端上进行接口测试；其他接口以源码及已有验证为准。示例 ID、日期、Token 均为示意值，测试不代表线上已部署。
- 2026-10-21 公开只读文件接口已完成隔离 MySQL 测试和线上验证，支持匿名列表、附件、HEAD 与单段 Range；旧文件操作和个人接口继续鉴权。个人网站入口为 `https://maopc.icu/downloads.html`。
- 长期目标迁移位于后端 `migrations/001_long_term_goals.sql`。既有表的全部约束仍应以实际数据库定义为准；迁移前需备份，并先迁移、后启动新后端。

## 1. 通用约定

### 1.1 服务地址与请求格式

正式服务迁往 N100，外部通过 HTTPS 访问，接口前缀为 `/api`。后端内部仍监听 `0.0.0.0:8080`，不直接公开该端口。

```text
Base URL = https://todo.maopc.icu/api
```

本文接口路径均包含 `/api`。若客户端 Base URL 已包含 `/api`，请勿重复拼接。

Android / Windows 新版默认域名为 `todo.maopc.icu`、端口 `443`，开启 HTTPS；Web 使用同源 `/api`。阿里云旧 IP 在迁移完成后停用。N100 当前采用公网 IPv6，访问网络需要支持 IPv6。

| 项目 | 约定 |
| --- | --- |
| JSON 请求 | `Content-Type: application/json` |
| 文件上传 | `multipart/form-data`，由 HTTP 客户端自动生成 boundary |
| 受保护接口 | `Authorization: Bearer <access_token>` |
| ID | JSON 请求体和响应中的 ID 是整数，服务端按 64 位整数处理；不要在 JSON 中传字符串 ID |
| 路径 ID | 替换为实际 ID；长期目标路径 ID 必须为正整数且不超过有符号 64 位整数上限。旧接口的校验规则以各节为准 |
| 布尔值 | 使用 JSON `true` / `false`，不是 `0` / `1` 或字符串 |
| 时间字符串 | 数据库字段直接转成字符串返回，未统一转为 ISO 8601，也未返回时区 |
| 截止日期 | 长期目标和子任务使用 `YYYY-MM-DD` 或 JSON `null`；按北京时间 04:00 跨天的任务日期判断，截止日次日 04:00 才过期 |
| 分页 | 所有列表均一次返回全部匹配记录；没有分页、搜索参数 |

除明确标注可选外，参数表中的 JSON 字段为必填。旧接口主要校验类型；新增长期目标接口校验非空、长度、正整数路径 ID 和真实日历日期，详见第 9 节。

### 1.2 JSON 响应与 HTTP 状态

成功示例：

```json
{"code":0,"msg":"ok","data":[]}
```

错误示例：

```json
{"code":400,"msg":"Missing content"}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `code` | integer | `0` 表示成功；其他值表示业务错误 |
| `msg` | string | 结果说明，具体文本见各接口 |
| `data` | object / array | 仅部分成功响应有此字段；无数据时通常省略，不保证为 `null` |

**必须同时处理 HTTP 状态码和 JSON `code`：**

- 既有任务池、每日任务、便签等接口的 JSON 错误没有显式设置 HTTP 状态，正常构造响应时默认是 **HTTP 200**，即使 `code` 为 `400`、`401`、`403`、`404`、`409` 或 `500`。
- `AuthFilter` 鉴权失败明确返回 **HTTP 401**，JSON 中也有 `code: 401`。
- 长期目标接口发生错误时同时设置对应 HTTP 状态（400 / 404 / 409 / 500）；成功仍为 HTTP 200、`code: 0`。下载凭证接口也使用相应 HTTP 错误状态。
- 文件下载成功返回二进制，二维码接口返回图片，二者没有 JSON 包装。
- 框架或反向代理产生的错误（例如请求体过大、文件无法读取、路由不匹配）不保证使用上述 JSON 结构。

| 业务码 | 含义 |
| --- | --- |
| `0` | 操作成功 |
| `400` | JSON 格式、字段类型或上传内容不符合要求 |
| `401` | 登录凭证错误、Token 缺失、无效或过期 |
| `403` | 无权限或资源不存在；具体看接口 |
| `404` | 资源不存在或无权限；具体看接口 |
| `409` | 用户名已存在，或已完成子任务请求加入今天 |
| `500` | 数据库或服务端处理异常 |

除特殊说明外，任务池、我的一天、便签、文件查询/下载/删除的捕获异常响应为 `{"code":500,"msg":"Database Error"}`。注册、登录、刷新和上传的异常文本见对应接口。

### 1.3 鉴权及刷新

公开接口：注册、登录、刷新 Token、获取打赏二维码，以及第 6.6 节的全部共享文件列表与下载。原浏览器附件下载接口仍使用短期下载凭证，其他接口均要求 Access Token。

| Token | 有效期及行为 |
| --- | --- |
| `access_token` | JWT，签发后 2 小时过期；用于 `Authorization` 请求头 |
| `refresh_token` | 签发时 JWT 有效期 30 天；数据库同时保存 Token 和 `NOW() + 30 DAY` 的过期时间 |

刷新接口实际通过数据库匹配 Refresh Token 并检查数据库过期时间，不调用 Access Token 验证逻辑。每次登录覆盖该用户数据库保存的 Refresh Token，因此此前不同的 Refresh Token 会失效；已签发的 Access Token 不会因这一数据库更新立即失效。

刷新只返回新的 Access Token，不轮换 Refresh Token，也不延长数据库中的刷新有效期。源码没有退出登录、主动吊销 Token、获取当前用户资料或修改密码接口。

推荐调用流程：登录保存两个 Token → 业务请求携带 Access Token → 鉴权失败时用 Refresh Token 换取 Access Token → 更新后重试原请求。刷新接口自身返回 `code: 401` 时应重新登录，避免循环刷新。

所有受保护接口共用以下错误：

| HTTP 状态 | `code` | `msg` | 条件 |
| --- | --- | --- | --- |
| 401 | 401 | `Missing or invalid Authorization header` | 缺少请求头或未以大小写一致的 `Bearer ` 开头 |
| 401 | 401 | `Token invalid or expired` | Token 无效、过期、签名/issuer/type 不符等 |

### 1.4 接口总览

| 方法 | 路径 | 功能 | 鉴权 |
| --- | --- | --- | --- |
| POST | `/api/auth/register` | 注册 | 否 |
| POST | `/api/auth/login` | 登录 | 否 |
| POST | `/api/auth/refresh` | 刷新 Access Token | 否，正文提供 Refresh Token |
| GET | `/api/pools` | 获取个人任务池及模板 | 是 |
| POST | `/api/pools` | 创建任务池 | 是 |
| POST | `/api/pools/task` | 添加任务模板 | 是 |
| DELETE | `/api/pools` | 删除任务池及其模板 | 是 |
| DELETE | `/api/pools/tasks/{task_id}` | 删除任务模板 | 是 |
| GET | `/api/goals` | 获取目标、子任务、进度及状态 | 是 |
| POST | `/api/goals` | 新建长期目标 | 是 |
| PUT | `/api/goals/{goal_id}` | 编辑目标 | 是 |
| DELETE | `/api/goals/{goal_id}` | 删除目标、全部子任务和每日关联 | 是 |
| POST | `/api/goals/{goal_id}/tasks` | 新建子任务 | 是 |
| PUT | `/api/goals/tasks/{task_id}` | 编辑子任务 | 是 |
| DELETE | `/api/goals/tasks/{task_id}` | 删除子任务及每日关联 | 是 |
| PUT | `/api/goals/tasks/{task_id}/status` | 设置子任务完成状态 | 是 |
| POST | `/api/goals/tasks/{task_id}/myday` | 将子任务加入今天 | 是 |
| GET | `/api/myday` | 获取今天的任务 | 是 |
| POST | `/api/myday` | 添加今天的任务 | 是 |
| PUT | `/api/myday/status` | 设置任务完成状态 | 是 |
| POST | `/api/myday/import` | 从模板导入今天的任务 | 是 |
| GET | `/api/notes` | 获取个人便签 | 是 |
| POST | `/api/notes` | 创建便签 | 是 |
| PUT | `/api/notes` | 修改便签 | 是 |
| DELETE | `/api/notes` | 删除便签 | 是 |
| POST | `/api/files/upload` | 上传共享文件 | 是 |
| GET | `/api/files` | 获取全局共享文件列表 | 是 |
| GET | `/api/files/download/{file_id}` | 下载共享文件 | 是 |
| POST | `/api/files/download-ticket/{file_id}` | 申请浏览器下载凭证 | 是 |
| GET | `/api/files/browser-download/{file_id}` | 浏览器原生附件下载 | 否，须携带短期 ticket |
| DELETE | `/api/files/{file_id}` | 删除自己上传的文件 | 是 |
| GET / HEAD | `/api/public/files` | 全部共享文件的公开列表 | 否 |
| GET / HEAD | `/api/public/files/download/{file_id}` | 公开附件下载，支持单段 Range | 否 |
| GET | `/api/donate/qr` | 获取打赏二维码图片 | 否 |

## 2. 用户认证

### 2.1 注册

**`POST /api/auth/register`**，无需鉴权。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `username` | string | 用户名 |
| `password` | string | 密码原文，由后端处理后存储 |

```json
{"username":"demo_user","password":"example_password"}
```

成功响应（不返回用户 ID 或 Token，注册后需再登录）：

```json
{"code":0,"msg":"Registration successful"}
```

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `Invalid JSON format` | 无可解析的 JSON 正文 |
| 400 | `Missing username or password` | 用户名或密码缺失/不是字符串 |
| 409 | `Username already exists` | 用户名查询结果已存在 |
| 500 | `Database connection error` | 未取得数据库客户端 |
| 500 | `DB Error: <异常详情>` / `Internal Error: <异常详情>` / `Unknown Error` | 捕获到相应异常 |

### 2.2 登录

**`POST /api/auth/login`**，无需鉴权。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `username` | string | 用户名 |
| `password` | string | 密码原文 |

```json
{"username":"demo_user","password":"example_password"}
```

成功响应：

```json
{
  "code": 0,
  "msg": "Login successful",
  "data": {
    "access_token": "<access-token>",
    "refresh_token": "<refresh-token>"
  }
}
```

`data.access_token`、`data.refresh_token` 均为字符串，不返回 `user_id`、`username` 或 `expires_in`。

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `Invalid JSON format` | JSON 无效，或用户名/密码缺失、类型错误 |
| 401 | `Invalid username or password` | 用户不存在或密码错误 |
| 500 | `Error: <异常详情>` / `Unknown Error` | 捕获异常 |

### 2.3 刷新 Access Token

**`POST /api/auth/refresh`**，无需 Authorization 请求头。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `refresh_token` | string | 登录接口返回的 Refresh Token |

```json
{"refresh_token":"<refresh-token>"}
```

成功响应：

```json
{
  "code": 0,
  "msg": "Token refreshed successfully",
  "data": {"access_token":"<new-access-token>"}
}
```

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `Missing refresh_token` | JSON 无效或字段缺失/不是字符串 |
| 401 | `Refresh token invalid or expired. Please login again.` | 数据库中无匹配的未过期 Token |
| 500 | `Database Error` | 捕获异常 |

## 3. 任务池

本模块所有接口均需鉴权，只允许操作当前用户的任务池及模板。

### 3.1 获取任务池及模板

**`GET /api/pools`**。无请求参数。

```json
{
  "code": 0,
  "msg": "ok",
  "data": [
    {
      "id": 1,
      "pool_name": "英语学习",
      "tasks": [
        {"id": 10, "content": "背 20 个单词"}
      ]
    }
  ]
}
```

| 响应字段 | 类型 | 说明 |
| --- | --- | --- |
| `data` | array | 当前用户的任务池；无数据为 `[]` |
| `data[].id` | integer | 任务池 ID |
| `data[].pool_name` | string | 任务池名称 |
| `data[].tasks` | array | 此池的模板；无模板为 `[]` |
| `data[].tasks[].id` | integer | 模板 ID，用于删除模板或导入我的一天 |
| `data[].tasks[].content` | string | 模板内容 |

任务池和模板查询均未指定排序，不保证返回顺序。

### 3.2 创建任务池

**`POST /api/pools`**。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `pool_name` | string | 任务池名称 |

```json
{"pool_name":"英语学习"}
```

成功：

```json
{"code":0,"msg":"Pool created successfully"}
```

参数错误：`code: 400`，`msg: "Missing pool_name"`。不返回新池 ID，创建后需重新获取列表。控制器没有重名校验。

### 3.3 添加任务模板

**`POST /api/pools/task`**。注意这里是单数 `task`。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `pool_id` | integer | 当前用户的任务池 ID |
| `content` | string | 模板内容 |

```json
{"pool_id":1,"content":"背 20 个单词"}
```

成功：

```json
{"code":0,"msg":"Task added to pool successfully"}
```

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `Missing pool_id or content` | JSON 无效或字段缺失/类型错误 |
| 403 | `Permission denied or pool does not exist` | 池不存在或不属于当前用户 |

不返回新模板 ID，需刷新任务池列表。

### 3.4 删除任务池及全部模板

**`DELETE /api/pools`**。参数放在 **JSON 正文**，不是查询字符串或路径。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `pool_id` | integer | 待删除的池 ID |

```json
{"pool_id":1}
```

成功：

```json
{"code":0,"msg":"Pool and its tasks deleted successfully"}
```

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `Missing pool_id` | JSON 无效或字段缺失/类型错误 |
| 404 | `Pool not found or permission denied` | 池不存在或不属于当前用户 |

后端依次删除池内模板和任务池，没有显式事务。代码未主动删除已导入的我的一天任务；实际外键影响因仓库缺少 DDL 无法确认。

### 3.5 删除单个模板

**`DELETE /api/pools/tasks/{task_id}`**。注意这里是复数 `tasks`。

| 路径参数 | 类型 | 说明 |
| --- | --- | --- |
| `task_id` | ID 文本 | 模板 ID，不是我的一天任务 ID |

示例：`DELETE /api/pools/tasks/10`。无请求正文。

成功：

```json
{"code":0,"msg":"Task deleted successfully"}
```

不存在或无权限：`code: 403`，`msg: "Permission denied or task not found"`。删除条件会关联任务池的所有者；已导入任务的外键行为同上，源码未提供数据库定义。

## 4. 我的一天

本模块所有接口均需鉴权。“今天”统一按**北京时间凌晨 04:00 跨天**：00:00–03:59 仍属前一个任务日。后端使用 `DATE(UTC_TIMESTAMP() + INTERVAL 4 HOUR)`，不依赖设备时区，也不修改 MySQL 全局时区。历史记录的 `target_date` 不重写。

`GET /api/myday` 和 `GET /api/goals` 的顶层响应均附带 `task_date: "YYYY-MM-DD"`，包括空列表。前端应使用该字段显示任务日期，不能直接拿设备当天日期代替。

### 4.1 获取今天的任务

**`GET /api/myday`**。无请求参数，不支持指定日期。

```json
{
  "code": 0,
  "msg": "ok",
  "data": [
    {"id":100,"content":"背 20 个单词","is_completed":false}
  ]
}
```

| 响应字段 | 类型 | 说明 |
| --- | --- | --- |
| `data` | array | 当前用户今天的任务；无数据为 `[]` |
| `data[].id` | integer | 我的一天任务实例 ID，与模板 ID 不同 |
| `data[].content` | string | 任务内容 |
| `data[].is_completed` | boolean | 数据库 `status == 1` 时为 `true`，否则为 `false` |

返回内容包含今天已完成和未完成的任务，按进行中、已完成、已过期排序，同组按每日记录 ID 排序。不返回 `target_date`、`pool_task_id` 或 `completed_at`。

长期目标子任务在本接口中额外返回以下字段；普通每日任务保持原有字段。子任务的内容和完成状态从长期目标实时读取，不是导入时的独立副本。

| 附加字段 | 类型 | 说明 |
| --- | --- | --- |
| `goal_task_id` | integer | 持久子任务 ID；不同于本行每日记录的 `id` |
| `goal_id` | integer | 所属长期目标 ID |
| `goal_title` | string | 目标当前名称 |
| `deadline` | string / null | 子任务自己的截止日期 |
| `is_expired` | boolean | 未完成且已超过子任务截止日期 |

长期目标子任务只在被选中的当天出现；第二天仍保留在目标和任务池中，可再次加入今天。同一子任务的完成状态跨天持久保留。

### 4.2 直接添加任务

**`POST /api/myday`**。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `content` | string | 任务内容 |

```json
{"content":"整理本周计划"}
```

成功：

```json
{"code":0,"msg":"Task added to My Day"}
```

参数错误：`code: 400`，`msg: "Missing task content"`。后端设置日期为今天、状态为未完成，不返回新任务 ID。

### 4.3 设置完成状态

**`PUT /api/myday/status`**。这是设置目标状态，不是服务器自动取反。

如果该每日记录关联长期目标子任务，此操作设置的是子任务唯一的完成状态，目标进度同步变化；取消完成也同步回退。`task_id` 仍传本行的每日记录 `id`，不能传 `goal_task_id`。这类设置相同状态的重试也返回成功。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `task_id` | integer | 我的一天任务实例 ID |
| `is_completed` | boolean | `true` 完成，`false` 取消完成 |

```json
{"task_id":100,"is_completed":true}
```

成功：

```json
{"code":0,"msg":"Task status updated"}
```

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `Missing task_id or is_completed flag` | JSON 无效或字段缺失/类型错误 |
| 404 | `Task not found or permission denied` | SQL 受影响行数为 0 |

完成时写入 `status = 1`、`completed_at = NOW()`；取消时写入 `status = 0`、`completed_at = NULL`。更新条件只限定任务 ID 和用户 ID，没有限定今天，因此已知 ID 的历史任务也能更新。重复设置完成会重写完成时间；重复更新无变化时的结果取决于数据库客户端的受影响行数语义。

### 4.4 从模板导入任务

**`POST /api/myday/import`**。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `pool_task_id` | integer | 模板 ID，来自 `GET /api/pools` 的 `tasks[].id` |

```json
{"pool_task_id":10}
```

成功：

```json
{"code":0,"msg":"Task imported to My Day successfully"}
```

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `Missing pool_task_id` | JSON 无效或字段缺失/类型错误 |
| 403 | `Pool task not found or permission denied` | 模板不存在或所属池不属于当前用户 |

将模板内容复制到新的今日任务，记录模板 ID，初始状态未完成；保留原模板，不返回新实例 ID。控制器未做重复导入校验，每次调用都会尝试插入，是否受唯一约束限制需核对数据库。

## 5. 便签

本模块所有接口均需鉴权，仅操作当前用户的便签。

### 5.1 获取便签列表

**`GET /api/notes`**。无请求参数，按 `updated_at DESC` 返回。

```json
{
  "code": 0,
  "msg": "ok",
  "data": [
    {"id":20,"content":"今天的灵感","updated_at":"2026-09-21 10:30:00"}
  ]
}
```

| 响应字段 | 类型 | 说明 |
| --- | --- | --- |
| `data` | array | 便签列表；无数据为 `[]` |
| `data[].id` | integer | 便签 ID |
| `data[].content` | string | 便签内容；接口仅按字符串传输，没有富文本格式协议 |
| `data[].updated_at` | string | 数据库更新时间原样转为字符串；示例格式不代表已验证的时区/精度契约 |

### 5.2 创建便签

**`POST /api/notes`**。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `content` | string | 便签内容 |

```json
{"content":"今天的灵感"}
```

成功：

```json
{"code":0,"msg":"Note created successfully"}
```

参数错误：`code: 400`，`msg: "Missing content"`。不返回新便签 ID。

### 5.3 修改便签

**`PUT /api/notes`**。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `note_id` | integer | 便签 ID |
| `content` | string | 完整的新内容，覆盖旧内容 |

```json
{"note_id":20,"content":"更新后的灵感"}
```

成功：

```json
{"code":0,"msg":"Note updated successfully"}
```

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `Missing note_id or content` | JSON 无效或字段缺失/类型错误 |
| 404 | `Note not found or permission denied` | SQL 受影响行数为 0 |

SQL 只更新 `content`，没有显式更新 `updated_at`；更新时间是否自动变化取决于数据库定义。提交相同内容时，可能因受影响行数为 0 而返回上述 404，需在实际数据库环境验证。

### 5.4 删除便签

**`DELETE /api/notes`**。参数在 JSON 正文。

| JSON 字段 | 类型 | 说明 |
| --- | --- | --- |
| `note_id` | integer | 待删除的便签 ID |

```json
{"note_id":20}
```

成功：

```json
{"code":0,"msg":"Note deleted successfully"}
```

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `Missing note_id` | JSON 无效或字段缺失/类型错误 |
| 404 | `Note not found or permission denied` | 不存在或不属于当前用户 |

## 6. 共享文件

原文件列表、上传、原下载、申请下载凭证及删除需要登录；原浏览器附件下载验证短期 ticket。2026-10-21 起另增公开只读接口，用户明确选择将全部共享文件公开；公开列表及下载无需登录，上传和删除权限保持原状，删除仅限上传者本人。

### 6.1 上传文件

**`POST /api/files/upload`**，使用 `multipart/form-data`。

| 表单项 | 类型 | 说明 |
| --- | --- | --- |
| 文件项（示例名 `file`） | binary | 至少提供一个文件；代码未限定字段名，只处理解析结果中的第一个文件 |

不要把文件转为 JSON 或 Base64。多文件请求中后续文件不会被此控制器保存。

成功响应：

```json
{
  "code": 0,
  "msg": "File uploaded successfully",
  "data": {"file_name":"example.txt","size":1024}
}
```

| 响应字段 | 类型 | 说明 |
| --- | --- | --- |
| `data.file_name` | string | 原始文件名 |
| `data.size` | integer | 文件大小，单位字节 |

不返回文件 ID 或下载 URL，需从文件列表获取 ID。

| `code` | `msg` | 条件 |
| --- | --- | --- |
| 400 | `No file found in the request` | multipart 解析失败或没有文件项 |
| 500 | `Failed to save file` | 保存或数据库写入过程中捕获异常 |

主程序设置的上限是**整个 HTTP 请求体 `1,073,741,824` 字节（1 GiB）**，包含 multipart 开销，所以不能保证恰好 1 GiB 的文件可上传；反向代理也可能有更小上限。代码没有显式校验扩展名或 MIME 类型。

文件保存路径为运行目录下的 `./shared_files_storage/<微秒时间戳>_<原始文件名>`。部署需保证存储目录可用、可写。控制器未检查 `saveAs` 返回值，因此 JSON 成功响应不构成物理文件成功落盘的完整保证，宜在部署验证时同时测试下载。

### 6.2 获取共享文件列表

**`GET /api/files`**。无参数，按 `upload_time DESC` 返回所有用户的共享文件。

```json
{
  "code": 0,
  "msg": "ok",
  "data": [
    {
      "id":30,
      "file_name":"example.txt",
      "size":1024,
      "upload_time":"2026-09-21 10:30:00",
      "uploader":"demo_user"
    }
  ]
}
```

| 响应字段 | 类型 | 说明 |
| --- | --- | --- |
| `data` | array | 文件列表；无数据为 `[]` |
| `data[].id` | integer | 文件 ID，用于下载或删除 |
| `data[].file_name` | string | 原始文件名 |
| `data[].size` | integer | 文件大小，字节 |
| `data[].upload_time` | string | 数据库上传时间直接转为字符串 |
| `data[].uploader` | string | 上传者用户名，不是用户 ID |

不返回 `uploader_id`、`can_delete`、存储路径或下载 URL。客户端可根据已知用户名展示操作入口，但最终删除权限由后端校验。

### 6.3 下载共享文件

**`GET /api/files/download/{file_id}`**。

| 路径参数 | 类型 | 说明 |
| --- | --- | --- |
| `file_id` | ID 文本 | 共享文件 ID |

示例：`GET /api/files/download/30`。无正文，任意登录用户均可下载。

成功返回文件二进制，控制器指定 `Content-Type: application/octet-stream`，并将原始文件名传给框架作为下载文件名。无 `code` / `msg` / `data` 包装。

数据库记录不存在时返回 JSON：

```json
{"code":404,"msg":"File not found"}
```

捕获异常时返回 `code: 500`、`msg: "Database Error"`。物理文件缺失或无法读取时由框架文件响应处理，不保证与“数据库无记录”时的响应相同。

客户端应区分二进制响应与 JSON 错误，避免将错误正文保存成文件。Web 使用第 6.5 节的短期凭证方案，让浏览器接管下载；Android / Windows 可继续使用本接口。

### 6.4 删除共享文件

**`DELETE /api/files/{file_id}`**。

| 路径参数 | 类型 | 说明 |
| --- | --- | --- |
| `file_id` | ID 文本 | 自己上传的共享文件 ID |

示例：`DELETE /api/files/30`。无正文。

成功：

```json
{"code":0,"msg":"File deleted successfully"}
```

不存在或不是本人上传：

```json
{"code":403,"msg":"File not found or permission denied (You can only delete your own files)"}
```

先尝试删除磁盘文件，再删除数据库记录。磁盘文件删除失败只记录日志，仍继续删除记录，因此成功响应不保证磁盘文件已清理；两步也不是原子操作。

### 6.5 浏览器原生下载凭证

**`POST /api/files/download-ticket/{file_id}`**，携带 Bearer 鉴权，无请求正文。

```json
{"code":0,"msg":"ok","data":{"download_url":"/api/files/browser-download/30?ticket=<64位随机十六进制凭证>","expires_in":300}}
```

登录后先申请凭证，再让浏览器导航至返回的同源相对 URL。不要把响应转为 Blob；由浏览器处理附件，下载可进入手机浏览器下载列表。

**`GET /api/files/browser-download/{file_id}?ticket=...`** 不需要 Bearer 请求头。凭证绑定文件、有效期 300 秒，期间允许重试和 Range 请求；不匹配、篡改、缺失或过期返回 HTTP 403。凭证保存在后端进程内存，后端重启后需要重新申请。成功响应为附件二进制，设置私有、不缓存和不发送 Referer 的响应头。申请接口不允许缓存。

### 6.6 全部文件公开下载

以下为新增只读接口；不需要账号、Bearer Token 或短期 ticket，不改变原有 `/api/files` 接口权限。不修改数据库结构，之后上传到共享文件大厅的文件也会出现在公开列表。

**`GET /api/public/files`**，支持 `HEAD`。按 `upload_time DESC, id DESC` 返回全部共享文件元数据，不返回上传者、磁盘路径或其他账户信息。列表响应使用 `Cache-Control: no-store`。

```json
{"code":0,"msg":"ok","data":[{"id":30,"file_name":"示例.txt","size":1024,"upload_time":"2026-10-21 20:00:00","download_url":"/api/public/files/download/30"}]}
```

**`GET /api/public/files/download/{file_id}`**，支持 `HEAD`。使用普通同源链接直接下载附件，由浏览器下载管理器接管，不将响应转为 Blob。

- `file_id` 须为正的有符号 64 位整数；非法、零、负数或溢出返回 HTTP 400。
- 文件记录不存在、磁盘文件缺失、路径位于共享文件存储目录之外，或符号链接指向目录之外，均返回 HTTP 404。
- 成功返回 `application/octet-stream` 和附件文件名，并设置 `Accept-Ranges: bytes`、`Cache-Control: no-store`、`X-Content-Type-Options: nosniff`、`Referrer-Policy: no-referrer`。
- 支持单段 `Range: bytes=0-7`、`bytes=8-`、`bytes=-8`。局部响应为 HTTP 206；非法、越界或多段 Range 返回 HTTP 416，并携带 `Content-Range: bytes */<文件大小>`。带 `If-Range` 的请求保守地返回完整文件。
- 数据库异常返回 HTTP 500；公开接口不支持上传或删除。

个人网站通过 N100 的 Caddy 仅代理上述两个路径的 GET / HEAD 请求，页面与下载均使用 `https://maopc.icu`，不向浏览器暴露账户凭据。

## 7. 打赏二维码

**`GET /api/donate/qr`**，无需鉴权，无请求参数。

直接返回运行目录下 `./assets/donate.png` 文件，由框架生成文件响应；正常文件存在时为 PNG 图片内容，没有 JSON 包装。图片缺失等错误由框架处理。

仓库没有提供该图片，部署时需自行配置。可用于图片地址：

```html
<img src="http://localhost:8080/api/donate/qr" alt="打赏二维码">
```

## 8. 调用示例（Windows PowerShell）

以下示例假设本机服务已运行，使用测试账号和自己创建的数据。

### 8.1 注册、登录及携带 Token

```powershell
$todoApiBase = 'http://localhost:8080/api'
$todoCredentials = @{ username = 'demo_user'; password = 'example_password' } | ConvertTo-Json

# 用户已存在时，无需再次注册。
Invoke-RestMethod -Method Post -Uri "$todoApiBase/auth/register" -ContentType 'application/json' -Body $todoCredentials

$todoLogin = Invoke-RestMethod -Method Post -Uri "$todoApiBase/auth/login" -ContentType 'application/json' -Body $todoCredentials
if ($todoLogin.code -ne 0) { throw $todoLogin.msg }
$todoHeaders = @{ Authorization = "Bearer $($todoLogin.data.access_token)" }
$todoRefreshToken = $todoLogin.data.refresh_token

Invoke-RestMethod -Method Get -Uri "$todoApiBase/pools" -Headers $todoHeaders
Invoke-RestMethod -Method Get -Uri "$todoApiBase/myday" -Headers $todoHeaders
```

### 8.2 新建便签及 DELETE JSON 正文

```powershell
$todoNoteBody = @{ content = 'Example note' } | ConvertTo-Json
$todoCreated = Invoke-RestMethod -Method Post -Uri "$todoApiBase/notes" -Headers $todoHeaders -ContentType 'application/json' -Body $todoNoteBody
if ($todoCreated.code -ne 0) { throw $todoCreated.msg }

# 从列表确认实际要删除的便签 ID，再手动替换下面示例中的 20。
Invoke-RestMethod -Method Get -Uri "$todoApiBase/notes" -Headers $todoHeaders
$todoDeleteBody = @{ note_id = 20 } | ConvertTo-Json
Invoke-RestMethod -Method Delete -Uri "$todoApiBase/notes" -Headers $todoHeaders -ContentType 'application/json' -Body $todoDeleteBody
```

### 8.3 刷新 Token

```powershell
$todoRefreshBody = @{ refresh_token = $todoRefreshToken } | ConvertTo-Json
$todoRefreshed = Invoke-RestMethod -Method Post -Uri "$todoApiBase/auth/refresh" -ContentType 'application/json' -Body $todoRefreshBody
if ($todoRefreshed.code -ne 0) { throw $todoRefreshed.msg }
$todoHeaders.Authorization = "Bearer $($todoRefreshed.data.access_token)"
```

### 8.4 上传、查看列表和下载

使用 `curl.exe`，避免 Windows PowerShell 的 `curl` 别名差异。将本地文件路径与 ID 改为实际值，不要手动设置 multipart Content-Type。

```powershell
curl.exe -X POST "$todoApiBase/files/upload" -H "Authorization: $($todoHeaders.Authorization)" -F 'file=@C:/Temp/example.txt'

Invoke-RestMethod -Method Get -Uri "$todoApiBase/files" -Headers $todoHeaders

# 先输出响应头再决定保存方式；业务错误也可能是 HTTP 200 的 JSON。
curl.exe -D download-headers.txt "$todoApiBase/files/download/30" -H "Authorization: $($todoHeaders.Authorization)" -o download-response.bin
Get-Content download-headers.txt
```

## 9. 长期目标

### 9.1 业务规则与迁移

- 目标和子任务都属于当前登录用户。客户端不传 `user_id`，不能操作其他人的 ID。
- 目标可填写名称、说明和截止日期；子任务可填写内容和独立截止日期。两种日期都可不设，传 JSON `null`。统一使用北京时间 04:00 跨天的任务日期；例如截止日为 10 月 19 日，10 月 20 日 03:59 仍有效，04:00 起过期。
- 过期只影响状态、样式和排序，不会删除、自动完成或阻止编辑与执行。过期后仍能勾选完成；将日期改到未来或清空，可以恢复进行中状态。
- 完成优先于过期：目标含至少一个子任务且全部完成时为 `completed`；否则按目标自己的日期判断 `expired` 或 `active`。没有子任务时进度为 0，不自动完成。父目标过期不会直接改变子任务状态。
- 进度等于已完成子任务数 / 全部现存子任务数，所有子任务权重相同，过期任务也计入分母。新增、删除、完成或取消完成都会重新计算。
- 列表先进行中，再已完成，最后已过期；同组有日期的排在无日期的前面，按截止日期升序，再按 ID 升序。子任务使用相同排序。
- “任务池”是现有普通模板与目标子任务的统一选取入口。目标子任务从 `/api/goals` 读取，不复制到普通 `pool_tasks`。
- 选择加入今天只创建每日关联；同一子任务同一天最多一条记录。第二天可以重新选取，不自动顺延。
- **删除目标会原子级联删除其全部子任务，以及这些子任务在所有日期的每日记录；删除子任务也会删除它的所有每日记录。** 普通任务池模板和无关联的每日任务不受影响。
- 数据库迁移新增 `long_term_goals`、`goal_tasks`；为 `my_day_tasks` 增加可空的 `goal_task_id`、每日唯一索引和级联外键。已有每日任务该列为 NULL，保留原行为。先执行迁移，再启动新后端；不要直接对线上数据库运行测试脚本。

### 9.2 获取目标和子任务

**`GET /api/goals`**，无参数，返回当前用户的全部目标及其子任务；无数据时 `data: []`。

```json
{
  "code": 0,
  "msg": "ok",
  "task_date": "2026-10-19",
  "data": [{
    "id": 10,
    "title": "完成 Todo 项目",
    "description": "拆分任务，逐步完成",
    "deadline": "2026-12-31",
    "status": "active",
    "total_tasks": 2,
    "completed_tasks": 1,
    "progress": 50,
    "tasks": [
      {"id":101,"content":"完成长期目标功能","deadline":null,"is_completed":false,"status":"active","is_in_my_day":true},
      {"id":102,"content":"修复手机网页下载","deadline":null,"is_completed":true,"status":"completed","is_in_my_day":false}
    ]
  }]
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `status`、`tasks[].status` | string | `active` / `completed` / `expired`，均由服务端计算 |
| `deadline`、`tasks[].deadline` | string / null | `YYYY-MM-DD`，不包含时间或时区 |
| `total_tasks`、`completed_tasks` | integer | 当前子任务总数、已完成数 |
| `progress` | integer | 0–100，百分比向下取整；空目标为 0 |
| `tasks[].is_completed` | boolean | 持久完成状态 |
| `tasks[].is_in_my_day` | boolean | 今天是否已选取；不表示其他日期是否选过 |

### 9.3 新建和编辑目标

**`POST /api/goals`** 新建；**`PUT /api/goals/{goal_id}`** 编辑。

| JSON 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `title` | string | 是 | 去除首尾空白后非空，最多 200 个 Unicode 字符 |
| `description` | string / null | 否 | 说明，最多 10000 个 UTF-8 字节；缺省或 null 按空字符串处理 |
| `deadline` | string / null | 否 | 有效日期 `YYYY-MM-DD`，年份 1000–9999；缺省或 null 表示不设截止日期 |

```json
{"title":"完成 Todo 项目","description":"分阶段完成","deadline":"2026-12-31"}
```

新建成功：`{"code":0,"msg":"Goal created","data":{"id":10}}`。

编辑为**完整替换这些可编辑字段**，不是 PATCH；省略说明会清空说明，省略日期会清空日期。重复提交相同内容仍成功：`{"code":0,"msg":"Goal updated"}`。修改目标名称会同步体现在每日任务的 `goal_title` 中。

### 9.4 新建和编辑子任务

**`POST /api/goals/{goal_id}/tasks`** 新建；**`PUT /api/goals/tasks/{task_id}`** 编辑。

| JSON 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `content` | string | 是 | 去除首尾空白后非空，最多 500 个 Unicode 字符 |
| `deadline` | string / null | 否 | 子任务自己的截止日期；可晚于目标截止日期，缺省或 null 表示不设日期 |

```json
{"content":"完成登录模块","deadline":null}
```

新建成功：`{"code":0,"msg":"Goal task created","data":{"id":101}}`。

编辑成功：`{"code":0,"msg":"Goal task updated"}`。编辑会完整替换内容和日期，不能通过此接口更改归属目标或完成状态；内容和日期同步体现在已有的每日关联中。

### 9.5 完成和取消完成

**`PUT /api/goals/tasks/{task_id}/status`**。

```json
{"is_completed":true}
```

`is_completed` 必须为 JSON 布尔值。成功：`{"code":0,"msg":"Goal task status updated"}`。传 `false` 取消完成，进度同步回退；同一状态重复提交成功。也可通过第 4.3 节的每日记录接口完成关联子任务，两处共用一个持久状态。

### 9.6 加入我的一天

**`POST /api/goals/tasks/{task_id}/myday`**，无正文。

成功：`{"code":0,"msg":"Goal task added to My Day"}`。重复请求不产生重复记录；完成后刷新 `/api/myday` 与 `/api/goals`，获取每日记录 ID 和今天选取标记。

已完成的子任务不能再次加入今天，返回 HTTP 409、`code: 409`、`msg: "Completed task cannot be added to My Day"`；需要先取消完成。已过期但未完成的子任务可以加入今天。

### 9.7 删除

| 方法 | 路径 | 成功结果 |
| --- | --- | --- |
| DELETE | `/api/goals/{goal_id}` | 删除目标、全部子任务、全部日期的每日关联，`msg: "Goal, child tasks and daily references deleted"` |
| DELETE | `/api/goals/tasks/{task_id}` | 删除指定子任务及全部每日关联，`msg: "Goal task and daily references deleted"` |

无正文，成功均为 HTTP 200、`code: 0`。其他目标、普通任务模板、临时每日任务、便签和共享文件不受影响。前端执行删除前展示范围确认，成功后同时刷新目标、任务池和当天列表。

### 9.8 错误与同步边界

| HTTP / code | 条件 |
| --- | --- |
| 400 | 参数缺失、空白内容、超长内容、非法日期、非正数或超出 64 位范围的路径 ID |
| 401 | Access Token 缺失、无效或过期 |
| 404 | 目标或子任务不存在，或不属于当前用户；不区分这两种情况 |
| 409 | 已完成子任务请求加入今天 |
| 500 | 数据库异常 |

各端通过同一服务端数据同步；当前没有 WebSocket 推送。操作成功后刷新相关视图，切回应用、跨天或手动刷新时重新查询。任务日期统一按北京时间 04:00 切换，不受 MySQL 默认 UTC 或设备时区影响。前端保持打开时会检查任务日变化并刷新。

## 10. 对接边界与待部署验证项

1. **没有实现的能力**：任务池重命名、模板内容修改、我的一天任务删除/内容编辑、按日期查询、便签详情单独查询、文件重命名、分页搜索均未注册接口。不要从 REST 命名习惯推断它们存在。
2. **创建后刷新列表**：任务池、模板、今日任务、便签创建成功均只返回 `code` 和 `msg`；文件上传虽然有 `data`，也不返回 ID。需要重新查询列表获得服务端 ID。
3. **权限范围不同**：任务池、今日任务和便签按当前用户隔离；原文件接口保持登录鉴权；新增公开只读接口允许访客查看及下载全部共享文件；文件删除仍限制上传者本人。
4. **日期和更新时间**：本次起今日任务和目标统一在北京时间 04:00 跨天，既有每日任务日期不重写；便签更新时间、文件上传时间仍依赖数据库定义。
5. **错误处理**：既检查 HTTP 状态又检查 JSON `code`；受影响行数为 0 的更新可能被当成未找到。文件接口还要处理非 JSON 响应。
6. **跨域**：主程序添加 `Access-Control-Allow-Origin: *`、允许方法 `OPTIONS, GET, POST, PUT, DELETE`，允许请求头 `Content-Type, Authorization`；未见显式 OPTIONS 业务路由或暴露 `Content-Disposition` 的响应头配置。浏览器预检与下载文件名读取需结合框架/代理实测。
7. **数据一致性**：删除任务池、文件保存和删除涉及多步操作，源码没有显式事务或完整补偿。发生中途错误后应重新读取状态，不假定全成功或全回滚。

## 11. 源码索引

以下链接固定到本次后端提交，与本文接口说明对应：

| 文档内容 | 源码 |
| --- | --- |
| 注册、登录、刷新 | [AuthController.cc](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/controllers/AuthController.cc) |
| 任务池及模板 | [TaskPoolController.cc](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/controllers/TaskPoolController.cc) |
| 我的一天 | [MyDayController.cc](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/controllers/MyDayController.cc) |
| 长期目标和子任务 | [GoalController.cc](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/controllers/GoalController.cc)、[GoalUtil.h](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/utils/GoalUtil.h) |
| 北京时间 04:00 任务日 | [TaskDate.h](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/utils/TaskDate.h) |
| 级联关系和每日唯一索引 | [001_long_term_goals.sql](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/migrations/001_long_term_goals.sql) |
| 便签 | [NotesController.cc](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/controllers/NotesController.cc) |
| 共享文件 | [FileController.cc](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/controllers/FileController.cc) |
| 打赏二维码 | [DonateController.cc](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/controllers/DonateController.cc) |
| 鉴权请求头与 HTTP 401 | [AuthFilter.h](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/middleware/AuthFilter.h) |
| Token 签发、有效期及验证 | [JwtUtil.cc](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/utils/JwtUtil.cc) |
| 端口、请求体上限、CORS | [main.cc](https://github.com/liuxingboy/todo-backend/blob/12d33119429e3791d7c04624165f8103d7cc30c1/main.cc) |
