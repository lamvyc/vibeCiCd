# vibeCiCd：可验证的 CI/CD 工程化项目

> **当前状态：阶段 0（分析与设计）已完成，等待确认后进入实施。**
> 尚未安装/启动服务，尚未初始化应用代码或 Git 仓库；本文档不包含“已运行”的声明。

## 这个项目要做什么

基于课程资料（Jenkins、Tekton、Drone、KubeVela、Zadig、Argo CD/Rollouts），在本机构建一条**可运行、可验证、可维护、可复现**的 CI/CD 链路：

```text
Git（Gitea）→ Jenkins（lint/test/质量门禁/构建）
  → Docker 镜像（scratch、非 root）→ Zot 镜像仓库（认证）
  → GitOps（Kustomize + Argo CD）→ Kubernetes（k3s）
  → 健康检查/关键接口验证 → 部署记录 → 失败处理与回滚
```

环境不允许时，按阶段 0 的决策门回退到 Docker Compose 部署，并明确标注能力差距，不把回退路径写成 K8s/GitOps 已验证。

## 阶段 0 交付

- [阶段 0 总览](docs/phase-0/README.md)
- [课程资料分析与问题清单](docs/phase-0/01-course-analysis.md)
- [项目方案设计](docs/phase-0/02-solution-design.md)
- [实施计划](docs/phase-0/03-implementation-plan.md)
- [验收标准与证据要求](docs/phase-0/04-acceptance.md)
- [课程逐节分析索引](docs/analysis/README.md)
- [架构决策记录（ADR）](docs/adr/)

## 关键环境事实（2026-10-19 实测）

| 项 | 结果 |
|---|---|
| 机器 | macOS 27.0.1 arm64、12 vCPU、24 GB RAM、约 210 GB 可用 |
| 已有 | Java 21.0.12、Node 24、Python 3.12、Maven、Homebrew |
| 缺少 | Docker、kubectl、kind/k3d、Helm、Go |
| 权限 | 无 `sudo`；Homebrew 缓存写入受沙箱限制（需授权或项目内工具链） |
| 网络 | **Docker Hub 不可达**（连接重置）；ghcr.io / quay.io 可达；GitHub 下载慢 |
| 端口 | 8080、5000 已占用；计划使用 8081/3000/5001/9090 |

## 计划中的目录结构

```text
app/        Go 服务（release-demo）
ci/         Jenkinsfile、JCasC、插件锁
gitops/     K8s/Kustomize 期望状态（Argo CD source）
platform/   registry、Prometheus、Compose 等本地平台配置
scripts/    bootstrap / verify / deploy / rollback / drill
docs/       课程分析、方案、计划、验收、runbook
```

## 安全与边界

- 仓库不保存真实密码/Token/私钥；`.env.local`、`.runtime/`、kubeconfig 等加入 `.gitignore`。
- 本地 HTTP/无 TLS 仅用于隔离环境；不开放公网。
- 不使用课程中的 `docker.sock` 明文挂载、`cluster-admin`、关闭 CSRF/SSL 校验、弱口令等做法。
- 生产差距（TLS、SSO、Vault、NetworkPolicy、镜像签名）会在文档中明确，不伪装成已完成。

## 下一步

请确认 `docs/phase-0/README.md` 中的 5 个决策（是否进入 Phase 1、工具链安装方式、部署目标、应用范围、首版范围）。确认后再开始安装/启动与代码实现。
