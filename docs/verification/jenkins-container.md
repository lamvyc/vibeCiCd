# Jenkins 官方镜像迁移记录（WAR → 容器）

> 日期：2026-10-20。目标：在保留现有配置、数据与回滚能力的前提下，把 Jenkins 从宿主原生 WAR 切换为官方 Docker 镜像（`jenkins/jenkins:2.580.1-lts-jdk21`），并保持 Gitea → Jenkins → Zot → Argo CD 全链路可用。

## 1. 结论

| 项 | 结果 |
|---|---|
| 基础镜像 | 官方 `jenkins/jenkins:2.580.1-lts-jdk21`，按 digest 固定：`sha256:a660310e39ade10631f774bacd5219de767dfd08947ea5c32a739b5e5bb382c1` |
| 派生工具镜像 | `vibe-cicd/jenkins:2.580.1-tools-1`（`infra/jenkins/Dockerfile`），工具全部来自同版本官方 builder 镜像或带 SHA256 校验的官方二进制 |
| 控制器运行形态 | Colima VM 内 Docker 容器，`--network host`，监听 VM `8081` |
| 宿主访问 | SSH local forward `127.0.0.1:8081 → VM:8081`（与控制口隧道同一机制） |
| 数据 | 全量副本 `.runtime/jenkins-container`（1.6 GB，含 jobs、plugins、users、secrets、build history）；原 WAR 数据 `.runtime/jenkins` 未改动 |
| 回滚 | `JENKINS_RUNTIME=war ./scripts/bootstrap/90-start-all.sh`（原 WAR 与数据保持可用） |
| 全链路验证 | build #14（手动指定 SHA）与 build #17（Gitea push → 桥 → 容器控制器，真实触发路径）均全阶段 SUCCESS；镜像推送、GitOps 提交、Argo 同步、部署健康验证全部通过 |
| 控制器自检 | `migration-selfcheck` job（build #4 SUCCESS）：工具链、Gitea 凭据、pnpm 安装、Zot 推拉、k3s/Argo 可达 |

## 2. 运行时差异与处置

| 差异 | 处置 |
|---|---|
| 官方镜像缺少打包工具链（node/pnpm/go/docker/kubectl/kustomize/jq/xz/make/file） | 在 `infra/jenkins/Dockerfile` 中从同版本官方镜像复制（`node:24.18.0-trixie-slim`、`golang:1.27.2-trixie`、`docker:29.9.1-cli`），kubectl/kustomize 走官方二进制 + SHA256 校验；三个 builder 镜像同样按 digest 固定 |
| 容器内 Docker CLI 需要 VM 的 Docker daemon | 挂载 `/var/run/docker.sock`，`--group-add <gid>`（VM 内实测 991）；并显式设置 `DOCKER_HOST=unix:///var/run/docker.sock` |
| 宿主 `.runtime/docker/config.json` 含 `currentContext: colima`（宿主机 socket 绝对路径） | 显式 `DOCKER_HOST` 覆盖 context 解析；`DOCKER_CONFIG` 仍挂载只读，提供 Zot 认证 |
| k3s API 在 VM 内是 `127.0.0.1:6443`（宿主 kubeconfig 用的是 `16443` 隧道） | 生成 `.runtime/kubeconfig-container`，`server` 改写为 `https://127.0.0.1:6443`，只读挂载 |
| Update Center 需要本地元数据；宿主 8899 与 VM 不互通 | 在 VM 内启动 `python3 -m http.server 8899 --directory .runtime/uc`；副本的 `hudson.model.UpdateCenter.xml` 指向 `http://127.0.0.1:8899/update-center.json` |
| 容器不继承 VM 的代理变量；流水线内 pnpm/go 需要出口 | 运行时显式注入 `HTTP(S)_PROXY` 与 `NO_PROXY=localhost,127.0.0.1,::1,192.168.5.1`，本地服务（Gitea/Zot/k3s）直连 |
| 容器内文件属主 | `--user 501:20` 与副本属主一致（宿主 UID），Jenkins 可写自己的 home；`--group-add 991` 获得 socket 权限 |
| 构建上下文过大（`.runtime` 含 60 GB VM 磁盘镜像） | 新增根 `.dockerignore`，构建上下文只保留 `infra/jenkins/Dockerfile` |
| VM 内 `curl` 带代理变量但无 `no_proxy`，探活会误判 | 启动脚本的就绪探测使用 `curl --noproxy '*'` |

## 3. 验证证据

### 3.1 派生镜像工具链（`docker run --rm --entrypoint sh`）

```
java: openjdk version "21.0.12.1" 2026-08-18 LTS
node: v24.18.0     npm: 11.16.0     pnpm: 9.15.0
go: go1.27.2 linux/arm64
docker: 29.9.1     kubectl: v1.35.9  kustomize: v5.8.3
jq: 1.7            git: 2.47.3      curl: 8.14.1
xz: 5.8.1          make: 4.4.1      file: 5.46
id: uid=1000(jenkins)
```

### 3.2 控制器自检（`migration-selfcheck` build #4，SUCCESS）

- 工具链：`docker version --format server` → `29.5.2`（经挂载 socket 访问 VM daemon）
- Gitea 克隆：`gitea-ci` 凭据（JCasC 解密）成功克隆 `lowcode/lowcode-platform`
- pnpm：`pnpm install --frozen-lockfile` 成功（146 packages）
- Zot 往返：`docker login` → pull `sha-3e9cb2f34287` → tag/push `:selfcheck` → 删除本地 → 再 pull 成功
- k3s/Argo：`kubectl get nodes`（colima Ready）；`argocd: Synced Healthy`

