# 阶段 0：实施计划

> 前置：`docs/phase-0/02-solution-design.md` 经确认。当前**未安装、未启动**任何服务；本文件中的命令是计划，不是执行记录。
> 原则：每个阶段有输入、输出、验证命令和完成标准；关键能力必须有可复核证据；失败先定位再继续。

## 0. 总体路线与决策门

```text
Phase 0  分析/设计（本次，待确认）
   ↓
Phase 1  工具链 + Colima + Gitea + Jenkins + Go 应用 + CI（lint/test/build/报告/PR）
   ↓
Phase 2  Docker 镜像 + Zot + 推送/拉取/启动验证 + 安全基线与认证
   ↓
Phase 2.5 部署目标 spike（时间盒 60–90 分钟）
   ├─ 通过：k3s + Argo CD 路径 → Phase 3K/4K
   └─ 不通过：Docker Compose 部署路径 → Phase 3C/4C（K8s/Argo CD 标记受环境限制）
   ↓
Phase 3  部署基线（K8s 清单 + 手工 apply/port-forward 验证，或 Compose 基线）
   ↓
Phase 4  CD：Argo CD GitOps（或 Compose 发布+回滚）
   ↓
Phase 5  质量门禁强化 + Prometheus/日志/部署记录 + 故障演练
   ↓
Phase 6  端到端验收 + 文档 + 交接
```

**Phase 2.5 是唯一允许改变部署目标架构的决策点**；通过/不通过都要把证据写入 `docs/verification/`，不得静默切换。

## 1. 工具链与环境（Phase 1 前置）

### 1.1 方案 A（推荐）：Homebrew 安装运行时/工具

需要一次更宽文件权限（`/opt/homebrew`、Homebrew 缓存）。安装清单（版本安装时锁定并写入 `versions.lock`）：

```bash
brew install colima lima docker kubectl kustomize helm go
# 可选：kind / k3d 作为 Phase 2.5 备选
```

- Jenkins/Gitea 不通过 brew 服务运行，使用项目内数据目录和明确版本，避免全局服务与端口冲突。
- 优点：官方校验、升级/卸载清晰、Lima/VZ 依赖完整。
- 风险：Homebrew 版本漂移；需记录实际版本；安装是全局变更，需确认。

### 1.2 方案 B：项目内便携工具链

- 下载到 `.tools/`，`versions.env` 固定版本 + SHA256；`COLIMA_HOME`、`LIMA_HOME` 指到 `.runtime/`。
- 需要：Colima/Lima 官方二进制、Docker CLI、kubectl、kustomize、Go、Jenkins WAR、Gitea 二进制、Argo CD CLI。
- 优点：不写全局路径、易清理；缺点：VM 镜像/依赖兼容性需自己处理，脚本更多。
- 仅在方案 A 不被允许或失败时采用。

### 1.3 安装后必须验证

| 检查 | 命令 | 通过标准 |
|---|---|---|
| Colima | `colima status` | Running；VM arch=aarch64 |
| Docker | `docker version --format '{{.Server.Version}} {{.Server.Arch}}'` | 有 Server 版本、arch=arm64 |
| K8s（可选） | `kubectl get nodes -o wide` | 单节点 Ready（若启用 K8s） |
| 端口 | `lsof -nP -iTCP:8081 -iTCP:3000 -iTCP:5001 -sTCP:LISTEN` | 不冲突（8080/5000 已占用，避开） |
| 资源 | `colima ssh -- free -h` / `df -h` | VM 内存/磁盘在预算内 |
| 网络 | 拉取一个 ghcr/quay 测试镜像 | 成功；不依赖 Docker Hub |

## 2. Phase 1：最小 CI 闭环

**输入**：工具链可用；Gitea/Jenkins 版本确定；应用骨架。
**输出**：Gitea 仓库 + 分支保护；Jenkins 任务；Jenkinsfile；CI 成功/失败证据；测试报告。

### 任务

1. **项目骨架**：`app/`（Go 模块、HTTP 服务、测试）、`ci/Jenkinsfile`、`scripts/`、`docs/`、`.gitignore`、`.env.example`。
2. **Gitea**：
   - 生成 `.env.local`（随机 admin 密码、token）；启动 Gitea（`GITEA__database__DB_TYPE=sqlite3`、`ROOT_URL=http://localhost:3000/`）。
   - 创建管理员/组织/仓库；导入初始代码；创建 `main` 保护规则（PR + 状态检查）。
   - 配置 webhook 到 Jenkins；验证 ping/delivery。
