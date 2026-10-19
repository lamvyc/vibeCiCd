> **实施变更（2026-10-20）**：应用已确认为现有 `lowCode-platform`（Vue/pnpm monorepo），
> 采用「应用仓库 + 平台/GitOps 仓库」两仓库模型，镜像由 Go 静态服务器包装前端 `dist`。
> 本文件保留阶段 0 的原始设计基线；凡涉及 Go `release-demo`、单仓库、Go 二进制镜像的描述，
> 以 [`../phase-1/01-app-assessment.md`](../phase-1/01-app-assessment.md) 和
> [`../verification/README.md`](../verification/README.md) 为准。

# 阶段 0：项目方案设计

> 状态：**待确认（Phase 0 gate）**。本文件是设计，不是实施结果；所有标记「已验证」的内容必须附命令输出，见 `docs/phase-0/04-acceptance.md`。
> 日期：2026-10-19。环境：macOS 27.0.1 arm64、12 vCPU、24 GB RAM、约 210 GB 可用磁盘。

## 1. 目标与非目标

### 1.1 目标

构建一条**可运行、可验证、可维护、可复现**的最小 CI/CD 工程链，并保留清晰的演进路径：

```text
开发者 → Git（Gitea）→ Webhook → Jenkins
  → 代码检查/测试/质量门禁 → 构建静态二进制
  → Docker 镜像（scratch，非 root）→ 推送本地 Zot 仓库（认证）
  → 更新 Git 中的期望状态（Kustomize）→ Argo CD 同步到 K8s
  → 健康检查/关键接口验证 → 部署记录
  → 失败：日志/事件/回滚；GitOps：漂移检测/自愈
```

同时交付：课程资料索引与可信度报告、架构决策记录（ADR）、运行手册、故障演练与验收证据。

### 1.2 非目标（本阶段不做）

- 不复制课程的多节点 K8s + NFS + OpenLDAP + SonarQube + MeterSphere + 飞书全套栈。
- 不引入 Tekton/Drone/KubeVela/Zadig 作为运行组件；它们只作为选型对照。
- 不做生产级高可用、TLS 公网入口、SSO、Vault、镜像签名/供应链证明、Argo Rollouts 全量灰度。
- 不把 `latest` 作为部署标签；不使用 `cluster-admin`、root 容器、明文凭据。

## 2. 环境事实与约束（已验证）

| 项 | 探测结果 | 影响 |
|---|---|---|
| OS/CPU/RAM/Disk | macOS 27.0.1 arm64；12 vCPU；24 GB；约 210 GB 可用 | 可跑单节点 K8s（预算 8 GB） |
| Docker/kubectl/kind/k3d/Helm | **均未安装** | 必须先安装容器运行时与 K8s 工具 |
| `sudo` | `/usr/bin/sudo: Operation not permitted`（沙箱） | 不能依赖 sudo/系统级安装 |
| Homebrew | 已安装 6.0.18；`/opt/homebrew` 当前不可写，缓存写入被沙箱阻止 | 需授权更宽文件权限，或改用项目内便携工具链 |
| Java | OpenJDK 21.0.12 | Jenkins 2.580.1 可直接运行（官方支持 Java 21） |
| Node/Python/Maven | Node 24.18、Python 3.12、Maven 可用 | 可用于测试报告转换/辅助脚本；不作为主应用运行时 |
| Docker Hub | 本次探测 IPv4/IPv6 均被连接重置（`registry-1.docker.io`、`auth.docker.io`、`hub.docker.com`） | **禁止依赖 Docker Hub**；改用 ghcr.io / quay.io / public.ecr.aws / 本地构建 |
| ghcr.io / quay.io | 可达（401 为正常鉴权挑战） | Argo CD、Zot、Gitea、Prometheus 等镜像来源 |
| GitHub 下载 | 网页可达但慢；release 资产下载多次超时/0 字节 | 工具下载需重试、校验、缓存；必要时用 Homebrew 或镜像 |
| 端口占用 | 8080（node 进程）、5000（ControlCenter/AirPlay） | Jenkins 用 8081；registry 用 5001；Gitea 3000；Prometheus 9090；Argo CD 8443/port-forward |
| 资源预算 | VM 8 GB / 6 vCPU / 60 GB；Jenkins ~1.5 GB；Gitea ~0.3 GB；K8s+Argo CD ~2 GB | 24 GB 可承受；不引入 SonarQube（+2–3 GB） |