### 3.3 真实流水线（`lowcode-platform` build #14，SUCCESS）

17 个阶段全部执行：Checkout SCM / Checkout platform / Classify / Checkout app / Report pending / Toolchain / Install / Typecheck / Test / Build frontend / Quality gate / Server test and build / Docker build / Image smoke test / Push image / GitOps update / Deploy verify。

- 镜像：`localhost:5001/lowcode-platform:sha-3e9cb2f34287`，digest `sha256:3f48982e2354b00a7117256051428c798fa54b8292c2f6f9f5c28b874ea3900e`
- GitOps：`[main 24db27f] chore(gitops): lowcode-platform sha-3e9cb2f34287 [skip ci]`
- 部署验证：`deployment verified: .runtime/deployments/dev-sha-3e9cb2f34287.json`
- 状态回传：`gitea status: ci/jenkins=success sha=3e9cb2f34287b92c3a2d12ab422a35c874d0664b`

### 3.4 独立的构建后核对

| 检查 | 结果 |
|---|---|
| Argo CD `lowcode-dev` | `Synced Healthy` |
| Pod | `lowcode-web-949ddbfc8-rf5zn`、`-tjdgr` 均 `1/1 Running` |
| Deployment 镜像 | `localhost:5001/lowcode-platform:sha-3e9cb2f34287@sha256:3f48982e…` |
| Zot 实际内容 | `Docker-Content-Digest: sha256:3f48982e…`（与流水线推送一致） |
| Argo synced revision | `24db27f`（与流水线 GitOps 提交一致） |

### 3.5 切换后 8081

```
GET http://127.0.0.1:8081/login → 200
API: numExecutors=2, jobs=[lowcode-platform(blue), migration-selfcheck]
lastBuild=14, lastSuccessful=14
jenkins-cli who-am-i → Authenticated as: admin
```

### 3.6 真实触发路径（Gitea push → 桥 → 容器控制器，build #17）

为验证切换后的生产触发链路，向应用仓库推送 `docs/ci-runtime.md`（分支 → PR #2 → 合并）：

```
21:18:21 桥: triggered branch feature/ci-runtime-note@3eb89ad9fbda http=201
21:18:21 桥: triggered PR #2@3eb89ad9fbda kind=pull_request http=201
          → build #15（分支）/ #16（PR）SUCCESS，commit status ci/jenkins=success
21:29:23 桥: triggered branch main@dde1a56ff5b9 http=201
          → build #17 全 18 阶段 SUCCESS
```

build #17 结果：

```
digest=localhost:5001/lowcode-platform@sha256:6c60811e97e497a5685b6351b49a3a12478cb4de0c2b572b3ed62dc4084e36e7
[main cbe613d] chore(gitops): lowcode-platform sha-dde1a56ff5b9 [skip ci]
deployment verified: .runtime/deployments/dev-sha-dde1a56ff5b9.json
gitea status: ci/jenkins=success sha=dde1a56ff5b901e525a729cd252dd2200a4fcc0f
Finished: SUCCESS
```

独立核对：Argo `Synced Healthy`（revision `cbe613d`）；Deployment 固定
`sha-dde1a56ff5b9@sha256:6c60811e…`；Zot `Docker-Content-Digest` 相同；Pod 1/1 Running；
`GET /api/version` → `{"commit":"dde1a56ff5b9…","version":"sha-dde1a56ff5b9"}`。

另外确认分支保护仍生效：直接 push `main` 被 pre-receive hook 拒绝，必须先经 PR 且
`ci/jenkins` 通过后才能合并——迁移没有削弱这道门禁。

## 4. 回滚

数据与配置在两处独立保留，任选其一即可：

```bash
# 方式一（推荐）：切回宿主 WAR，容器自动停止，反向转发恢复
JENKINS_RUNTIME=war ./scripts/bootstrap/90-start-all.sh
#   宿主 http://127.0.0.1:8081/ 即原 WAR（.runtime/jenkins，lastBuild=12）

# 方式二：只停容器、起 WAR
./scripts/bootstrap/21-jenkins-container.sh stop
./scripts/bootstrap/20-jenkins.sh

# 切回容器
./scripts/bootstrap/90-start-all.sh
```

约束：`.runtime/jenkins`（WAR 数据）与 `.tools/jenkins.war` 始终保留，未删除、未改动。

## 5. 已知限制

1. **手动触发必须带 `APP_SHA`**：`APP_SHA_RESOLVED` 为空时 Jenkins 不会导出该变量，
   Jenkinsfile 的 `set -u` 会在 Go 阶段报 `parameter not set`（build #13）。这是迁移前
   就存在的行为（webhook 触发总会带 `PAYLOAD_AFTER`）。手动/桥触发请传完整 40 位 SHA，
   或使用 `jenkins_cli build ... -p APP_SHA=<sha>`。
2. **Webhook 仍受沙箱 egress 策略限制**，Gitea 直连 Jenkins 不可用；CI 桥为触发主路径
   （迁移后桥继续指向 `127.0.0.1:8081`，语义不变）。
3. 容器以 `--restart unless-stopped` 运行；Docker/VM 重启后自动拉起，但 VM 内的
   Update Center 服务（8899）需要 `21-jenkins-container.sh` 重新启动（仅插件元数据用，
   不影响启动与构建）。
