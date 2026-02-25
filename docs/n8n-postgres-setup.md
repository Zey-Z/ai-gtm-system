# 在 n8n 里连接 PostgreSQL 数据库

## 阶段 1：配置数据库连接

### 步骤 1：打开你的 n8n

1. 打开浏览器，访问 `http://localhost:5678`
2. 这是你已经在用的 n8n 实例

---

### 步骤 2：添加 PostgreSQL Credential

1. **点击右上角的个人头像** → 选择 **Settings（设置）**
2. 在左侧菜单点击 **Credentials（凭证）**
3. 点击右上角的 **+ Add Credential（添加凭证）** 按钮
4. 在搜索框输入 `postgres`，选择 **Postgres**

---

### 步骤 3：填写数据库连接信息

在弹出的配置页面，填写以下信息：

| 字段 | 填写内容 | 说明 |
|------|---------|------|
| **Credential Name** | `AI GTM PostgreSQL` | 随便起个名字 |
| **Host** | `host.docker.internal` | 重要！Docker 容器间通信 |
| **Database** | `aigtm` | 数据库名 |
| **User** | `aigtm_user` | 用户名 |
| **Password** | `aigtm_secure_pass_2024` | 密码（在 .env 文件里） |
| **Port** | `5432` | PostgreSQL 默认端口 |
| **SSL Mode** | `disable` | 本地开发不需要 SSL |

> **重要提示：** Host 填 `host.docker.internal` 而不是 `localhost`！
> 这是因为你的 n8n 容器需要访问另一个 PostgreSQL 容器。

---

### 步骤 4：测试连接

1. 填完信息后，点击页面最下方的 **Test Connection（测试连接）** 按钮
2. 如果看到绿色的 ✅ 成功提示，说明连接成功！
3. 点击 **Save（保存）** 按钮

---

## 常见问题

### 问题 1：连接失败，提示 "connection refused"

**解决方法：**
- 检查 Host 是否填写了 `host.docker.internal`
- 如果还是不行，试试用 `172.17.0.1`（Docker 默认网关）
- 或者运行这个命令查看 PostgreSQL 容器的 IP：
  ```bash
  docker inspect aigtm_postgres | grep IPAddress
  ```

### 问题 2：连接失败，提示 "authentication failed"

**解决方法：**
- 检查用户名是否是 `aigtm_user`
- 检查密码是否是 `aigtm_secure_pass_2024`
- 检查数据库名是否是 `aigtm`

---

## 下一步

连接成功后，我们会创建一个测试 workflow 来验证数据库读写。
