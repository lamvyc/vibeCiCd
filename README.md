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
        │                     Jenkins 2.580.1 (macOS, Java 21)
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
| Jenkins | macOS 原生 | 8081 |
| Zot | VM Docker | 5001 |
| k3s API | VM → SSH tunnel | 宿主 16443 |
| Argo CD | k3s | port-forward 8443 |
| 应用 dev | k3s | port-forward 18081 |
| Prometheus | k3s | port-forward 19090 |

版本与 digest：[`docs/versions.lock.md`](docs/versions.lock.md)。凭据在 `.env.local`（gitignored，mode 600）。

## 4. 快速开始

```bash
cd /Users/unravel/vibeCiCd
./scripts/bootstrap/90-start-all.sh
```

然后：

```bash
./scripts/deploy/verify-deploy.sh dev 3e9cb2f34287b92c3a2d12ab422a35c874d0664b sha-3e9cb2f34287
kubectl -n argocd get applications
kubectl -n monitoring port-forward svc/prometheus 19090:9090
```

完整启动/停止/回滚/排错：[`docs/runbook.md`](docs/runbook.md)。

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
