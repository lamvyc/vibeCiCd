# Phase 1：应用接入评估与设计修订

> 日期：2026-10-19。对象：`/Users/unravel/ lowCode-platform`（注意目录名带**前导空格**）。
> 本文件是阶段 0 设计在「应用范围」上的修订；未变更的架构/安全/验收原则仍以 `docs/phase-0/` 为准。

## 1. 只读检查结果

| 项 | 结果 |
|---|---|
| 实际路径 | `/Users/unravel/ lowCode-platform`（`/Users/unravel/lowCode-platform` 不存在） |
| Git | 是；分支 `main`；工作区**干净**；最近提交 `51de0d5`；远端 `https://github.com/lamvyc/-lowCode-platform.git` |
| 规模 | 325 个受版本控制文件；总目录约 453 MB（含 `node_modules` 219 MB）；`packages/` 约 20 MB |
| 技术栈 | pnpm 9.15.0 workspace；Node 24.18.0；TypeScript 5.6；Vue 3.5；Vite 6；Vitest 2.1；happy-dom |
| 包 | `schema`、`core`、`runtime`、`materials`、`codegen`、`editor`、`playground` 共 7 个 workspace 包 |
| 测试 | 58 个 `*.test.ts` / `*.spec.ts`；`pnpm -r test` |
| 类型检查 | `pnpm -r typecheck`（Vue 包用 `vue-tsc`） |
| 构建 | `pnpm -r build`；前端产物 `packages/playground/dist`（约 2.2 MB，`index.html` + assets） |
| 后端 | **无**；是纯前端低代码平台/设计器，部署物是静态 SPA |
| 包管理 | `.npmrc` 指向 `https://registry.npmjs.org/`；本次探测可达（约 6.9 s 延迟） |
| 现有 CI/CD | 未发现 Jenkinsfile/Dockerfile/K8s 清单；本次不修改应用源码 |

## 2. 接入决策

### 2.1 不改原仓库

- 原仓库保持干净；所有 CI/CD 文件放在 `vibeCiCd` **平台仓库**。
- 在 Gitea 建立应用仓库 `lowcode-platform`：从本地仓库克隆后推送，作为 CI 的构建源；原 GitHub 远端不变。
- 若应用后续更新，需把新提交同步到 Gitea（或配置镜像/remote）；这是本地实验的已知边界，写入 runbook。

### 2.2 两仓库职责

| 仓库 | 位置 | 职责 | 谁写入 |
|---|---|---|---|
| `lowcode-platform` | Gitea（源自本地克隆） | 应用源码、锁文件、测试；不含环境状态 | 开发者；本次只读消费 |
| `vibe-cicd` | Gitea（`vibeCiCd` 工作区） | Jenkinsfile、JCasC、Go 静态服务器、Dockerfile、GitOps 清单、脚本/文档 | 平台维护者；Jenkins 只写 `gitops/` 镜像字段 |

这解决了单仓库 bot 提交触发 CI 回路的问题：应用仓库 webhook 触发 CI；平台仓库不被 webhook 监听，Argo CD 只读平台仓库的 `gitops/`。

### 2.3 部署物：静态 SPA + Go 包装服务器

应用没有后端，直接部署 `dist` 需要静态服务器。基础镜像（nginx/node）在 Docker Hub 不可达，因此：

- 在平台仓库新增 `platform/server/`：Go 标准库静态服务器，提供：
  - `/healthz`、`/readyz`（可注入失败，用于演练）
  - `/api/version`（版本/commit/buildTime/env）
  - `/metrics`（Prometheus 文本）
  - `/` 与静态资源；非 API 路径回退到 `index.html`（SPA）
  - JSON 请求日志、优雅关闭、请求计数/时延直方图
- 构建：`CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build` → 与 `dist/` 一起放入 `scratch` 镜像。
- 镜像：非 root（65532）、无 shell、无源码/密钥；仅 `server` + `static/`。
- 这样既保留真实应用的构建产物，又不修改应用代码，也不依赖 Docker Hub 基础镜像。

### 2.4 CI 流水线（修订）

```text
Gitea app webhook (push / pull_request)
  → Jenkins job（Pipeline from SCM: vibe-cicd/ci/Jenkinsfile）
  → checkout 平台仓库（Jenkinsfile/server/gitops）
  → checkout 应用仓库到 app/（按 webhook ref/SHA）
  → pnpm install --frozen-lockfile
  → pnpm -r typecheck
  → vitest (JUnit) / pnpm -r test
  → pnpm -r build → packages/playground/dist
  → go test ./... (platform/server)
  → 质量门禁（typecheck/test/build 全绿 + dist 完整）
  → 组装镜像上下文 → docker build（scratch）→ 运行/健康/版本校验
  → main：push 到 Zot → 解析 digest → 更新 gitops/overlays/dev → 等 Argo CD → 部署验证
  → PR/feature：到此结束，不 push、不部署
```

