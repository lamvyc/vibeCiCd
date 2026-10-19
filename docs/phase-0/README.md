# 阶段 0 交付：课程分析、方案与实施计划

> 状态：**待确认（Phase 0 gate）**。尚未安装/启动任何服务，尚未修改课程资料。
> 交付日期：2026-10-19。

## 1. 本次交付内容

| 文件 | 内容 |
|---|---|
| [`01-course-analysis.md`](01-course-analysis.md) | 163 小节索引、ASR 还原、错误/过时/缺失步骤、可信度与采用边界 |
| [`02-solution-design.md`](02-solution-design.md) | 架构、技术选型、版本兼容、分支/流水线/部署/GitOps/安全/风险/范围 |
| [`03-implementation-plan.md`](03-implementation-plan.md) | Phase 1–6 的输入/输出/验证/完成标准、Phase 2.5 决策门、脚本规划 |
| [`04-acceptance.md`](04-acceptance.md) | 8 个端到端场景、CI/镜像/部署/GitOps/安全/可维护性验收与证据模板 |
| [`../analysis/`](../analysis/) | 4 份逐节原始分析报告 + 索引 |
| [`../adr/`](../adr/) | CI、运行时/K8s、GitOps、质量门禁、暂缓工具 5 份 ADR |

## 2. 核心结论

1. **课程不能直接复刻**：文稿是 ASR 转写，版本缺失，环境假设是多节点 K8s + NFS + LDAP + GitLab + ACR + 公网；多处安全反模式（docker.sock、cluster-admin、明文凭据、关闭校验）和内容错位（Tekton 6-6、Argo CD 10-15/10-17）。
2. **可采纳的是方法与机制**：声明式 Pipeline、凭据/门禁/失败终止、PR 与主分支分流、Argo CD 的 Git 期望状态/sync/health/drift/回滚、部署后验证。
3. **本机约束决定选型**：无 Docker/kubectl/sudo，Docker Hub 不可达，ghcr/quay 可达，24 GB 内存。方案坚持**不依赖 Docker Hub**、**不写全局路径**（尽量）、**不引入重栈**。
4. **目标与回退**：目标 Jenkins + Gitea + Go + Docker + Zot + K8s + Argo CD + Prometheus；Phase 2.5 用时间盒 spike 验证 K8s 是否可行，不可行则 Docker Compose 部署并明确标注差距。
5. **质量与安全优先**：门禁在推送前；镜像非 root/scratch；registry 认证；tag@digest；PR 不接触发布凭据；回滚以 Git revert 为主。

## 3. 建议的实施顺序

```text
Phase 1  CI 最小闭环（Gitea + Jenkins + app + lint/test/build）
Phase 2  镜像 + Zot + push/pull/run
Phase 2.5 K8s spike（决策门）
Phase 3  部署基线（K8s 或 Compose）
Phase 4  Argo CD GitOps（或 Compose 发布/回滚）
Phase 5  质量/可观测性/故障演练
Phase 6  端到端验收 + 文档
```

每个阶段结束都必须有命令输出/状态/日志作为证据；不跨阶段宣称完成。

## 4. 需要你确认的决策

1. **是否批准本方案并进入 Phase 1？**
2. **工具链安装方式**：
   - A（推荐）Homebrew：需要一次更宽文件权限（`/opt/homebrew` 与缓存）；标准、易维护。
   - B 项目内便携工具链：不写全局路径，但脚本更多、首次下载/兼容性风险更高。
3. **部署目标**：
   - A（推荐）K8s/Argo CD 优先；Phase 2.5 不可行时回退 Docker Compose，并明确标注。
   - B 直接 Docker Compose，暂不引入 K8s/Argo CD（最快、最稳）。
   - C 必须 K8s：接受更复杂的镜像/系统组件绕过与更长排错时间。
4. **应用范围**：使用自带的 Go `release-demo`，还是接入你已有的应用？
5. **首版范围**：dev 自动部署 + prod 手工/后续；Prometheus 纳入；SonarQube、Argo Rollouts、Istio、LDAP、MeterSphere、飞书暂缓 —— 是否同意？

## 5. 参考

- 课程原始资料：[`../course-materials/`](../course-materials/)
- 逐节分析：[`../analysis/README.md`](../analysis/README.md)
- 验收模板：[`04-acceptance.md`](04-acceptance.md)
