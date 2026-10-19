# 课程资料分析索引（阶段 0）

> 分析对象：`docs/course-materials/` 下 4 份中文课程逐字稿，共 2,808 行、约 848 KB。
> 分析日期：2026-10-19。分析方法：全文分块阅读 + 关键操作抽样复核 + 版本/环境假设标注。
> 重要前提：这些文稿是**语音转写**，不是官方操作手册。所有结论都区分「原文事实 / 推断 / 无法确认」。

## 1. 文件与章节

| 文件 | 章节 | 行数 | 主题 | 原始报告 |
|---|---|---:|---|---|
| `jenkins.md` | 第 3–5 章 | 907 | Jenkins 部署、LDAP/RBAC、声明式 Pipeline、代理、共享库、SonarQube/MeterSphere 实战 | [raw-jenkins.md](raw-jenkins.md) |
| `tekton-drone.md` | 第 6–7 章 | 749 | Tekton、Drone；主要是 CI 选型对照 | [raw-tekton-drone.md](raw-tekton-drone.md) |
| `delivery-platforms.md` | 第 8–9 章 | 777 | KubeVela、Zadig；应用交付平台对照 | [raw-delivery-platforms.md](raw-delivery-platforms.md) |
| `argocd-rollouts.md` | 第 10 章 | 353 | Argo CD、Argo Rollouts、Istio/Prometheus 分析 | [raw-argocd-rollouts.md](raw-argocd-rollouts.md) |

共 163 个小节（Jenkins 53、Tekton/Drone 42、KubeVela/Zadig 43、Argo CD 25）。

## 2. 文稿质量与阅读约定

- **ASR 噪声极重**：例如「真皮实/整体时/正题十/金提子/精品词/静力时」= Jenkins，「拍拍赖/啪啪赖」= Pipeline，「勾语/购物」= Groovy，「k八十」= K8s，「肉outs」= Rollouts。
- **命令大量丢失**：KubeVela 的安装脚本、Tekton 的多段 YAML 只剩口述；不能把文稿当可执行脚本。
- **版本几乎全部缺失**：只有零散线索（JDK 11、K8s 1.28、Tekton `v1beta1`、Zadig v1.18.0、Istio 1.22.2 的推断）。报告中已逐条标注「明确 / 推断 / 无法确认」。
- **内容错位/重复**：Tekton 6-6 名实不符；Argo CD 10-15、10-17 与前后小节逐字重复，蓝绿发布介绍/实战实际缺失。
- **环境强绑定**：NFS StorageClass、双节点 K8s、OpenLDAP、阿里云 ACR、飞书 webhook、公网 GitLab、Istio、NodePort 固定 IP。换到本机即失效。

## 3. 跨章节的共性问题（本项目必须补齐）

1. **版本与可复现性**：课程普遍使用 `lts`、`latest`、未记版本的插件；本项目必须锁定 Jenkins/K8s/Argo CD/镜像/插件版本并记录摘要。
2. **凭据与权限**：课程多次出现明文密码、base64 当加密、`cluster-admin`、关闭 SSL/CSRF、`docker.sock`、root 容器。本项目改为凭据机制、最小权限、非 root、只读根文件系统、registry 认证与 imagePullSecret。
3. **交付验证缺失**：多数实验把 `kubectl apply` 或 `docker run` 成功当成部署成功；缺少 readiness/liveness、Argo CD health/sync 检查、关键接口验证与部署记录。
4. **回滚缺失**：Jenkins 章节用 `sed` 改镜像后 `apply`，没有回滚；Tekton 项目只有 `sed + apply`；Argo CD 章节有回滚 UI 但未讲清与 selfHeal/Git 的关系。
5. **Webhook 与分支/PR 规则**：课程依赖关闭 CSRF、关闭 SSL 校验、明文 token；未讲签名校验、分支过滤、PR 与普通分支的差别。
6. **环境假设不可迁移**：NFS、LDAP、固定 IP、NodePort、公网域名。本项目用 local-path/无 PVC、本地账号、port-forward/NodePort 可配置。
7. **可观测性薄弱**：几乎没有指标、告警、日志收集与部署状态检查；本项目补 Prometheus 指标、健康检查、部署记录与故障演练。