3. **Jenkins**：
   - 下载/运行 `jenkins.war` 2.580.1；`JENKINS_HOME=.runtime/jenkins`；端口 8081。
   - 安装插件（锁定版本）：`configuration-as-code`、`workflow-aggregator`、`git`、`credentials-binding`、`junit`、`timestamps`、`ws-cleanup`、`gitea`（若兼容）或 `generic-webhook-trigger`。
   - JCasC：管理员、凭据（Gitea token、registry、GitOps token）、节点标签、并发/丢弃策略。
   - 建立 Multibranch Pipeline（Gitea SCM）或 Generic Webhook Pipeline（备选）；验证分支/PR 发现。
4. **Jenkinsfile**：Checkout → Classify → Lint → Test（JUnit/覆盖率）→ Build → Quality Gate；PR/feature 到此结束；失败终止。
5. **状态回传**：Gitea commit status（pending/success/failure）在关键阶段更新；PR 页面可见。
6. **失败验证**：提交一个测试失败/格式错误的分支，确认流水线在 Test/Lint 失败、没有进入构建/推送；记录日志。

### 验证命令（示例）

```bash
curl -fsS http://localhost:3000/api/v1/version
curl -fsS -u "$JENKINS_USER:$JENKINS_TOKEN" http://localhost:8081/api/json?tree=jobs[name]
# 触发后：
curl -fsS -u ... "http://localhost:8081/job/<job>/lastBuild/api/json?tree=result,stages"
```

### 完成标准

- [ ] Gitea 可登录；仓库有初始提交；webhook delivery 成功。
- [ ] Jenkins 可登录；JCasC 生效；凭据不落盘明文。
- [ ] 正常分支 CI 成功；失败分支在正确 stage 失败；PR 状态正确。
- [ ] JUnit/覆盖率报告可下载；日志能定位失败步骤。
- [ ] 未安装/未启动的服务不写入完成声明。

## 3. Phase 2：镜像构建与仓库

**输入**：CI 成功；Go 静态二进制可构建；Colima Docker 可用。
**输出**：scratch 镜像；Zot 仓库（认证）；推送/拉取/启动证据；镜像 digest。

### 任务

1. 编写 `app/Dockerfile`（scratch、非 root、OCI labels、仅二进制）与 `.dockerignore`。
2. 启动 Zot（`ghcr.io/project-zot/zot:2.1.22`），配置 htpasswd、端口 5001、存储卷；生成随机密码。
3. 配置 Colima Docker 的 insecure registry（`localhost:5001`，仅本地 loopback）并验证 `docker login`。
4. Jenkinsfile 增加 Docker Build → Image Verify → Push（仅主分支）→ 清理/重拉/启动验证。
5. 镜像标签：`sha-<12>`（主分支）、`vX.Y.Z`（tag）；解析 `tag@digest`；记录到 `versions.lock`/部署记录。
6. 安全验证：`docker inspect` 确认 `User=65532`；`docker run` 后 `id` 不存在（scratch）→ 用 `/api/version` 与进程用户检查；确认镜像无 `.git/.env/key`。
7. 未认证 `docker pull` 失败、认证成功；K8s imagePullSecret 预演（Phase 3 使用）。

### 验证命令（示例）

```bash
docker build -t localhost:5001/release-demo:sha-<sha> app/
docker push localhost:5001/release-demo:sha-<sha>
docker rmi localhost:5001/release-demo:sha-<sha>
docker pull localhost:5001/release-demo@sha256:<digest>
docker run --rm -d -p 18080:8080 --name rd localhost:5001/release-demo@sha256:<digest>
curl -fsS localhost:18080/healthz && curl -fsS localhost:18080/api/version
docker image inspect localhost:5001/release-demo:sha-<sha> --format '{{.Config.User}} {{.Size}}'
```

### 完成标准

- [ ] 镜像可构建、推送、删除后重新拉取、启动、通过健康/版本接口。
- [ ] 未认证拉取被拒绝；认证成功。
- [ ] 镜像非 root、无密钥/源码、体积合理（目标 <30 MB）。
- [ ] digest 与 Git commit 关联并可追溯。
- [ ] 测试失败时不会产生镜像（Phase 1/2 联合验证）。

## 4. Phase 2.5：部署目标 spike（决策门）

**时间盒**：60–90 分钟；只做可行性验证，不写完整流水线。

### 候选顺序

1. **k3s（Colima 内置）+ 本地 Zot**
   - `colima start --kubernetes --k3s-version v1.35.3+k3s1`（具体参数以 Colima 0.10.3 为准）。
   - 检查 `kubectl get pods -A`；重点：CoreDNS/pause 是否 ImagePullBackOff。
   - 若系统镜像拉取失败：尝试 k3s airgap 镜像包；若不可得，禁用非必要 addon（traefik/servicelb/metrics-server/local-path），用本地 Zot 提供 CoreDNS/pause；记录来源与 digest。
   - 部署一个测试 Pod/Deployment（使用本地 registry 的镜像），验证 imagePullSecret。
