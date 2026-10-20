# vibeCiCd：可运行的 CI/CD 工程化项目

> **状态：核心链路已实现并在本机验证**（2026-10-20）。
> 应用：现有 `lowCode-platform`（Vue 3 / pnpm monorepo，未修改源码）。
> 平台：Jenkins + Docker + Zot + k3s + Argo CD + Prometheus。
> Webhook 直连受沙箱 egress 限制，已用 Gitea API 轮询桥替代并验证；详见限制文档。

## 1. 跑通的链路

```text
应用仓库 (Gitea, VM)  ──提交/PR──▶  CI 桥 (轮询 Gitea API)
        │                              │
        │                              ▼
        │                     Jenkins 2.580.1（官方镜像容器，VM 内）
        │                     typecheck + 538 tests + build
        │                     + Go server tests + 质量门禁
        │                              │
        │                     scratch 镜像（Go 静态服务器 + 前端 dist）
        │                              │
        │                              ▼
        │                     Zot 2.1.22（htpasswd 认证）
        │                              │ tag@digest
        │                              ▼
        └── 期望状态（GitOps）──▶ Argo CD 3.5.5 (k3s)
                                       │ sync / health / selfHeal
                                       ▼
                              K8s Deployment (lowcode-dev / -prod)
                                       │ /metrics
                                       ▼
                              Prometheus 3.8.0（up=1）
```

## 2. 已验证的能力

| 能力 | 结果 |
|---|---|
| 正常 main 构建 | build #11 **SUCCESS**（检查/测试/构建/镜像/推送/GitOps/部署验证） |
| 测试失败门禁 | build #12 在 **Test FAILED**；registry 无该 commit 镜像（404） |
| PR 构建与状态 | PR #1；build #8 SUCCESS；Gitea status `ci/jenkins=success`；可合并 |
| 镜像构建/认证/推送/拉取 | Zot tags；Pod `Successfully pulled image …`；2/2 Running |
| K8s + Argo CD 部署 | `lowcode-dev` Synced/Healthy；镜像 digest 固定 |
| 部署健康/接口验证 | `verify-deploy.sh`：`/healthz`、`/readyz`、`/api/version` commit 匹配 |
| 漂移自愈 | 手工 scale 5 → Argo CD 恢复 2 |
| 同步失败识别 | 错误 Kustomization → `ComparisonError`，事件与 Application 状态可查 |
| 回滚 | `rollback.sh dev` → git revert → 恢复旧 digest → 接口验证通过 |
| 可观测性 | Prometheus `up{job="lowcode-web"}=1`，target healthy，告警规则加载 |
| 复现文档 | `docs/runbook.md`、`docs/verification/`、`docs/versions.lock.md` |

**受环境限制**：Gitea webhook 直连 Jenkins。沙箱 egress 策略阻断所有非公网地址（`127.0.0.1` 与 `192.168.5.1` 均有日志证据），因此实现了 `scripts/ci/gitea-jenkins-bridge.py` 作为自动触发回退；webhook 配置保留。详见 [环境限制](docs/verification/environment-limitations.md)。

## 3. 环境与端口

| 组件 | 位置 | 端口 |
|---|---|---|
| Gitea | Colima VM 容器（host network） | 宿主 3000 |
| Jenkins | Colima VM 容器（官方镜像 + 派生工具镜像，host network） | 宿主 8081（SSH local forward） |
| Zot | VM Docker | 5001 |
| k3s API | VM → SSH tunnel | 宿主 16443 |
| Argo CD | k3s | port-forward 8443 |
| 应用 dev | k3s | port-forward 18081 |
| Prometheus | k3s | port-forward 19090 |

版本与 digest：[`docs/versions.lock.md`](docs/versions.lock.md)。凭据在 `.env.local`（gitignored，mode 600）。

## 4. 快速开始

**前置**：macOS + Homebrew，已装 `colima`、`docker`、`kubectl`、`helm`、`kustomize`、`jq`、
`curl`、`openssl`、`ssh`、`python3`、`java`（WAR 回滚与 CLI 用）。全部为本地服务，不需要公网域名。

**首次（本机已初始化过则跳过）**：

```bash
cd /Users/unravel/vibeCiCd
./scripts/bootstrap/00-env.sh        # 生成 .env.local（随机本地凭据，mode 600；已存在则保留）
./scripts/bootstrap/10-gitea.sh      # 初始化 Gitea 数据（用户/仓库/schema/token）
kill "$(cat .runtime/gitea/gitea.pid)" 2>/dev/null || true   # 10 是宿主原生进程，需让出 3000
./scripts/bootstrap/15-gitea-container.sh                    # 同一数据目录改由 VM 容器提供
./scripts/bootstrap/20-repos.sh      # 推送应用仓库与平台仓库
./scripts/bootstrap/30-wire.sh       # 凭据、分支保护、webhook（webhook 受沙箱限制）
```

> 只有 `.runtime/gitea` 为空时才需要这一节；已有数据直接跳到「日常启动」。
> `15-gitea-container.sh` 不会替你停宿主 Gitea，若宿主仍占用 3000，容器转发会静默失败。

**日常启动（一条命令，幂等）**：

```bash
cd /Users/unravel/vibeCiCd
./scripts/bootstrap/90-start-all.sh
```

