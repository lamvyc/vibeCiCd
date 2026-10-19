# 阶段 0：验收标准与证据要求

> 本文件定义「什么叫完成」。任何能力只有附上可复核命令输出，才能标记「已实现且已验证」。
> 状态：`已实现且已验证` / `已实现但未验证` / `待实现` / `受环境限制`。禁止用「命令返回 0」「Pod Running」单独作为业务验证。

## 1. 端到端验收场景（对应任务第六节）

| # | 场景 | 操作 | 通过标准 | 证据 |
|---|---|---|---|---|
| 1 | 正常提交，流水线成功 | 在 `feature/*` 提交小改动 → PR → 合并 `main` | CI 全绿；镜像推送；GitOps 更新；部署 Synced/Healthy；`/api/version` 返回新 commit | Jenkins 构建 URL/控制台尾部；Gitea commit status；`docker inspect` digest；Argo CD Application JSON；curl 输出 |
| 2 | 有问题的代码，流水线失败 | 提交 `gofmt` 未格式化或编译错误 | 在 Lint/Build 阶段失败；PR 状态 failure；不进入 Push | 失败 stage 名称、日志片段、Gitea status API 输出 |
| 3 | 测试失败时不发布 | 提交一个断言失败的测试 | Test 阶段失败；registry 无该 commit 镜像；GitOps 无新提交 | `docker manifest inspect` 404/无 tag；`git log gitops/` 无对应提交；Jenkins 日志 |
| 4 | 镜像可构建/推送/拉取/启动 | 主分支构建；删除本地镜像后从 Zot 拉取；运行容器 | 拉取成功；容器健康；`/api/version` 正确；未认证拉取失败 | `docker pull` 输出；`docker run`；curl；`docker login` 失败用例 |
| 5 | 部署后健康、关键接口可访问 | 部署后 port-forward/NodePort；访问健康/版本/业务接口 | Pod Ready；探针通过；`/healthz`、`/readyz`、`/api/version` 200；版本=部署 digest 的 commit | `kubectl get pods`、`rollout status`、curl；Argo CD health |
| 6 | 人为失败场景，日志与排查 | 部署不存在的镜像 tag / 让 `/readyz` 失败 | 现象可复现（ImagePullBackOff/CrashLoop/Degraded）；能定位根因；有恢复步骤 | `kubectl describe`、events、logs；Argo CD 状态；修复/回滚后验证 |
| 7 | 回滚并验证恢复 | 部署坏版本 → `git revert` 或 `argocd rollback` | 恢复到已知可用 digest；Synced/Healthy；`/api/version` 恢复 | Git 历史、Application history、curl、部署记录 |
| 8 | GitOps 同步/异常识别 | 修改 GitOps 镜像 tag；制造仓库不可达/错误 path；改副本制造漂移 | 正常变更自动同步；异常状态可见（OutOfSync/Degraded/SyncFailed）；漂移自愈 | Argo CD UI/JSON、events、repo-server 日志、`kubectl get` |

> 若采用 Docker Compose 回退路径：场景 5/7 用 Compose 实现；场景 8 标记「受环境限制（无 K8s/Argo CD）」，并说明后续迁移条件。不得把 Compose 的 `up` 成功写成 GitOps 已验证。

## 2. CI 验收（Phase 1）

- [ ] Webhook 触发可追踪：Gitea delivery 记录、Jenkins build cause 一致。
- [ ] 分支策略：`main`/`feature/*`/PR 的行为符合设计表。
- [ ] 失败定位：能从 Jenkins stage 直接定位到具体步骤与日志。
- [ ] 测试报告：JUnit XML 可下载/展示；覆盖率报告可读。
- [ ] 凭据：日志中无明文密码/token；`withCredentials` 掩码生效。
- [ ] 配置可追踪：Jenkinsfile、JCasC、插件版本在 Git 中；UI 手工配置有记录/可重建。

## 3. 镜像与仓库验收（Phase 2）

- [ ] Dockerfile 合理：scratch/非 root/无源码/无密钥；`.dockerignore` 生效。
- [ ] 镜像大小/层数有记录；构建使用缓存（重复构建时间对比）。
- [ ] 标签与 Git commit 关联；部署使用 `tag@digest`，不是 `latest`。
- [ ] 推送/拉取/启动/健康检查全部通过；未认证拉取失败。
- [ ] 镜像内容检查：无 `.git`、`.env`、私钥、测试报告等不该进入的文件。
- [ ] 凭据通过 Jenkins credentials/Secret，不落盘明文。

