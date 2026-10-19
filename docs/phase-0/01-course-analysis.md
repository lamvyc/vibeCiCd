# 阶段 0：课程资料分析与问题清单

> 配套材料：逐节索引见 `docs/analysis/raw-*.md`；本文件给出跨章节结论、错误/缺口清单与可采纳边界。
> 标记：**[原文]** = 文稿明确陈述；**[推断]** = 依据上下文还原；**[无法确认]** = 证据不足。行号均指原文件。

## 1. 课程知识地图

```text
第3章 Jenkins 基础
  部署(Docker/Helm/YAML) → LDAP + RBAC → 视图/凭据
  → 声明式 Pipeline 语法 → 代理 → 共享库/参数/Kaniko
  → SonarQube + MeterSphere 企业实战
        │
第4章 Jenkins 进阶 ── 静态/Docker/K8s 动态代理、Groovy、共享库、参数化、Kaniko
        │
第5章 Jenkins 企业实战 ── 测试流水线 + 飞书 + SQ + MeterSphere + 静态/动态代理两套实现
        │
第6章 Tekton ── Task/Pipeline/Workspace/Results/Triggers（K8s 原生 CI 对照）
第7章 Drone  ── GitLab + Docker/K8s pipeline（轻量 CI 对照）
        │
第8章 KubeVela ── OAM、项目/环境/交付目标、工作流、多集群（交付抽象对照）
第9章 Zadig   ── 一体化 CI/CD/测试平台（商业平台对照）
        │
第10章 Argo CD + Argo Rollouts
  Application/ApplicationSet/AppProject → syncPolicy/health/drift
  → Rollouts 蓝绿/金丝雀 → Istio + Prometheus 分析模板 → 自动回滚
```

## 2. 实验依赖关系（原文隐含）

| 依赖 | 说明 |
|---|---|
| K8s 集群 + NFS StorageClass | Jenkins Helm/YAML、Tekton、Drone、KubeVela、Zadig、Argo CD、Rollouts 的共同前置 |
| 可用的 Git 服务（GitLab） | webhook、多分支、PR、状态回传、Tekton/Drone 触发 |
| 镜像仓库（阿里云 ACR/私有 registry） | Jenkins、Tekton、Drone、Zadig、Argo CD 的镜像推送/拉取 |
| OpenLDAP | Jenkins、SonarQube、KubeVela、Zadig、Argo CD 的 SSO/RBAC 前置 |
| SonarQube + MeterSphere | Jenkins 第 5 章实战的质量/接口测试前置 |
| Istio + Prometheus | Argo Rollouts 10-19~10-22 的流量分析与自动回滚前置 |
| 公网/固定 IP/域名 | webhook、NodePort、LDAP、飞书、ACR 的前置 |

**结论**：课程是一条「多节点 K8s + NFS + LDAP + GitLab + ACR + 公网」的重型实验链，与本机单机环境不匹配。不能按章节顺序机械复现。

## 3. 术语与 ASR 还原（摘录）

| 原文 | 还原 | 依据 | 置信度 |
|---|---|---|---|
| 真皮实/整体时/正题十/金提子/精品词/静力时/金克斯 | Jenkins | 章节主题与上下文 | 高 |
| k八十/开八十/k8s样 | Kubernetes / YAML | 3-3、3-4、6-3 | 高 |
| 拍拍赖/啪啪赖/拍拍line | Pipeline | 3-10 起 | 高 |
| 勾语/购物/grovvy | Groovy | 4-5 | 高 |
| pi值 | PR（Pull Request） | 3-28/3-29 上下文；也可能是「PR 值」口误 | 中 |
| pre | 预发环境（pre-production），或分支前缀 `pre` | 3-8 视图分类讲「预发」；3-30 多分支含 `pre` | 中（需按上下文分别解释） |
| 妹分支 | 每个分支 / 多分支 | 3-30 多分支流水线上下文 | 中 |
| storm class/strong class | StorageClass | 3-4/3-5 持久化存储 | 高 |
| 解发器 | Trigger | 6-14 | 高 |
| 窝克斯贝斯/VCT | Workspace / VolumeClaimTemplate | 6-8~6-10 | 中 |
| 肉outs/阿狗罗话 | Argo Rollouts | 第 10 章 | 高 |
| 楞/与造林 | `len(result)` / `isNaN`（空值兜底） | 10-22 分析模板表达式 | 中 |
| 耶蒂 | 无法确认（可能是某个 CD 工具名） | 10-24 三工具对比 | 低 |
| 慕课 | 课程示例域名/组织名占位，不是真实域名 | 3-6 LDAP `DC=慕课,DC=CN` | 中 |