> 这些是 2026-10-19 的实测结果，不保证长期有效；每个阶段开始前复测网络与端口。

## 3. 技术选型

### 3.1 选定组合（目标架构）

| 能力 | 选型 | 版本（候选，安装时锁定） | 职责与引入理由 | 备选/不选原因 |
|---|---|---|---|---|
| 版本管理 | Git + Gitea | Gitea 28.2.0（原生） | 本地 Git 托管、Webhook、PR、提交状态、分支保护；替代课程的公网 GitLab | 纯 bare repo 无 PR/UI；GitHub 依赖公网与凭据 |
| CI | Jenkins（WAR，原生） | 2.580.1 + Java 21 | 课程主线；声明式 Pipeline、凭据、多分支/PR、插件生态；本地无需 Docker Hub 拉 Jenkins 镜像 | Tekton 需 K8s 且版本旧；Drone 维护态；Gitea Actions 与课程偏离 |
| 应用 | Go 服务 `release-demo` | Go 1.27.2（工具链） | 无第三方依赖、静态编译、可直接放入 `scratch`；适合演示版本/健康/指标 | Node/Java 需要基础镜像（Docker Hub 不可达）；Python 同理 |
| 容器运行时 | Colima + Lima（VZ） | Colima 0.10.3、Lima 2.2.1、Docker CLI 29.9.1 | macOS 上无 sudo 的轻量 Linux VM + Docker；可启 K8s | Docker Desktop 需 GUI/管理员；Podman 仍需 VM；无运行时则无法构建镜像 |
| 镜像仓库 | Zot | 2.1.22（ghcr.io/project-zot/zot） | OCI 兼容、轻量、支持 htpasswd 认证；本地 registry，避免 Docker Hub | Harbor 过重；Gitea registry 与 K8s 认证链更复杂；`registry:2` 在 Docker Hub 不可达 |
| 编排 | k3s（Colima 内置） | v1.35.3+k3s1（候选） | 单节点、资源占用低；K8s 1.35 与 Argo CD 3.5 兼容 | kind 需 `kindest/node`（Docker Hub）；k3d 需 k3s 镜像/系统镜像；裸 kubeadm 过重 |
| GitOps | Argo CD | v3.5.0（quay.io） | 课程第 10 章主线；Git 为期望状态、sync/health/drift/回滚 | Jenkins 直接 `kubectl apply` 不可审计；Flux 未在课程中 |
| 镜像更新 | Jenkins 更新 GitOps 仓库 | 自研脚本 | 明确 CI 与 CD 边界；避免引入 Argo CD Image Updater 额外组件 | Image Updater 可作为后续增强 |
| 质量门禁 | `gofmt` + `go vet` + `go test -race` + 覆盖率阈值 | 内置工具 | 无额外服务、可在推送镜像前失败 | SonarQube 需 DB、arm64 镜像不确定、内存 2–3 GB；后续可加 |
| 可观测性 | Prometheus + 应用 `/metrics` + K8s 探针 + 部署记录 | Prometheus v3.x（quay.io） | 课程第 10 章涉及 Prometheus；轻量、能验证真实健康/错误率 | Grafana/Alertmanager 暂缓（避免组件堆叠）；日志先用 `kubectl logs`/Jenkins 控制台 |
| 镜像构建 | Docker CLI + Dockerfile（scratch 多阶段替代） | Docker 29.x | 本地单用户、构建简单；镜像仅含静态二进制 | Kaniko/BuildKit rootless 作为生产迁移路径；课程 docker.sock 做法不复制 |

