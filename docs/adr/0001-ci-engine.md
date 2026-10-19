# ADR-001：CI 引擎选择 Jenkins

- 状态：**提议（待阶段 0 确认）**
- 日期：2026-10-19
- 相关：`docs/phase-0/02-solution-design.md`

## 背景

课程第 3–5 章以 Jenkins 为主线，覆盖声明式 Pipeline、凭据、代理、共享库、质量门禁与部署。第 6–7 章给出 Tekton、Drone 作为替代。需要在本机（macOS arm64、无 Docker、Docker Hub 不可达）选择一套可运行、可维护的 CI。

## 决策

采用 **Jenkins 2.580.1（WAR，原生运行，Java 21）** 作为唯一 CI 引擎。

- 流水线定义入仓（`ci/Jenkinsfile`），使用声明式语法。
- 配置尽量 JCasC；凭据通过 Jenkins credentials 注入；插件版本锁定。
- 主分支才具备 push/GitOps 写权限；PR/feature 只做验证。
- 不在本阶段引入 Jenkins Kubernetes 动态代理；使用本机节点 + 标签，保留后续迁移路径。

## 备选方案

| 方案 | 优点 | 不选原因 |
|---|---|---|
| Tekton | K8s 原生、声明式 | 需要额外控制器；课程 API `v1beta1` 过时；与 Jenkins 职责重复；本地 K8s 尚未稳定 |
| Drone | 轻量、Git 集成 | 维护态；GitLab 子组限制；课程配置不安全；与 Jenkins 重复 |
| Gitea Actions | 与 Gitea 集成、轻量 | 课程未覆盖；插件/生态与课程目标偏离；排错资料少 |
| GitLab CI | 一体化 | 需要 GitLab 服务，资源重；与本地 Gitea 重复 |

## 影响

- 正面：与课程知识对齐；插件生态成熟；本地 WAR 不依赖 Docker Hub 的 Jenkins 镜像；可按阶段扩展。
- 负面：Jenkins 原生进程与宿主共享环境；需要 JCasC/插件兼容性维护；Docker 构建使用本地 Colima socket，生产需 rootless/BuildKit。
- 迁移：若未来转 Tekton，保留 `ci/` 中的构建/测试脚本与质量门禁，流水线层替换。

## 验证要求

- 版本、Java 兼容性、插件兼容性有记录。
- 正常/失败/PR 三类构建有证据。
- 无明文凭据；PR 不接触发布凭据。