2. **k3d（备选）**：`k3d cluster create --image ghcr.io/k3s-io/k3s:v1.35.3-k3s1 --registry-create ...`；验证系统 Pod 与 registry 连通。
3. **kind（备选）**：仅当能取得 `kindest/node` 且系统镜像可用；否则不采用。

### 通过标准

- 节点 Ready；CoreDNS/必要系统 Pod Running；能拉取本地 registry 镜像；Service/port-forward 可访问测试应用。
- 记录：K8s 版本、节点镜像来源、系统镜像来源/digest、registry 配置、失败与解决。

### 不通过时

- 不强行拼凑；切换 **Docker Compose 部署**（Phase 3C/4C），在文档中标注：
  - 已实现：镜像、Compose 部署、健康/接口验证、回滚、失败演练。
  - 未实现/受环境限制：K8s 编排、Argo CD GitOps、漂移检测。
  - 后续条件：可用 K8s 集群或镜像来源后，按 Phase 3K/4K 迁移。

## 5. Phase 3K：K8s 部署基线（若 spike 通过）

**输入**：K8s Ready；镜像 digest；imagePullSecret。
**输出**：dev/prod 清单；手工部署成功；健康/接口验证；失败现象记录。

### 任务

1. `gitops/base`：Deployment（2 副本、探针、resources、securityContext）、Service、ConfigMap、kustomization。
2. `gitops/overlays/dev`、`prod`：命名空间、副本/资源/环境变量差异；镜像占位。
3. `gitops/argocd`：AppProject + Application（dev 自动；prod 手动 sync）。
4. 手工 `kubectl apply -k gitops/overlays/dev`（仅基线验证，后续由 Argo CD 接管）；创建 namespace/imagePullSecret。
5. 验证：Pod Ready、`/healthz`、`/readyz`、`/api/version`、日志无敏感信息；故意设置错误镜像验证 ImagePullBackOff 与事件收集。
6. 记录：`kubectl get all`、events、describe、curl 输出。

### 完成标准

- [ ] dev 命名空间 Deployment 可用副本=期望；探针通过。
- [ ] 通过 port-forward 访问健康/版本接口；版本=镜像 commit。
- [ ] 错误镜像/错误探针的失败现象可复现并可定位。
- [ ] prod 清单存在但**不自动部署**（权限/审批边界清晰）。

## 6. Phase 4K：Argo CD GitOps（若 spike 通过）

**输入**：Argo CD 已部署（quay 镜像）；Gitea repo token；GitOps 仓库/目录。
**输出**：Application Synced/Healthy；镜像更新自动同步；漂移自愈；Git 回滚证据。

### 任务

1. 安装 Argo CD v3.5.0（官方 install.yaml 或 kustomize；记录镜像 digest）；暴露用 port-forward（不默认 NodePort）。
2. 创建 `AppProject`（限制 sourceRepos/destinations）与 `repo` Secret（Gitea 只读 token；不写 Git）。
3. 创建 dev/prod `Application`；dev `automated {prune, selfHeal}`，prod 手动。
4. Jenkins 增加 GitOps Update：Kustomize 写入 `image:tag@digest`，提交 `[skip ci]`，push；轮询 Argo CD 状态。
5. 验证自动同步：改镜像 tag → Argo CD 同步 → Pod 更新 → `/api/version` 变化。
6. 验证漂移：`kubectl scale` 改副本 → selfHeal 恢复。
7. 验证回滚：部署一个错误镜像/错误版本 → Degraded → `git revert` → Synced/Healthy，版本恢复。
8. 记录所有证据：Application JSON、事件、Pod 日志、curl、Git 历史。

### 完成标准

- [ ] Application `Synced` + `Healthy`；Jenkins 部署验证通过。
- [ ] 镜像更新由 Git 变更驱动；不是 Jenkins 直接 `kubectl set image`。
- [ ] 漂移被识别并自愈（或有明确的手动同步记录）。
- [ ] 回滚实际执行并验证旧版本恢复。
- [ ] 同步失败/健康失败有日志、事件与处理记录。

## 7. Phase 3C/4C：Docker Compose 回退路径（仅当 K8s 不可行）

**输入**：Docker 可用；Zot；镜像 digest。
**输出**：Compose 部署；健康/接口验证；回滚；失败演练；明确的 K8s 迁移差距。