### 3.2 暂缓/不纳入

| 工具/内容 | 结论 | 理由 | 触发条件 |
|---|---|---|---|
| SonarQube | 暂缓 | Docker Hub 镜像/arm64 不确定；内存 2–3 GB；本地质量门禁已覆盖 | 有可用镜像/内存且需要统一代码质量平台时 |
| Argo Rollouts | 暂缓 | 无第二个部署控制器需求；蓝绿/金丝雀需要多副本与流量治理；课程两节内容缺失 | GitOps 稳定且需要渐进发布时 |
| Istio + 分析模板 | 暂缓 | 约 1.5–2 GB；单机收益低；无真实流量比例 | 需要按流量比例灰度/自动回滚时 |
| Tekton | 不纳入运行 | 课程 API `v1beta1` 过时；需要额外 K8s 控制器；与 Jenkins 职责重复 | 团队决定全面转向 K8s 原生 CI 时 |
| Drone | 不纳入 | 维护态、GitLab 子组限制、课程命令不安全 | 仅作对比 |
| KubeVela / Zadig | 不纳入 | 栈重、版本过时、单机不友好；KubeVela 多集群未真验 | 需要 OAM/一体化平台时评估 |
| OpenLDAP | 不纳入 | 单用户本地环境；增加认证依赖与故障面 | 多用户/SSO 需求出现时 |
| MeterSphere | 不纳入 | 平台重；本项目用接口探针覆盖关键路径 | 需要完整 API 测试管理时 |
| 飞书通知 | 不纳入 | 外部 webhook/凭据；本地失败报告已足够 | 有团队通知渠道时 |
| NFS / 多节点 | 不纳入 | 单机无 NFS；用 local-path/无 PVC | 多节点/共享存储需求出现时 |

### 3.3 兼容性核对（证据）

| 组合 | 结论 | 证据 |
|---|---|---|
| Jenkins 2.580.1 + Java 21 | 支持（政策层）；安装时复核 | Jenkins Java 支持策略页面列出 Java 17/21/25；本机 Java 21.0.12；2.580.1 的具体升级说明在安装时复核 |
| Argo CD 3.5 + K8s 1.35 | 支持 | Argo CD 安装文档支持矩阵：3.5 → v1.36/v1.35/v1.34/v1.33 |
| K8s 1.35 + kubectl 1.35.x | 匹配 | 使用与集群同 minor 的 kubectl，避免 skew |
| Colima 0.10.3 + Lima 2.2.1 | 兼容 | Homebrew 公式依赖关系；Lima ≥1.0 在 macOS 默认 VZ |
| Gitea 28.2.0 macOS arm64 | 存在官方二进制 | `dl.gitea.com` 返回 200；安装时校验 SHA256 |
| Zot 2.1.22 | 多架构 OCI registry | ghcr 标签存在；安装时 `docker manifest inspect` 复核 arm64 |
| Prometheus 3.x | quay 官方镜像 | quay 标签 v3.5–v3.8 可拉取（manifest 200） |

> 未在表中列出的版本组合，一律视为「待安装时验证」，不得写入完成声明。

## 4. 架构

### 4.1 目标架构（K8s + GitOps）

