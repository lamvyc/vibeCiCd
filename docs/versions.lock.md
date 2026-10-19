# 实际版本与关键摘要（2026-10-20）

> 用于复现与审计。tag 之外，关键镜像记录 digest；镜像/二进制摘要来自实际拉取与运行。

## 主机与工具

| 项 | 版本 |
|---|---|
| macOS | 27.0.1 arm64 |
| CPU / RAM / Disk | 12 vCPU / 24 GB / 约 210 GB 可用 |
| Java | OpenJDK 21.0.12（Homebrew） |
| Node / pnpm | 24.18.0 / 9.15.0 |
| Go | 1.27.2 |
| Colima / Lima | 0.10.3 / 2.2.1 |
| Docker CLI / Server | 29.9.1 / 29.5.2（VM 内，arm64） |
| kubectl | 1.35.9（keg-only `kubernetes-cli@1.35`） |
| kustomize | 5.8.3 |
| Helm | 4.3.1（仅用于渲染 Argo CD chart） |

## 服务

| 服务 | 版本/摘要 |
|---|---|
| Jenkins | 2.580.1；77 个插件；JCasC；Java 21 |
| Gitea | 28.2.0；`ghcr.io/go-gitea/gitea@sha256:30777c91280d973fa02be48b1ade735bd6859e8f6f7af3b4444d519437852504` |
| k3s / K8s | v1.35.0+k3s1 / v1.35.0；单节点 `colima` |
| k3s 二进制来源 | `ghcr.io/k3s-io/k3s@sha256:10464930d9bad0c06aef9830e84cd4019c24ed44d5eab594efb7416119097248` 提取 `/bin/k3s` + `/bin/cni` |
| k3s airgap 镜像 | `k3s-airgap-images-arm64.tar.gz`，SHA256 `cb3d24f44c9f29da3421e99db0801f2a30b3e16c7032c423a9b631c0fc66a5fa` |
| Colima 镜像 | `ubuntu-24.04-minimal-cloudimg-arm64-docker.raw.gz`，SHA512 `32242674b046b5057e60c4aba334b51e3665f05412cda89ed081cc2de153ae5c41f6b105b5c442cbe48d78e2cc21e9ba1950e406b6fb4fc2fd1dd2259240abbd` |
| Zot | 2.1.22；`ghcr.io/project-zot/zot@sha256:96cda11459ce6f8c60da3b03f03e9f67fd11b3ae2d82c4c04c92b3c608996080` |
| Argo CD | v3.5.5；Helm chart 10.10.5；`quay.io/argoproj/argocd:v3.5.5` |
| Prometheus | v3.8.0；`quay.io/prometheus/prometheus:v3.8.0` |
| Redis（Argo CD） | `ecr-public.aws.com/docker/library/redis:8.6.4-alpine` |

## 应用镜像（Zot）

| tag | digest | 说明 |
|---|---|---|
| `sha-51de0d5e2bff` | `sha256:d10f0b0da7bc22ce697be9803421759b5d2b19d05a57e222e03534bbf4ba21ec` | 首次完整 CI 推送（build #5） |
| `sha-3e9cb2f34287` | `sha256:cd4ee6d44b181c007596eea66dd2e796f516d38849dfd9418238f66b88d6a1c6` | PR #1 合并后的最终部署（build #11） |

## 关键 Git 提交

| 仓库 | commit | 说明 |
|---|---|---|
| 应用 `lowcode-platform` | `3e9cb2f34287b92c3a2d12ab422a35c874d0664b` | PR #1 merge 到 main |
| 应用（失败演练） | `2c1dc0788184b95b0f696ad44486ace211cc4685` | 故意失败测试，未发布 |
| 平台/GitOps `vibe-cicd` | `9428f581b44e981d5e2826107ee1d3dafce154cc` | 回滚坏镜像演练后的 main（含 revert） |
| 平台/GitOps 文档 | `299c4a56f1ec85e68f24e61f22f8ddead88cd8db` | 验收记录、runbook、版本与 bootstrap 脚本 |

> 平台仓库后续还会增加文档/脚本提交；以 Gitea `main` 最新提交为准。