已确认的 ASR 错误不应写进项目文档作为事实；本项目的术语统一使用官方英文名与现行版本。

## 4. 严重问题与缺失步骤

### 4.1 Jenkins（第 3–5 章）

| # | 问题 | 证据 | 影响 | 本项目处理 |
|---|---|---|---|---|
| J1 | 版本全缺：`lts`、Kaniko `latest`、插件无版本 | 47、669 | 不可复现 | 锁定 Jenkins 2.580.1、插件版本、镜像 digest |
| J2 | `/var/run/docker.sock` + root 运行 | 3-3、869 | 宿主 root 等价权限 | 本地使用 Colima 专用 socket；PR 不给 Docker/仓库凭据；生产改 rootless BuildKit/Kaniko |
| J3 | LDAP/NFS/ACR/飞书/固定 IP 强绑定 | 32、46、416、731 | 换环境即失败 | 本地账号、无 PVC、Gitea、控制台失败报告 |
| J4 | cron 示例 `0-29/10` 被说成「每 10 分钟」 | 291–295 | 实际触发 3 次/小时 | 用 `H/15` 或明确 cron，写测试 |
| J5 | `disableConcurrentBuilds` 语义说反 | 170、706 | 误以为会终止旧构建 | 使用 `abortPrevious: true` 并验证 |
| J6 | RBAC 实操先删 admin 角色，可能自锁 | 113–117 | 无法恢复 | JCasC 保留管理员；最小权限 + 恢复路径 |
| J7 | 无健康检查、无回滚、无 imagePullSecret、无 JCasC | 710、871 | 交付不可验证 | 探针、Argo CD health、回滚脚本、Secret、JCasC |
| J8 | webhook 靠关闭 CSRF/SSL 校验 + 明文 token | 416–426 | 安全风险 | 本地 webhook 仅监听 loopback；token 入凭据；生产加签名/TLS |
| J9 | 5-10（docker.sock）与 5-11（Kaniko）工艺冲突 | 869、885 | 方案自相矛盾 | 采用受控 Docker 构建，记录 Kaniko/BuildKit 迁移路径 |
| J10 | 3-28「必须注释 skipDefaultCheckout 才能回传状态」 | 407–409 | 结论依赖实现细节 | 用 Gitea status API 显式回传，独立于 checkout 顺序 |

### 4.2 Tekton / Drone（第 6–7 章）

| # | 问题 | 证据 | 本项目处理 |
|---|---|---|---|
| T1 | 6-6 标题是 taskref/taskspec/pipelineref/pipelinespec，正文却是触发器，且与 6-14 重复 | 6-6/6-14 | 不纳入；只把 Tekton 作为「K8s 原生 CI」对照 |
| T2 | 仅一处 API 版本 `tekton.dev/v1beta1` | L59 | 已过时；如未来采用需升 v1 + Pipelines as Code |
| T3 | Trigger SA 直接绑 `cluster-admin` | L309 | 反模式；最小权限 |
| T4 | webhook 关闭 SSL 校验、凭据明文进 git URL、base64 当加密 | L96–102、329 | 安全红线；不复制 |
| T5 | Drone runner 挂 docker.sock + 特权容器 | L457–475 | 不复制 |
| T6 | 6-17 只有 sed + apply，无回滚/健康检查 | L343–372 | 本项目补部署验证与回滚 |
| T7 | Drone 不支持 GitLab 子组 | L434–438 | 选型时作为限制记录；本项目不用 Drone |

### 4.3 KubeVela / Zadig（第 8–9 章）

| # | 问题 | 证据 | 本项目处理 |
|---|---|---|---|
| D1 | 纯口述，安装脚本/参数丢失 | 8-2 | 不复刻 |
| D2 | 「多集群」用同一 kubeconfig 冒充第二集群 | L94、L201 | 多集群结论不可信；单机不引入 |
| D3 | GitLab 账密 base64、NodePort 弱口令、ACR 明文密码、触发器无鉴权 | L275、L472、L512、L259 | 安全红线 |
| D4 | Zadig v1.18.0 + K8s 1.16–1.26，MySQL+Mongo+NFS | L463、L473 | 版本过时、栈过重；不纳入 |
| D5 | 「1.18 以上都要付费」与 v2.0 后许可模式不符 | L465/735 | 仅作对比，不引用商业结论 |