```text
┌──────────────┐   git push/PR    ┌──────────────┐   webhook    ┌────────────────────┐
│  Developer   │ ───────────────▶ │    Gitea     │ ───────────▶ │  Jenkins (native)  │
│  (macOS)     │                  │  :3000       │              │  :8081, Java 21    │
└──────────────┘                  │  app + gitops│              │  lint/test/build   │
                                  └──────┬───────┘              └─────────┬──────────┘
                                         │ git clone/push                 │ docker build/push
                                         │                                ▼
                                         │                     ┌────────────────────┐
                                         │                     │  Zot registry      │
                                         │                     │  :5001, htpasswd   │
                                         │                     └─────────┬──────────┘
                                         │                               │ image digest
                                         │                               ▼
                                         │                     ┌────────────────────┐
                                         └── desired state ──▶│  Argo CD (k3s)     │
                                                               │  sync/health/drift │
                                                               └─────────┬──────────┘
                                                                         │ apply
                                                                         ▼
                                                               ┌────────────────────┐
                                                               │ K8s Deployment     │
                                                               │ dev / prod ns      │
                                                               │ probes + metrics   │
                                                               └─────────┬──────────┘
                                                                         │ /metrics
                                                                         ▼
                                                               ┌────────────────────┐
                                                               │ Prometheus :9090   │
                                                               │ rules + targets    │
                                                               └────────────────────┘
```

组件运行位置：
- macOS 宿主：Gitea、Jenkins、Colima CLI、kubectl、脚本；浏览器访问 Gitea/Jenkins/Prometheus。
- Colima Linux VM：Docker daemon、Zot 容器、k3s（含 Argo CD、应用、Prometheus）。
- 所有工具/数据尽量在项目目录下（`.tools/`、`.runtime/`），避免全局污染；Gitea/Jenkins 数据不入 Git。

### 4.2 仓库与职责（单仓库、逻辑分层）

```text
vibeCiCd/
├── app/                     # 应用源码（Go）
│   ├── cmd/release-demo/
│   ├── internal/...
│   ├── go.mod
│   └── Dockerfile
├── ci/                      # Jenkinsfile、JCasC、插件锁、共享脚本
├── gitops/                  # 期望状态（Argo CD source）
│   ├── base/
│   ├── overlays/dev/
│   ├── overlays/prod/
│   └── argocd/
├── platform/                # 本地运行时编排：compose、Prometheus、registry
├── scripts/                 # bootstrap/verify/rollback/drill
├── docs/                    # 课程分析、方案、计划、验收、runbook
├── versions.env             # 工具/镜像版本与校验和
└── Makefile
```

职责边界（GitOps 语义上的「应用仓库 / 部署配置仓库」）：
- `app/`：只产出可测试、可构建的制品；不保存环境状态。
- `gitops/`：唯一的环境期望状态；Argo CD 只读该目录；Jenkins 只改镜像引用，不改副本/资源等运行参数。
- `platform/`：本地平台搭建（registry、Prometheus、Compose），不属于应用发布物。
- `ci/`：流水线定义与凭据引用；不保存明文凭据。

> 取舍：本地采用单仓库便于复现；若团队需要独立审批/权限，可把 `gitops/` 拆为独立仓库，只需改 Argo CD `repoURL/path` 与 Jenkins 的 `GITOPS_REPO_URL`，不影响流水线阶段。拆分步骤写入 ADR-003。

### 4.3 分支与触发策略

| 事件 | 分支/Ref | 流水线行为 | 发布 |
|---|---|---|---|
| push | `main` | 全流程：lint→test→build→quality gate→image→push→GitOps 更新→部署验证 | 是（dev） |
| push | `feature/*` | lint→test→build→image build（不 push） | 否 |
| PR | `refs/pull/*` | 同上 + 状态回传；不 push、不改 GitOps | 否 |
| tag | `v*` | 全流程 + 不可变版本标签；prod overlay 更新 | 手动/后续 |
| push | `gitops/*` 变更 | 仅当应用代码未变时跳过（避免 bot 提交触发回路） | Argo CD 自行同步 |

实现要求：
- Gitea 分支保护：`main` 要求 PR + 至少一个成功状态检查；禁止直接 push（管理员可按需绕过，需记录）。
- Jenkins 区分 `BRANCH_NAME`、`CHANGE_ID`、`TAG_NAME`；PR 使用 Gitea 提供的 merge ref 或 head SHA，检出后记录实际 commit。
- 所有触发都记录 build cause、commit、分支、镜像 digest、部署结果。