- `platform/compose/compose.yaml`：app + Prometheus；使用 `${IMAGE_REF}`（tag@digest）；healthcheck（应用 `-healthcheck`）。
- Jenkins：Push 后写 `.env`（不含密码）→ `docker compose pull/up -d --wait` → curl 验证 → 部署记录。
- 回滚：读取上一部署记录的 digest → `docker compose up -d` → 验证；记录。
- 失败演练：错误 digest/端口/健康检查失败 → 日志/`docker inspect`/events → 回滚。
- 文档明确：无 K8s、无 Argo CD、无漂移检测；迁移条件与步骤（Phase 3K/4K）。

## 8. Phase 5：质量、可观测性与故障演练

- 质量门禁：覆盖率阈值、vet/gofmt、硬编码密钥扫描；记录阈值与失败样例。
- Prometheus：部署（K8s 或 Compose）、抓取 `/metrics`、`up`/5xx 规则、UI 证据；不引入 Alertmanager。
- 日志/状态：应用 JSON 日志、Jenkins 控制台、K8s events、Argo CD UI/CLI；失败脚本自动收集。
- 演练（至少）：
  1. 测试失败 → 流水线失败、无镜像/无 GitOps 变更。
  2. 错误镜像 → ImagePullBackOff/Degraded → 日志/事件 → 回滚。
  3. 就绪探针失败 → rollout 不完成/Degraded → 回滚。
  4. 配置漂移 → selfHeal 恢复。
  5. GitOps 同步失败（错误 path/仓库不可达）→ 状态识别与恢复。
- 每项写入 `docs/verification/`，含命令、关键输出（脱敏）、结论、时间。

## 9. Phase 6：端到端验收与交付

- 按 `docs/phase-0/04-acceptance.md` 逐项执行；区分「已实现且已验证 / 已实现未验证 / 待实现 / 受环境限制」。
- 文档：README、架构、ADR、runbook、troubleshooting、course-mapping、verification 索引。
- 清理：停止服务、保留数据；`--purge` 需人工确认。
- 交付演示：正常提交、失败提交、镜像、部署、回滚、GitOps 漂移/GitOps 回滚（若实现）。

## 10. 文件与脚本规划

```text
scripts/
├── bootstrap/
│   ├── 00-check-env.sh          # 只读环境/端口/网络检查
│   ├── 10-tools.sh              # 安装/校验工具（按选定方案）
│   ├── 20-colima.sh             # VM + Docker
│   ├── 30-registry.sh           # Zot + htpasswd
│   ├── 40-k8s.sh                # k3s/registry 配置（可选）
│   ├── 50-gitea.sh              # Gitea + 初始仓库/用户
│   ├── 60-jenkins.sh            # WAR/JCasC/插件/任务
│   └── 70-argocd.sh             # Argo CD + AppProject/repo secret
├── lib/common.sh                # 日志/错误/确认/脱敏
├── verify/
│   ├── ci.sh                    # 触发/查询构建
│   ├── image.sh                 # push/pull/run/health
│   ├── deploy.sh                # Argo CD/rollout/接口
│   └── security.sh              # 非 root/密钥/认证
├── deploy/
│   ├── update-gitops.sh
│   ├── verify-deploy.sh
│   └── rollback.sh
├── drill/
│   ├── bad-test.sh
│   ├── bad-image.sh
│   ├── bad-readiness.sh
│   └── drift.sh
└── cleanup.sh
```

每个脚本：`set -euo pipefail`、幂等、失败信息可操作、不打印 secret、不在日志 echo 密码；危险操作（删除/重置）必须显式参数+确认。

## 11. 时间估算（按专注会话计）

| 阶段 | 预计 |
|---|---|
| Phase 1 | 2–4 小时（含下载/插件兼容） |
| Phase 2 | 1.5–2.5 小时 |
| Phase 2.5 spike | 1–1.5 小时 |
| Phase 3K/4K（若通过） | 3–5 小时 |
| Phase 3C/4C（回退） | 1.5–2.5 小时 |
| Phase 5 | 2–3 小时 |
| Phase 6 | 2–3 小时 |

网络慢、插件/镜像兼容问题可能显著拉长；每个阶段结束更新进度与证据，不跨阶段宣称完成。

## 12. 待确认（阻塞实施）

1. 批准本计划并进入 Phase 1。
2. 选择工具链安装方式（Homebrew / 便携）。
3. 选择部署目标策略（K8s 优先 + Compose 回退 / 直接 Compose）。
4. 确认应用范围（自带 Go demo / 你的应用）。
5. 确认暂缓 SonarQube、Argo Rollouts、Istio、LDAP、MeterSphere、飞书。