### 4.4 Argo CD / Rollouts（第 10 章）

| # | 问题 | 证据 | 本项目处理 |
|---|---|---|---|
| A1 | 10-15 与 10-13 逐字重复；10-17 与 10-16 逐字重复 | 211–212、229–234 | 蓝绿介绍/实战缺失；Rollouts 暂缓 |
| A2 | 全章无版本号 | — | 锁定 Argo CD v3.5.0（支持 K8s 1.33–1.36） |
| A3 | 未讲 sync waves；AppProject 只当分类 | 57、103、184 | 用 Kustomize + 明确 AppProject；sync waves 作为扩展 |
| A4 | RBAC 资源名写成 `APP location/Application` | 182 | 使用真实 `applications` 资源与最小权限 |
| A5 | 「selfHeal 必须关，否则回滚失效」 | 97–100 | 正确做法：回滚 Git 提交；selfHeal 保留 |
| A6 | NodePort + 跳过证书告警 + 弱口令 + 明文初始密码 | 22–23、190 | port-forward/受控 NodePort、随机密码、Secret |
| A7 | 无 repo-creds、无 image updater、无自定义 health | 55 | 用 Argo CD repo Secret、Jenkins 更新镜像、内置 health |
| A8 | 「灰度最少 2 副本」、pause 1 小时 vs 60 秒矛盾 | 241–244 | 不引用；Rollouts 暂缓 |

## 5. 课程中「可直接采纳」的方法

1. 声明式 Pipeline 的 `pipeline / agent / stages / steps / post` 骨架，以及 `options`、`environment`、`withCredentials`、`parallel`、`when`、`input` 的用法。
2. 构建产物与流水线定义分离：Jenkinsfile 入仓，构建可重复；凭据按 ID 引用，不写死在脚本里。
3. 「CI 通过后才构建/推送镜像」的顺序门禁，以及失败时终止后续阶段。
4. 多分支/PR 与普通分支的区别：PR 只做验证，不发布；主分支才发布。
5. Argo CD 的核心模型：Git 是期望状态；Application 的 source/destination；syncPolicy 的 automated/prune/selfHeal；health 状态；drift 检测；Git 回滚。
6. 质量门禁应在「推送镜像/部署」之前失败（课程用 `waitForQualityGate`，本项目用测试/覆盖率/vet）。
7. 部署后必须检查状态，而不是只看 `kubectl apply` 返回码（本项目补 Argo CD health + rollout status + 接口验证）。

## 6. 明确不纳入本项目的课程内容

- Jenkins 的 LDAP、Role-Based Strategy 完整实操、MeterSphere、飞书通知、NFS/Helm/YAML 多节点部署、Kaniko 实操、K8s 动态代理。
- Tekton、Drone 的完整实验；只保留选型对照与「K8s 原生 CI」的差异说明。
- KubeVela、Zadig 的部署与实战；只保留 OAM/一体化平台的对照结论。
- Argo Rollouts 的蓝绿/金丝雀全量实验、Istio、Prometheus 分析模板自动回滚；保留为后续阶段的可选扩展。
- 所有需要关闭认证/校验、使用弱口令、明文凭据、`cluster-admin`、`docker.sock` 的做法。

## 7. 课程与 2026 版本差异（迁移提示）

| 课程环境 | 本项目环境 | 影响 |
|---|---|---|
| JDK 11（3-3/4-2） | Java 21.0.12 | Jenkins 2.580.1 支持 Java 21；旧插件需复核 |
| K8s 1.28（3-4） | K8s 1.35（如 K8s 阶段可行） | API/Ingress/CRD 版本变化；避免 `v1beta1` |
| Docker + docker.sock | Colima + Docker CLI（项目内 socket） | 本地可行；生产需 rootless/BuildKit |
| GitLab + 公网 webhook | Gitea 本地 + loopback webhook | 需本地 tunnel 才能接外部 webhook；本项目不依赖公网 |
| NFS StorageClass | 无 PVC / local-path | 不复制 NFS 依赖 |
| 阿里云 ACR | Zot 本地 registry | 认证、TLS、GC 简化 |
| SonarQube + MeterSphere | 测试/覆盖率/vet + 接口探针 | 质量门禁仍存在，工具更轻 |
| Argo CD 旧版 | Argo CD v3.5.0 | Application/RBAC/CLI 字段以新版为准 |