### 4.4 流水线设计（Jenkins 声明式）

| 阶段 | 关键动作 | 失败行为 | 产物/证据 |
|---|---|---|---|
| Checkout | 检出正确 ref；记录 commit/branch | 终止 | `build-info.txt` |
| Classify | 判断 PR/主分支/仅 gitops 变更 | 仅 gitops → 提前成功退出 | 分类日志 |
| Lint | `gofmt -l`、`go vet ./...` | 终止，不构建镜像 | lint 日志 |
| Test | `go test -race -coverprofile` + JUnit 转换 | 终止，不推送 | `junit.xml`、`coverage.out` |
| Build | `CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath` | 终止 | 二进制 SHA256、大小 |
| Quality Gate | 覆盖率阈值（首版 ≥60%）、测试全绿、vet 无输出 | 终止，不推送 | 门禁报告 |
| Docker Build | 构建 scratch 镜像，打 `sha-<12>` / `vX.Y.Z` 标签与 OCI labels | 终止 | `docker image inspect` |
| Image Verify | 启动容器，调用 `/healthz`、`/api/version`；检查非 root/无敏感文件 | 终止，不推送 | 运行日志、镜像大小 |
| Push | `docker login`（凭据掩码）→ push → 解析 digest → 清理本地并重新 pull/run | 终止，不更新 GitOps | digest、pull 日志 |
| GitOps Update | 克隆仓库，Kustomize 设置 `image:tag@digest`，提交 `[skip ci]`，push | 终止；记录未部署 | Git commit SHA |
| Deploy Verify | 轮询 Argo CD sync/health；`kubectl rollout status`；port-forward；curl `/healthz`、`/readyz`、`/api/version` | 失败；收集 events/logs；不自动掩盖 | 部署记录 JSON、接口响应 |
| Post | 归档报告/日志；失败写 `artifacts/failure-*.txt`；成功写部署记录 | — | 可复核证据 |

约束：
- PR/feature 不获取 registry push 与 GitOps 写权限；只有 `main` 的受信任构建才使用这些凭据。
- `docker login` 前后 `set +x`，密码只通过 stdin；Jenkins `withCredentials` 掩码。
- 镜像标签**不使用 `latest`**；部署引用 `tag@digest`，保证不可变、可追溯。
- 测试失败/覆盖率不达标时，流水线必须在 Docker Build 之前失败；验收时验证 registry 中没有该 commit 的镜像。

### 4.5 应用与镜像

- Go 服务 `release-demo`，仅标准库；端点：`/healthz`、`/readyz`、`/api/version`、`/api/hello`、`/metrics`。
- 版本信息通过 `-ldflags -X` 注入：`version`、`commit`、`buildTime`；`/api/version` 返回它们。
- 优雅关闭、请求日志（JSON）、超时、请求计数/时延直方图（手写 Prometheus 文本）。
- `Dockerfile`：`FROM scratch`，仅复制静态二进制；`USER 65532:65532`；`EXPOSE 8080`；OCI labels；无 shell、无包管理器、无源码、无密钥。
- K8s：2 副本（dev）、readiness/liveness、resources requests/limits、`runAsNonRoot`、`readOnlyRootFilesystem`、`allowPrivilegeEscalation: false`、`capabilities.drop: [ALL]`、`seccompProfile: RuntimeDefault`；imagePullSecret。
- 环境配置放 ConfigMap/overlay；镜像 tag/digest 是唯一随发布变化的字段。

### 4.6 GitOps 与部署

- Argo CD `Application`（dev）：
  - `source.repoURL` = 本地 Gitea 仓库；`path` = `gitops/overlays/dev`；`targetRevision` = `main`。
  - `destination` = in-cluster，namespace `release-demo-dev`。
  - `syncPolicy.automated { prune: true, selfHeal: true }`；`syncOptions: [CreateNamespace=true, PruneLast=true]`。
  - `retry` 有限次；`revisionHistoryLimit` 保留。
