这份清单不仅是你 C++ 后端心血的结晶，更是接下来我们用 Flutter 编写前端网络请求时最重要的“施工图纸”。

目前你的后端一共包含 **4 个核心模块**，总计 **13 个 API 接口**。除了注册和登录，其余 11 个接口全部受到全局 JWT 中间件 (`AuthFilter`) 的严格保护，必须在请求头中携带 `Authorization: Bearer <token>` 才能访问。

以下是完整的接口全景图：

### 1. 鉴权与用户模块 (Auth)
负责用户的通行证发放，是整个系统的安全大门。
| 方法名            | 路径                   | HTTP 方法 | 功能说明                                                                                         |
| -------------- | -------------------- | ------- | -------------------------------------------------------------------------------------------- |
| `registerUser` | `/api/auth/register` | POST    | 用户注册，接收 JSON `{ "username": "...", "password": "..." }`，返回注册结果。                              |
| `loginUser`    | `/api/auth/login`    | POST    | 用户登录，接收 JSON `{ "username": "...", "password": "..." }`，返回 `access_token` 与 `refresh_token`。 |

### 2. 任务池模块 (Task Pools)
| 方法名             | 路径                | HTTP 方法 | 功能说明                                                         |
| --------------- | ----------------- | ------- | ------------------------------------------------------------ |
| `getPools`      | `/api/pools`      | GET     | 获取当前用户所有任务池及池内模板任务。                                          |
| `createPool`    | `/api/pools`      | POST    | 创建新的任务池（如“英语学习”），接收 JSON `{ "pool_name": "..." }`。           |
| `addTaskToPool` | `/api/pools/task` | POST    | 向指定任务池添加任务模板，接收 JSON `{ "pool_id": 123, "content": "..." }`。 |

### 3. 我的一天模块 (My Day) - 🌟 核心引擎
| 方法名          | 路径           | HTTP 方法 | 功能说明                                                        |
| ------------ | ------------ | ------- | ----------------------------------------------------------- |
| `getNotes`   | `/api/notes` | GET     | 获取用户所有便签，按更新时间倒序。                                           |
| `createNote` | `/api/notes` | POST    | 创建便签，接收 JSON `{ "content": "..." }`。                        |
| `updateNote` | `/api/notes` | PUT     | 修改便签内容，接收 JSON `{ "note_id": 123, "content": "..." }`，防止越权。 |
| `deleteNote` | `/api/notes` | DELETE  | 删除便签，接收 JSON `{ "note_id": 123 }`，防止越权。                     |


### 4. 灵感便签模块 (Notes)
| 方法名                  | 路径                  | HTTP 方法 | 功能说明                                                               |
| -------------------- | ------------------- | ------- | ------------------------------------------------------------------ |
| `getTodayTasks`      | `/api/myday`        | GET     | 获取当天的任务列表，返回每条任务状态。                                                |
| `addTaskToMyDay`     | `/api/myday`        | POST    | 添加任务到“我的一天”，接收 JSON `{ "content": "..." }`。                        |
| `toggleTaskStatus`   | `/api/myday/status` | PUT     | 更新任务完成状态，接收 JSON `{ "task_id": 123, "is_completed": true/false }`。 |
| `importTaskFromPool` | `/api/myday/import` | POST    | 从任务池导入模板任务到当天任务，接收 JSON `{ "pool_task_id": 123 }`，防止越权。            |


### 接口文档 (删除任务池 API)

* **功能描述**: 删除指定的任务池，并级联清空池内所有任务。
* **请求路径**: `/api/pools`
* **请求方法**: `DELETE`
* **请求头 (Headers)**:
    * `Content-Type: application/json`
    * `Authorization: Bearer <动态获取本地的 access_token>`
* **请求体 (Request Body)**:
    ```json
    {
      "pool_id": 1  // 要删除的任务池 ID
    }
    ```

* **成功返回示例**:
    ```json
    {
      "code": 0,
      "msg": "Pool and its tasks deleted successfully"
    }
    ```

**前端交互要求：**
接口返回 `code == 0` 后，请把这个任务池从本地 UI 列表里移除，并弹出绿色 SnackBar 提示删除成功。如果报错，弹出红色错误信息。



我们需要在页面中（比如侧边栏抽屉 Drawer，或者“我的”个人中心页面）增加一个“打赏作者”的按钮。
点击按钮后，弹出一个优雅的 Dialog（对话框）或者 BottomSheet，展示后端的收款二维码图片，并在图片下方配上一句感谢语：“感谢支持独立开发！”。

### 接口文档 (获取打赏二维码图片)

* **功能描述**: 直接返回收款二维码的图片流。
* **资源 URL**: `http://<替换为服务器公网IP>:8080/api/donate/qr`
* **请求方法**: `GET`
* **鉴权限制**: 无（公开接口）

**前端交互与代码要求：**
1. 在 Flutter 中，你不需要使用网络库去手动下载二进制流。
2. 请直接使用 `Image.network('http://<替换为服务器公网IP>:8080/api/donate/qr')` 组件来渲染这张图片。
3. 请为图片加上一个 `loadingBuilder`（加载中的 loading 动画）和 `errorBuilder`（如果图片加载失败，显示一个裂开的图标和“二维码加载失败”的提示）。