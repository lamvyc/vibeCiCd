# ADR-003：用 Argo CD 做 GitOps 持续交付

- 状态：**提议（待阶段 0 确认；以 Phase 2.5 K8s spike 通过为前提）**
- 日期：2026-10-19
- 相关：`docs/phase-0/02-solution-design.md`

## 背景

课程第 10 章介绍 Argo CD 与 Argo Rollouts。CI 已由 Jenkins 负责构建/推送；需要决定部署由谁执行、如何保证可追溯与回滚。课程里的 `sed + kubectl apply` 无审计、无漂移检测、无健康门禁，不适合作为最终方案。

## 决策

采用 **Argo CD v3.5.0** 作为 CD/GitOps 控制器：

- Git 中的 `gitops/` 是唯一期望状态；Argo CD 监听 `gitops/overlays/dev`。
- Jenkins 只负责构建/推送镜像，并把 `tag@digest` 写入 `gitops/overlays/dev`；不直接 `kubectl set image`。
- `Application` 使用 `automated { prune: true, selfHeal: true }` + `CreateNamespace`/`PruneLast`；`AppProject` 限制 source/destination。
- dev 自动同步；prod 清单存在但手动 sync（审批边界）。
- 回滚主路径是 **git revert**，不是直接改集群；`argocd app rollback` 仅作应急，之后必须用 Git 对齐。
- 仓库凭据用 Argo CD repo Secret（Gitea 只读 token），不写入 Git。

## 备选方案

| 方案 | 优点 | 不选原因 |
|---|---|---|
| Jenkins 直接 kubectl/helm 部署 | 少一个组件 | 无 Git 期望状态、无漂移检测、回滚不可审计；课程反模式 |
| Flux CD | GitOps 事实标准之一 | 课程未覆盖；本项目只需要单集群/单应用，Argo CD 更贴合课程与可视化 |
| Argo CD + Rollouts | 渐进发布 | 当前无多副本/流量治理需求；课程两节内容缺失；增加控制器与复杂度 |
| KubeVela/Zadig | 交付抽象/一体化 | 栈重、版本过时、单机不友好；仅对照 |

## 影响

- 正面：部署可审计、可回滚；Git 与集群状态可对比；健康/同步状态可查询；CI/CD 职责清晰。
- 负面：多一个控制器（~1–1.5 GB）；需要 repo 凭据、AppProject、CRD 维护；selfHeal 与应急回滚需要理解。
- 迁移：若未来采用 Argo Rollouts，在 Application 中替换 Deployment 为 Rollout，保留 GitOps 流程。

## 验证要求

- Application Synced/Healthy；镜像更新由 Git 提交驱动。
- 漂移被检测并自愈；同步失败/健康失败可定位。
- git revert 实际执行并验证版本恢复。
- 不使用 NodePort 固定 IP/跳过 TLS/弱口令等课程做法。
