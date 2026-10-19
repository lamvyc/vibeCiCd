# ADR-006：接入现有 lowCode-platform 应用

- 状态：**已确认（2026-10-19，用户选择接入现有应用）**
- 日期：2026-10-19
- 相关：`docs/phase-1/01-app-assessment.md`、ADR-001/002/003

## 背景

用户指定接入 `/Users/unravel/ lowCode-platform`（目录名带前导空格）。该仓库是 pnpm + Vue 3 + Vite 的前端 monorepo，`main` 分支干净，含 7 个 workspace 包、58 个测试文件、约 2.2 MB 的前端构建产物；**没有后端、Dockerfile、K8s 清单或 CI 配置**。

原阶段 0 方案假设自建 Go 服务，需要修订：应用不可改写为后端服务，部署物是静态 SPA。

## 决策

1. **不修改应用源码**：CI/CD 文件放平台仓库 `vibe-cicd`；Gitea 中的应用仓库来自本地克隆，仅作为构建源。
2. **两仓库**：
   - `lowcode-platform`：应用源码，webhook 触发 CI。
   - `vibe-cicd`：Jenkinsfile、Go 静态服务器、Dockerfile、GitOps 清单、脚本/文档；Argo CD 只读。
3. **镜像 = Go 静态服务器 + `packages/playground/dist`**，`scratch`、非 root。避免 nginx/node 基础镜像（Docker Hub 不可达），也不改应用。
4. **CI 质量门禁**：`pnpm install --frozen-lockfile`、`pnpm -r typecheck`、58 个 Vitest 测试、`pnpm -r build`、Go server 测试；全部通过才构建/推送镜像。首版不引入 ESLint/coverage 依赖。
5. **触发**：应用仓库 Gitea webhook（push + pull_request）→ Jenkins Generic Webhook Trigger → Pipeline from SCM（平台仓库）。平台仓库不配置 webhook，避免 GitOps bot 提交触发 CI。
6. **部署**：静态 SPA；关键验证为 `/`（HTML/资源）、`/healthz`、`/readyz`、`/api/version`、`/metrics`；不虚构不存在的后端 API。

## 备选方案

| 方案 | 不选原因 |
|---|---|
| 在应用仓库加 Dockerfile/Jenkinsfile | 修改用户仓库；CI 文件与应用耦合；原仓库保持干净的约束 |
| 复制应用源码到 `vibeCiCd/app` | 双份源码漂移；大仓库；更新需手工同步 |
| 用 nginx/node 基础镜像 | 依赖 Docker Hub；当前不可达；镜像更大 |
| 用 Vite preview 作为生产服务 | 开发服务器，不适合生产；需要 Node 基础镜像 |
| 让应用新增后端 | 超出用户项目范围，改变应用架构 |

## 影响

- 正面：不碰应用源码；构建真实产物；两仓库职责清晰；镜像小且无基础镜像依赖。
- 负面：应用仓库是克隆副本，需同步；静态服务器是平台代码，需要测试；无 ESLint/coverage；纯前端没有真实业务 API。
- 迁移：若应用后续提供服务端/SSR，替换镜像运行层即可；若需要独立部署仓库，Gitea 两仓库已分离。

## 验证要求

- 预检（install/typecheck/test/build）结果记录；失败先定位，不降门禁。
- 镜像能启动并返回 HTML/健康/版本/指标；非 root；无应用源码/密钥。
- PR 构建不改 GitOps、不 push 镜像；main 才发布。
- 静态子路径回退有测试；`/api/*` 404 不返回 index.html。

## 实施结果（2026-10-20）

- 应用仓库未修改；Gitea 托管克隆；CI 使用 pnpm 9.15.0 / Node 24.18.0，538 tests 通过。
- 镜像 = Go 静态服务器 + `packages/playground/dist`，scratch、非 root；最终 digest 见 `docs/versions.lock.md`。
- Gitea 迁入 Colima VM（host network），使 Argo CD 可访问；宿主 Jenkins 通过 SSH local forward 访问。
- Webhook 受沙箱 egress 限制，使用 Gitea API 轮询桥作为自动触发回退。