- `AppProject`：`sourceRepos` 仅允许该仓库；`destinations` 仅允许 dev/prod 命名空间；禁止 cluster-scoped 资源（除必要的 Namespace）。
- `repo` Secret：Gitea 只读 token；不写入 Git；由 bootstrap 从 `.env.local` 创建。
- 镜像更新：Jenkins 写 `gitops/overlays/dev/kustomization.yaml` 的 `images[].newTag` + digest；提交者/消息可审计。
- 回滚：
  - **主路径**：`git revert` 最后一个 GitOps 发布提交 → push → Argo CD 自动同步回旧 digest；验证 `/api/version` 恢复。
  - **应急**：`argocd app rollback`（需关闭/理解 selfHeal 的影响）；执行后以 Git revert 重新对齐，避免漂移。
- 漂移：`kubectl scale` 改副本后，Argo CD selfHeal 恢复；记录事件与时间。
- 部署状态：Jenkins 轮询 `Application.status.sync.status == Synced` 且 `health.status == Healthy`，再校验 Deployment available replicas 与接口版本。

### 4.7 质量门禁与可观测性

- 质量门禁（首版）：`gofmt` 无差异、`go vet` 无告警、`go test -race` 全绿、覆盖率 ≥ 60%、无硬编码密钥扫描（简单正则，后续可换 gitleaks）。
- 失败即阻断：门禁在 Docker Build/Push 前；验收验证失败提交没有镜像、没有 GitOps 提交。
- Prometheus：
  - 目标：`release-demo-dev` Service 的 `/metrics`；记录 `up`、请求总数、5xx 比例、P95 时延。
  - 规则：`up == 0`、5xx 速率阈值；UI 可见 firing；不引入 Alertmanager（本地无通知渠道）。
  - 资源：单副本、emptyDir、requests/limits；随 K8s 阶段部署。
- 日志：应用 JSON 日志 → `kubectl logs`；Jenkins 控制台；Argo CD events；失败时脚本收集 `kubectl get events`、`describe`、最近日志到 `artifacts/`。
- 部署记录：`artifacts/deployments/<env>-<tag>.json`，含 commit、digest、Argo CD revision、健康状态、接口响应摘要、时间戳；不入 Git（或写 `docs/verification/` 的脱敏摘要）。

### 4.8 安全模型

| 项 | 做法 | 生产差距/后续 |
|---|---|---|
| 凭据 | `.env.local` 随机生成、gitignore；Jenkins credentials/JCasC 注入；K8s Secret/imagePullSecret | 生产用 Vault/External Secrets，定期轮换 |
| 仓库认证 | Gitea 细粒度 token（读/写分权）；Argo CD 只读 | 生产用 Deploy Key/SSO |
| Registry | Zot htpasswd；Jenkins push 凭据；K8s imagePullSecret；先验证未认证拉取失败 | 生产 TLS + 扫描 + 签名 |
| CI 权限 | PR 不接触 push/GitOps 凭据；主分支受保护 | 生产用 ephemeral agents + OIDC |
| 容器 | scratch、非 root、只读根、drop caps、seccomp | 生产加 NetworkPolicy、Pod Security Admission |
| Docker socket | 本地 Jenkins 使用项目内 Colima socket；视为 root 等价，仅本地 | 生产改 rootless BuildKit/Kaniko/Tekton |
| 传输 | 本地 loopback HTTP；不暴露公网 | 生产 TLS/Ingress/Auth |
| 日志 | 不打印密码/token；`set +x`；Jenkins 掩码 | 生产接入日志脱敏/审计 |

## 5. 关键流程与失败处理

### 5.1 正常发布

1. 开发者在 `feature/*` 提交 → PR → Jenkins CI（lint/test/build，不 push）→ Gitea 状态 success。
2. 合并 `main` → Jenkins 全流程 → 推送镜像（tag+digest）→ 更新 `gitops/overlays/dev` → Argo CD 同步 → 健康/接口验证 → 部署记录。
3. 验证 `/api/version` 返回的 commit 与流水线 commit 一致。