顺序：Colima → Zot → k3s/API 隧道 → Gitea → Jenkins 转发 → Jenkins（容器）→ Argo CD →
Prometheus → CI 桥。Jenkins 形态可切换：默认容器（官方镜像）；
`JENKINS_RUNTIME=war ./scripts/bootstrap/90-start-all.sh` 回滚到宿主 WAR。

**启动后自检**：

```bash
set -a; . ./.env.local; set +a
curl -fsS http://127.0.0.1:3000/api/v1/version                      # Gitea
curl -fsS -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" \
     http://127.0.0.1:8081/api/json | jq '{jobs:[.jobs[].name]}'     # Jenkins
curl -fsS -u "$REGISTRY_USER:$REGISTRY_PASSWORD" \
     http://127.0.0.1:5001/v2/_catalog                              # Zot
export KUBECONFIG=$PWD/.runtime/kubeconfig
kubectl get nodes
kubectl -n argocd get applications                                  # 期望 Synced/Healthy
kubectl -n lowcode-dev get deploy,pods

# 当前部署的业务验证（用最新 main 的 SHA 与 tag）
./scripts/deploy/verify-deploy.sh dev <full-sha> sha-<short-sha>
```

**触发一次 CI**（二选一）：

```bash
# A. 真实路径：向应用仓库推分支/PR，CI 桥在数秒内触发；main 受保护，需 PR + ci/jenkins 通过
# B. 手动：必须带完整 40 位 SHA，否则 Go 阶段会因 set -u 报 parameter not set
jenkins_cli() { java -jar .runtime/jenkins-cli.jar -s http://127.0.0.1:8081/ \
  -auth "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" "$@"; }
jenkins_cli build lowcode-platform -p APP_REF=refs/heads/main -p APP_SHA=<full-sha> \
  -p PUBLISH_IMAGE=true -p GITOPS_ENABLED=true -p DEPLOY_ENABLED=true
```

**停止 / 回滚**：

```bash
./scripts/bootstrap/21-jenkins-container.sh stop   # 停 Jenkins 容器
./scripts/bootstrap/60-bridge.sh stop              # 停 CI 桥
colima stop                                        # 停 VM（数据保留）
./scripts/deploy/rollback.sh dev                   # 回滚一次 GitOps 部署
JENKINS_RUNTIME=war ./scripts/bootstrap/90-start-all.sh   # 回滚 Jenkins 运行形态
```

完整启动/停止/回滚/排错：[`docs/runbook.md`](docs/runbook.md)；
Jenkins 容器化迁移记录：[`docs/verification/jenkins-container.md`](docs/verification/jenkins-container.md)。

## 5. 仓库结构

```text
vibeCiCd/
├── ci/                 Jenkinsfile、JCasC、job XML、init groovy
├── gitops/             Kustomize base/overlays + Argo CD Application/AppProject
├── platform/           Go 静态服务器、Dockerfile、Zot/Prometheus 配置
├── scripts/            bootstrap / deploy / ci（Gitea 状态、触发桥）/ lib
├── docs/
│   ├── course-materials/  课程原始资料
│   ├── analysis/          课程逐节分析
│   ├── phase-0/           阶段 0 分析、设计、计划、验收标准
│   ├── phase-1/           应用评估
│   ├── adr/               架构决策记录
│   ├── verification/      实际验收证据与环境限制
│   └── runbook.md         运行手册
├── versions.env           工具/服务版本与 checksum
└── versions.lock.md       实际版本/镜像 digest
```

应用源码在独立的 Gitea 仓库 `lowcode/lowcode-platform`，源自用户本机
`/Users/unravel/ lowCode-platform`（目录名带前导空格）的克隆；平台仓库不修改应用源码。

## 6. 安全边界

- 仓库不保存真实密码/token/私钥；`.env.local`、`.runtime/`、`.tools/`、kubeconfig 均 gitignore。
- Jenkins 凭据通过 JCasC / credentials 注入；PR/feature 构建跳过 push/GitOps。
- Zot 使用 htpasswd（SHA-512 crypt）；K8s 使用 `imagePullSecret`；Argo CD repo 使用只读 token。
- 镜像非 root（65532）、scratch、只读根文件系统、drop capabilities、seccomp。
- 本地 HTTP、无公网入口；生产所需的 TLS/SSO/Vault/NetworkPolicy/镜像签名等明确未实现。

## 7. 暂缓项

SonarQube、Argo Rollouts、Istio、OpenLDAP、MeterSphere、飞书通知、Tekton/Drone/KubeVela/Zadig 均未运行；保留选型对照与重新评估条件，见 [ADR-005](docs/adr/0005-deferred-tools.md)。

## 8. 文档索引

- [阶段 0 总览](docs/phase-0/README.md) / [课程分析](docs/phase-0/01-course-analysis.md) / [方案](docs/phase-0/02-solution-design.md) / [计划](docs/phase-0/03-implementation-plan.md) / [验收标准](docs/phase-0/04-acceptance.md)
- [实际验收记录](docs/verification/README.md) / [环境限制](docs/verification/environment-limitations.md)
- [运行手册](docs/runbook.md)
- [应用接入评估](docs/phase-1/01-app-assessment.md)
- [ADR](docs/adr/)