- Node 版本：24.18.0；pnpm 9.15.0（与 `packageManager` 一致）。Jenkins 节点固定 PATH，流水线首步打印版本。
- 质量门禁：应用没有 ESLint/coverage 脚本；首版用 **typecheck + 58 个测试 + build**，不擅自引入新依赖。覆盖率/SonarQube 作为后续增强（ADR-004/005）。
- 测试报告：优先 `vitest run --reporter=junit`；若 workspace 模式无法汇总，则保留 `pnpm -r test` 控制台 + 退出码，并在文档中说明。实现时以实际输出为准。
- 发布条件：`APP_EVENT == push && APP_REF == refs/heads/main && APP_PR == 0`。
- PR 构建：checkout PR head SHA；只验证，不 push；状态回传 Gitea。
- 分支保护：`main` 需要 PR + `ci/jenkins` 状态成功。
- 镜像标签：`sha-<app-sha12>`；GitOps 写 `tag@digest`。

### 2.5 命名与端口

| 项 | 值 |
|---|---|
| 应用仓库 | `lowcode/lowcode-platform`（Gitea org `lowcode`） |
| 平台仓库 | `lowcode/vibe-cicd` |
| 镜像 | `localhost:5001/lowcode-platform` |
| 命名空间 | `lowcode-dev`、`lowcode-prod` |
| Service | `lowcode-web`，80→8080 |
| NodePort | dev 30080、prod 30081（可改） |
| 健康接口 | `/healthz`、`/readyz` |
| 版本/指标 | `/api/version`、`/metrics` |

## 3. 预检（实施前）

在克隆 `.runtime/repos/lowcode-platform`（不改原仓库）执行：

```bash
pnpm install --frozen-lockfile
pnpm -r typecheck
pnpm -r test
pnpm -r build
```

结果记录：

| 步骤 | 状态 | 证据 |
|---|---|---|
| pnpm install | **通过**（1m 1.2s，146 个包，干净克隆） | `.runtime/logs/app-precheck.log` |
| typecheck | **通过**（7/8 workspace 项目；`tsc`/`vue-tsc`） | 同上 |
| test | **通过**（58 个测试文件；538 passed，2 skipped，0 failed） | 同上 |
| build | **通过**（Vite 6.4.3，1998 modules，3.44s） | 同上 |
| dist 产物 | **通过**（`packages/playground/dist/index.html` + assets，约 2.6 MB） | `ls -lh .runtime/repos/lowcode-platform/packages/playground/dist` |

> 若 typecheck/test 失败：先判断是应用既有问题还是环境问题；不通过降低门禁来「修复」。需要修改应用源码时单独向你确认。

## 4. 风险与边界

| 风险 | 影响 | 处理 |
|---|---|---|
| npm registry 慢（本次 6.9 s） | `pnpm install` 时间长/超时 | 使用 pnpm store 缓存；Jenkins 超时 30 min；失败重试；记录耗时 |
| Node 24 与项目开发版本差异 | 类型/构建差异 | 流水线打印版本；必要时用 `package.json` engines/`.nvmrc`（需应用仓库变更，先确认） |
| 58 个测试 + vue-tsc 较慢 | CI 时长 | 并行/缓存；超时；不在每次构建重复安装 |
| 无 ESLint/coverage | 质量门禁较弱 | typecheck+test+build 作为首版；后续加 lint/coverage（ADR-004） |
| 纯前端无业务 API | 关键接口只有静态页/健康/版本 | 验收访问 `/`、静态资源、`/api/version`；不虚构后端接口 |
| Gitea 应用仓库是克隆副本 | 原仓库后续提交不会自动出现 | runbook 写同步命令；后续可配 mirror/remote |
| SPA 路由 | 刷新子路径 404 | Go 服务器对非 API 路径回退 `index.html`；测试覆盖 |
| 静态资源缓存 | 旧资源 | hashed assets 长缓存；`index.html` no-cache |
| 前端体积 2.2 MB | 首屏 | 不在本项目优化应用；镜像大小仍很小 |

## 5. 与阶段 0 设计的差异

| 项 | 阶段 0 基线 | Phase 1 修订 |
|---|---|---|
| 应用 | Go `release-demo` | 现有 Vue/pnpm `lowcode-platform` |
| 仓库 | 单仓库 | 应用仓库 `lowcode-platform` + 平台/GitOps 仓库 `vibe-cicd` |
| 构建 | Go 编译 | pnpm install/typecheck/test/build + Go 包装服务器 |
| 镜像 | 单 Go 二进制 | Go 静态服务器 + 前端 `dist`（scratch） |
| 质量门禁 | gofmt/vet/test/coverage | typecheck + 58 tests + build + server tests（无 coverage） |
| 关键接口 | `/healthz`、`/api/version` | 同上 + `/` 静态页/SPA 回退 |
| 触发 | 单仓库分支/PR | 应用仓库 webhook → 平台仓库 Jenkinsfile；平台仓库不被监听 |

其余（Docker/Zot/K8s/Argo CD/Prometheus/安全/验收）不变。