### 5.2 失败处理

| 失败点 | 现象 | 处理 | 验证 |
|---|---|---|---|
| Lint/Test/门禁 | Jenkins 在对应 stage 失败；无镜像 | 修复代码重跑；不人工绕过门禁 | registry 无该 commit tag |
| Docker build | 构建日志报错；无镜像 | 修复 Dockerfile/构建参数 | 重跑成功 |
| Push | 登录/网络/权限错误 | 检查凭据、registry 状态、磁盘 | 重试并解析 digest |
| GitOps 更新 | push 失败/冲突 | 重新拉取、重试；不强行覆盖他人提交 | Git 历史与 diff |
| Argo CD 同步失败 | `OutOfSync`/`SyncFailed`/`Degraded` | 查看 Application events、repo-server 日志、清单校验 | `kubectl describe app` |
| Pod 启动失败 | `ImagePullBackOff`/`CrashLoopBackOff` | 检查 imagePullSecret、digest、探针、日志 | 修复后 Healthy |
| 接口验证失败 | 版本不符/5xx | 检查 Service/端口/就绪；回滚 | `/api/version` 恢复 |
| 部署后异常 | 指标/日志异常 | 回滚 GitOps 提交；保留现场证据 | 回滚验收 |

### 5.3 回滚策略

- **GitOps 回滚**是默认路径：`git revert <deploy-commit>` → push → 等 `Synced/Healthy` → 验证旧版本 digest。
- **镜像回滚**不重新构建：直接引用历史 digest（registry 保留策略至少覆盖验收窗口）。
- **应急 `argocd app rollback`**：只用于 Argo CD 侧快速恢复；随后必须用 Git revert 对齐，否则 selfHeal/下一次同步会再次应用错误状态。
- 回滚后记录：触发原因、旧/新 digest、Argo CD revision、恢复时间、验证结果。

## 6. 资源、端口与运行方式

| 组件 | 位置 | 端口 | 资源预算 | 数据 |
|---|---|---|---|---|
| Gitea | macOS 原生 | 3000 | ~0.3 GB | `.runtime/gitea/`（SQLite、repos） |
| Jenkins | macOS 原生（Java 21） | 8081 | ~1.5 GB | `.runtime/jenkins/` |
| Colima VM | macOS VZ | — | 8 GB / 6 vCPU / 60 GB | `.runtime/colima/`、`.runtime/lima/` |
| Zot | VM 内 Docker | 5001→5000 | ~100 MB | `.runtime/registry/` volume |
| k3s | VM 内 | 6443 | ~1 GB | VM 磁盘 |
| Argo CD | k3s | 8443/port-forward | ~1–1.5 GB | K8s CRD/Secret |
| 应用 | k3s dev/prod ns | 8080 / NodePort 30080/30081 | 2×128 MB | 无状态 |
| Prometheus | k3s | 9090/port-forward | ~300 MB | emptyDir |

启动顺序：Colima → Zot（seed 基础镜像）→ k3s → Argo CD → Gitea → Jenkins → 应用/GitOps。停止顺序相反；数据保留，`--purge` 需显式确认。

## 7. 风险清单与缓解