## 4. 可信度与采用结论（汇总）

| 来源 | 可信度 | 采用方式 | 说明 |
|---|---|---|---|
| Jenkins 3-10~3-18、3-22、3-23、4-5、4-6、4-9 | A | 直接采用/改造 | 声明式语法、凭据、post、parallel、when、共享库、Kaniko 概念长期稳定 |
| Jenkins 3-7、3-8、3-9、3-25~3-27 | A/B | 改造 | 凭据/视图/RBAC/SCM 思路可用；需 JCasC、API token、最小权限 |
| Jenkins 3-3~3-5、3-28~3-30、4-2~4-4、5-2、5-11 | B | 改造 | 部署、webhook、多分支、代理、实战；需换版本与安全模型 |
| Jenkins 3-24、5-10 | C | 不纳入 | 插件/API 无法确认；`docker.sock` + 管理员权限是反模式 |
| Tekton 6-2、6-7、6-13 | A−/B | 仅对照 | 概念可参考；`v1beta1` 已过时，需升 v1 |
| Tekton 6-6、6-10~6-17 | C/B− | 不纳入 | 6-6 内容错位；命令不可照抄；SA 绑 `cluster-admin` |
| Drone 全章 | B− | 仅对照 | 维护态、GitLab 子组限制；不作为主 CI |
| KubeVela 第 8 章 | B | 仅对照 | OAM/交付抽象有参考价值；多集群未真验；命令缺失 |
| Zadig 第 9 章 | B−/C+ | 不纳入 | v1.18、K8s 1.16–1.26 已过时；MySQL+Mongo+NFS 栈过重 |
| Argo CD 10-2/4/7/13/14/16/20/25 | A | 直接采用 | Application、syncPolicy、CLI、Rollouts 概念、AnalysisTemplate 字段 |
| Argo CD 10-3/5/6/8/9/10/12/18/21/22 | B | 改造 | 补 repo-creds、TLS、RBAC 资源名、selfHeal/Git 回滚、pause 语义 |
| Argo CD 10-11/15/17/24 | C | 不纳入/仅对照 | LDAP 成本高；两节内容缺失；三工具对比不完整 |

## 5. 课程 → 项目映射（摘要）

- **保留并现代化**：Jenkins 声明式 Pipeline、凭据、post、并行、when、SCM 多分支/PR、共享库思想；Argo CD Application/syncPolicy/health/RBAC 模型；Kaniko 的「构建与推送分离」思想。
- **替换**：GitLab → 本地 Gitea（webhook/PR/状态回传）；NFS StorageClass → 本地 registry + 无 PVC 或 local-path；LDAP → 本地账号（单用户）；SonarQube → `gofmt`/`go vet`/测试覆盖率门禁（环境不满足时）；MeterSphere → 健康检查 + 关键接口 curl；飞书 → 本地失败报告/控制台；Kaniko/docker.sock → 受控 Docker 构建（本地）并记录生产替代方案。
- **仅作选型对照**：Tekton、Drone、KubeVela、Zadig、Istio、Argo Rollouts 全量灰度、OpenLDAP、MeterSphere。理由见 `docs/phase-0/02-solution-design.md` 的「暂缓/不纳入」表。

## 6. 使用说明

- 原始报告（`raw-*.md`）保留行号、ASR 对照与逐节清单，供追溯。
- 综合结论以本目录和 `docs/phase-0/` 为准；两者冲突时，以综合报告和实际验证结果为准。
- 报告中的「推断」不等于已验证；任何进入实施的结论都要在对应阶段用命令输出复核。