## 4. 部署验收（Phase 3）

- [ ] 配置与环境分离：dev/prod overlay 差异明确（命名空间、副本、资源/环境变量）。
- [ ] 部署状态检查：不是只看 apply 返回码；检查 rollout/available replicas/探针。
- [ ] 应用健康：`/healthz`、`/readyz` 正常；关键业务接口返回预期。
- [ ] 失败处理：错误镜像/探针失败有日志、事件、定位与恢复记录。
- [ ] 部署记录：commit、digest、环境、时间、结果、验证响应摘要。
- [ ] 权限：部署使用的 kubeconfig/SA 最小权限；不使用 `cluster-admin`（本地如必须，记录并隔离）。

## 5. GitOps 验收（Phase 4，若实现）

- [ ] Git 是期望状态：应用变更只通过 GitOps 提交进入集群，Jenkins 不直接 `kubectl set image`。
- [ ] Application/AppProject：source/destination 限制明确；repo 凭据为只读 Secret。
- [ ] 自动同步：Git 变更 → Synced/Healthy；Jenkins 能轮询并验证。
- [ ] 漂移：手工改副本/镜像 → 被检测并自愈（或明确记录手动同步原因）。
- [ ] 异常：错误 path/镜像/仓库不可达 → OutOfSync/Degraded/SyncFailed，有事件与恢复。
- [ ] 回滚：Git revert 实际执行并验证；说明 `argocd rollback` 与 selfHeal 的关系。
- [ ] 不使用课程中的 NodePort 固定 IP、跳过证书、弱口令、明文初始密码。

## 6. 质量门禁与可观测性验收（Phase 5）

- [ ] 门禁在镜像推送前生效；失败样例可复现。
- [ ] 覆盖率阈值、vet、gofmt、密钥扫描的配置在 Git 中，可调整。
- [ ] Prometheus target `up=1`；应用指标可查询；5xx/up 规则可见 firing。
- [ ] 日志可定位请求/错误；不泄露敏感信息。
- [ ] 部署状态/健康状态可在 Jenkins/Argo CD/Prometheus 任一处交叉验证。
- [ ] 至少完成：测试失败、错误镜像、就绪失败、漂移四项演练（按实现路径）。

## 7. 安全验收

- [ ] 仓库无真实密码/Token/私钥；`.env.local`、`.runtime/`、kubeconfig 被 gitignore。
- [ ] Jenkins/K8s 日志无 secret；`set +x`/掩码有效。
- [ ] 镜像/容器非 root、只读根、drop capabilities（K8s）。
- [ ] Registry 认证生效；imagePullSecret 生效。
- [ ] 本地服务仅绑定 loopback/本机；未开放公网；未关闭认证/校验。
- [ ] 生产差距（TLS、SSO、Vault、NetworkPolicy、签名）在文档中明确，不谎称已实现。

## 8. 可维护性与可复现性验收

- [ ] 干净环境按 README 可从零启动（或明确前置下载/网络要求）。
- [ ] `versions.env`/`versions.lock` 记录版本与 digest；无无依据的 `latest`。
- [ ] 脚本幂等、有用法/注释；失败信息可操作。
- [ ] 无硬编码绝对路径/固定 IP（必要处用变量并文档化）。
- [ ] 配置修改有说明（作用、依赖、修改方式）。
- [ ] 停止/清理/重建步骤可执行；数据保留与 `--purge` 区分。

## 9. 证据模板

每项验证记录到 `docs/verification/<phase>-<scenario>.md`：

```markdown
# <场景>
- 日期/时间：
- 环境/版本（Jenkins、K8s、Argo CD、镜像 digest）：
- 前置：
- 命令：
- 关键输出（脱敏，保留错误行/状态码）：
- 结论：通过/失败/受环境限制
- 失败根因与修复：
- 关联提交/构建/部署记录：
```

## 10. 不能宣称完成的情况

- 只执行了 `docker build`，未验证 push/pull/run/health。
- 只执行了 `kubectl apply`，未检查 rollout/探针/接口。
- Argo CD 显示 Synced 但未验证业务接口/版本。
- 用 `latest` 或可变 tag 部署，无法追溯 commit。
- 测试失败但流水线继续推送/部署。
- 回滚只写在文档里，没有实际执行。
- K8s/Argo CD 因环境限制未跑通，却把 Docker Compose 的结果写成 K8s/GitOps 已验证。
- 课程中的错误/过时内容被当作事实写入，未标注来源或验证。