| # | 风险 | 概率/影响 | 缓解 | 回退 |
|---|---|---|---|---|
| R1 | Colima/Lima 在沙箱/无 sudo 下无法启动 VM | 中/高 | 先做 30 分钟 spike；`COLIMA_HOME`/`LIMA_HOME` 放工作区；必要时申请 Homebrew 全盘权限或 Docker Desktop | 若 VM 不可用：仅 CI（native app + Jenkins），CD 标记受环境限制；或申请管理员安装 |
| R2 | Docker Hub 不可达导致 K8s 系统镜像/基础镜像拉取失败 | 高/高 | 只用 ghcr/quay；k3s 用 airgap/本地 zot 镜像；禁用 traefik/local-path/metrics-server；kind 仅作备选且需镜像站 | 部署目标降级为 Docker Compose（本机），K8s/Argo CD 标记「受环境限制」 |
| R3 | K8s 系统组件（CoreDNS/pause）无法取得 | 中/高 | 优先 k3s airgap 包；否则本地 zot 镜像 + 禁用非必要 addon；最后才考虑可信镜像站并记录 digest | 同 R2 |
| R4 | Jenkins 插件与 2.580.1 不兼容（尤其 Gitea/SCM） | 中/中 | 安装前查 plugin 页面兼容性；锁定版本；备选 Generic Webhook Trigger + Pipeline 脚本 | 降低 Jenkins 版本或换触发方式 |
| R5 | Gitea 28.2.0 配置/API 变化 | 中/中 | 安装时核对官方 config/API；保留 1.27.3 回退 | 使用上一稳定版 |
| R6 | 资源不足（24 GB，VM 8 GB + Jenkins 1.5 GB） | 中/中 | 单副本应用、VM 6–8 GB、关闭无用 addon；监控内存 | 降 VM 到 6 GB/1 副本，或停 Prometheus |
| R7 | 端口冲突（8080/5000 已占用） | 高/低 | 固定 8081/3000/5001/9090；启动前检查并报错 | 改端口变量并更新文档 |
| R8 | 网络下载慢/不稳定（GitHub release） | 高/中 | 缓存、重试、SHA256 校验；优先 Homebrew/ghcr/quay | 使用已缓存产物或申请镜像 |
| R9 | 课程内容错误被误用 | 中/中 | 以本报告和官方文档为准；关键版本/命令实测 | 记录纠正与依据 |
| R10 | 本地无 TLS/公网隔离不足 | 中/中 | 只绑定 loopback/本机；随机密码；不开放公网；文档标注生产差距 | 加反向代理/TLS 后再暴露 |

## 8. 范围与里程碑

| 优先级 | 能力 | 说明 |
|---|---|---|
| 必须 | Git + Gitea、Jenkins CI、lint/test/build、质量门禁、Docker 镜像、Zot 推送/拉取、部署、健康/接口验证、失败演练、文档 | 形成可运行闭环 |
| 目标 | K8s + Argo CD GitOps、dev/prod 配置分离、漂移/自愈、回滚、Prometheus | 环境 spike 通过后实现 |
| 建议 | PR 状态回传、分支保护、镜像 digest 固定、部署记录、失败证据收集 | 与必须项一起做 |
| 暂缓 | SonarQube、Argo Rollouts、Istio、Tekton/Drone/KubeVela/Zadig、LDAP、MeterSphere、飞书 | 有明确需求/资源时再评估 |

## 9. 决策记录

- ADR-001：Jenkins 作为 CI（`docs/adr/0001-ci-engine.md`）
- ADR-002：Colima + k3s 作为本地运行时/K8s（`docs/adr/0002-runtime-kubernetes.md`）
- ADR-003：Argo CD GitOps 作为 CD（`docs/adr/0003-gitops-argocd.md`）
- ADR-004：轻量质量门禁替代 SonarQube（`docs/adr/0004-quality-gate.md`）
- ADR-005：暂缓工具与回退策略（`docs/adr/0005-deferred-tools.md`）

## 10. 待确认项

1. 是否批准本方案并进入阶段 1（安装/启动 VM、Gitea、Jenkins、CI）？
2. 工具链安装方式：Homebrew（需更宽文件权限）还是项目内便携工具链？
3. K8s/Argo CD 是目标（失败则 Docker Compose 回退），还是直接先做 Docker Compose？
4. 是否接受首版「dev 自动部署 + prod 手工/后续」以及 Prometheus、暂缓 SonarQube/Argo Rollouts？
5. 应用是否使用本方案自带的 Go `release-demo`，还是替换为你已有的应用？
