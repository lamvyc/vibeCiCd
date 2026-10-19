# ADR-002：本地运行时与 Kubernetes 路径

- 状态：**提议（待阶段 0 确认）**
- 日期：2026-10-19
- 相关：`docs/phase-0/02-solution-design.md`、`docs/phase-0/03-implementation-plan.md`

## 背景

本机 macOS 27.0.1 arm64，24 GB RAM，当前**没有 Docker/kubectl/kind/k3d/Helm**，无 sudo；Homebrew 缓存写入被沙箱阻止；Docker Hub 在本次探测中不可达，ghcr/quay 可达。课程假设多节点 K8s + NFS，不能直接复现。

## 决策

1. **容器运行时**：优先 Colima 0.10.3 + Lima 2.2.1（VZ），项目内 `COLIMA_HOME`/`LIMA_HOME`；Docker CLI 29.9.1。
2. **K8s**：优先 Colima 内置 k3s v1.35.3；单节点，禁用非必要 addon（traefik/servicelb/metrics-server/local-path 视需要）。
3. **镜像仓库**：Zot 2.1.22（ghcr），本地 5001，htpasswd 认证；不使用 Docker Hub 的 `registry:2`。
4. **部署目标决策门**：Phase 2.5 时间盒 spike；通过则 K8s + Argo CD；不通过则 Docker Compose 部署，K8s/Argo CD 标记「受环境限制」，不假装完成。
5. **安装方式**：优先 Homebrew（需一次更宽文件权限）；若不允许，使用项目内便携工具链。两者都必须锁定版本并记录。

## 备选方案

| 方案 | 优点 | 不选/回退原因 |
|---|---|---|
| Docker Desktop | 成熟、GUI | 需安装到 /Applications/管理员；Docker Hub 仍不可达；资源占用高 |
| kind | 简单、贴近上游 | `kindest/node` 在 Docker Hub，当前不可达；需镜像站 |
| k3d | registry 集成好 | 节点镜像 `rancher/k3s` 在 Docker Hub；可用 ghcr k3s 但系统镜像仍需处理 |
| Podman | 无 daemon | macOS 仍需 VM；课程/工具链兼容性不确定 |
| 仅 Docker Compose | 最可靠 | 不满足 K8s/GitOps 目标；作为回退而不是首选 |
| 原生进程（无容器） | 零运行时 | 无法验证镜像/部署/编排，违背项目目标 |

## 影响

- 正面：无需 sudo/管理员；本地数据可清理；K8s 资源可控；避免 Docker Hub。
- 负面：Colima/Lima 首次启动下载大；k3s 系统镜像可能受网络影响；单节点不能验证多节点/高可用；本地 HTTP registry 只适合隔离环境。
- 回退：若 VM 无法启动 → 申请管理员安装或仅 CI；若 K8s 系统镜像不可得 → Docker Compose 部署，保留迁移清单。

## 验证要求

- `colima status`、`docker version`、`kubectl get nodes`（若启用）有输出。
- K8s 系统 Pod 状态与镜像来源/digest 记录。
- 不依赖 Docker Hub；所有镜像来源可追溯。
