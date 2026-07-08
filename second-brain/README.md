# Second Brain Helm Chart

Second Brain을 k3s 또는 Kubernetes에 배포하기 위한 Helm chart입니다. 이 차트는 GitHub Issue #14의 배포 요구사항을 기준으로 만들되, 이슈 생성 이후 바뀐 현재 앱 구조를 반영합니다.

## 현재 앱 기준

- 저장소는 PostgreSQL 단일 provider를 사용합니다. 예전 설계의 `STORAGE_PROVIDER` 값은 차트에 넣지 않습니다.
- sync 상태는 PostgreSQL에 저장됩니다. 예전 `.data/sync-status.json` 보존용 PVC는 기본 비활성화 상태로만 지원합니다.
- 앱 서버와 sync worker는 같은 이미지에서 각각 `npm run start`, `npm run sync:watch`를 실행합니다.
- worker의 `APP_BASE_URL` 기본값은 내부 Service 주소입니다.
- `AUTH_MODE=required`에서는 앱과 worker가 같은 `APP_INTERNAL_API_TOKEN`을 Secret으로 받아야 보호된 sync API를 호출할 수 있습니다.
- MCP endpoint는 `APP_INTERNAL_API_TOKEN`이 아니라 `npm run mcp:create-key`로 발급한 별도 API key를 사용합니다.
- AI 호출 방식은 현재 코드 기준으로 `AI_API_MODE=responses`가 기본입니다. Mac mini VibeProxy override는 OpenAI-compatible chat completions 호환성을 위해 `chat`을 사용합니다.

## 이미지 계약

이 차트는 이미지 안에 Second Brain 앱과 의존성이 들어 있고 다음 npm script가 실행 가능하다고 가정합니다.

- `npm run start`
- `npm run sync:watch`
- `npm run db:migrate`
- `npm run db:seed`

앱 컨테이너는 `PORT`와 `HOSTNAME` 환경변수를 따르며 기본값은 `3000`, `0.0.0.0`입니다.

## Secret

운영 배포에서는 Secret을 직접 만들고 `secretRefs.existingSecret`로 연결하는 방식을 권장합니다.

```bash
kubectl create namespace second-brain

kubectl -n second-brain create secret generic second-brain-env \
  --from-literal=DATABASE_URL='postgres://user:password@postgresql:5432/second_brain' \
  --from-literal=AI_API_KEY='sk-...' \
  --from-literal=AUTH_SECRET='change-to-long-random-secret' \
  --from-literal=AUTH_USERNAME='admin' \
  --from-literal=AUTH_PASSWORD_HASH='scrypt:...' \
  --from-literal=APP_INTERNAL_API_TOKEN='change-to-long-random-token'
```

`AUTH_PASSWORD_HASH`는 앱 README의 scrypt 생성 명령으로 만들 수 있습니다. 개발 확인용으로만 `AUTH_PASSWORD`를 사용할 수 있고, 운영에서는 `AUTH_PASSWORD_HASH`를 권장합니다.

사설 레지스트리(Zot)에서 이미지를 당겨오려면 namespace에 pull secret도 필요합니다. `values/values-k3s.yaml`은 기본으로 `regcred`를 참조합니다.

```bash
kubectl -n second-brain create secret docker-registry regcred \
  --docker-server=registry.homelab.robinjoon.xyz \
  --docker-username='<registry-username>' \
  --docker-password='<registry-password>'
```

OpenAI 호환 로컬 proxy를 쓰는 경우:

```yaml
config:
  env:
    AI_BASE_URL: http://vibeproxy.default.svc.cluster.local:8317/v1
    AI_API_MODE: chat
```

## AI API proxy

Second Brain은 `AI_BASE_URL`을 OpenAI 호환 API base URL로 사용합니다. 이 차트는 `aiProxy` 옵션으로 두 가지 방식을 지원합니다.

### 1. 클러스터 내부 CLIProxyAPI

`router-for-me/CLIProxyAPI`를 별도 Deployment로 실행하고, Second Brain 앱에는 내부 Service URL을 `AI_BASE_URL`로 자동 주입합니다.

```bash
helm upgrade --install second-brain ./second-brain \
  -n second-brain \
  --create-namespace \
  -f ./second-brain/values/values-k3s.yaml \
  -f ./second-brain/values/values-ai-proxy-internal-cliproxy.yaml
```

기본 내부 proxy URL:

```text
http://second-brain-ai-proxy:8317/v1
```

내부 모드는 다음 리소스를 추가합니다.

- `Deployment/second-brain-ai-proxy`
- `Service/second-brain-ai-proxy`
- CLIProxyAPI `config.yaml` Secret
- OAuth/auth 파일 보존용 PVC

기본 `config.yaml`은 클러스터 내부 사용을 위한 최소 예시입니다. 운영에서는 `aiProxy.internal.config` 또는 `aiProxy.internal.existingConfigSecret`로 API key, OAuth provider, model alias 등을 명시하세요.

### 2. 외부 Mac mini VibeProxy를 k8s Service처럼 노출

Mac mini에서 VibeProxy 또는 CLIProxyAPI를 실행하고, k8s에는 selector 없는 Service와 Endpoints만 생성합니다. Second Brain은 여전히 내부 DNS 이름을 사용합니다.

```yaml
aiProxy:
  enabled: true
  mode: external
  external:
    addressType: IPv4
    addresses:
      - 192.168.0.50
    port: 8317
```

배포:

```bash
helm upgrade --install second-brain ./second-brain \
  -n second-brain \
  --create-namespace \
  -f ./second-brain/values/values-k3s.yaml \
  -f ./second-brain/values/values-ai-proxy-external-macmini.yaml
```

이 방식에서는 다음 주소가 앱에 자동 주입됩니다.

```text
AI_BASE_URL=http://second-brain-ai-proxy:8317/v1
```

Mac mini 쪽 proxy는 k8s 노드에서 접근 가능한 인터페이스에 바인딩되어 있어야 합니다. CLIProxyAPI 계열 기본 포트는 예시 기준 `8317`입니다. VibeProxy/CLIProxyAPI가 Responses API를 지원하지 않는 조합이면 `AI_API_MODE=chat`으로 두세요.

## 설치

기본 설치:

```bash
helm upgrade --install second-brain ./second-brain \
  -n second-brain \
  --create-namespace
```

k3s/Traefik 예시 values 사용:

```bash
helm upgrade --install second-brain ./second-brain \
  -n second-brain \
  --create-namespace \
  -f ./second-brain/values/values-k3s.yaml
```

Ingress host는 실제 도메인으로 바꿔서 사용합니다.

```yaml
ingress:
  enabled: true
  className: traefik
  hosts:
    - host: second-brain.robinjoon.xyz
      paths:
        - path: /
          pathType: Prefix
```

## Migration과 seed

PostgreSQL migration은 Helm hook Job으로 선택 실행합니다.

```bash
helm upgrade --install second-brain ./second-brain \
  -n second-brain \
  --create-namespace \
  -f ./second-brain/values/values-k3s.yaml \
  --set migration.enabled=true
```

초기 AI 설정과 카테고리 seed까지 같이 실행하려면:

```bash
helm upgrade --install second-brain ./second-brain \
  -n second-brain \
  --create-namespace \
  -f ./second-brain/values/values-k3s.yaml \
  --set migration.enabled=true \
  --set migration.runSeed=true
```

seed에서 사용할 수 있는 환경변수:

- `DEFAULT_AI_MODEL`
- `DEFAULT_REASONING_EFFORT`
- `DEFAULT_DESCRIPTION_REASONING_EFFORT`
- `DEFAULT_RELATION_REASONING_EFFORT`
- `DEFAULT_DESCRIPTION_PROMPT`
- `DEFAULT_RELATION_PROMPT`
- `DEFAULT_DESCRIPTION_MAX_COMPLETION_TOKENS`
- `DEFAULT_RELATION_MAX_COMPLETION_TOKENS`
- `DEFAULT_TEMPERATURE`
- `DEFAULT_CATEGORY_OPTIONS`

## AUTH_MODE=required 설정

`AUTH_MODE=required`에서는 다음 값들이 필요합니다.

```yaml
config:
  env:
    AUTH_MODE: required

secretRefs:
  existingSecret: second-brain-env
```

Secret에는 앱 로그인용 `AUTH_SECRET`, `AUTH_USERNAME`, `AUTH_PASSWORD_HASH`와 worker 내부 호출용 `APP_INTERNAL_API_TOKEN`을 함께 넣습니다. 앱 Deployment와 worker Deployment가 같은 Secret을 읽기 때문에 protected sync API 호출에 같은 Bearer token이 사용됩니다.

## 운영 명령

상태 확인:

```bash
kubectl -n second-brain get pods
kubectl -n second-brain get ingress
```

로그 확인:

```bash
kubectl -n second-brain logs deploy/second-brain
kubectl -n second-brain logs deploy/second-brain-worker
```

배포 이력:

```bash
helm -n second-brain history second-brain
```

롤백:

```bash
helm -n second-brain rollback second-brain <REVISION>
```

Secret 변경 후 재시작:

```bash
kubectl -n second-brain rollout restart deploy/second-brain
kubectl -n second-brain rollout restart deploy/second-brain-worker
```

## 주요 values

| 값 | 설명 | 기본값 |
| --- | --- | --- |
| `image.repository` | Second Brain 이미지 | `registry.homelab.robinjoon.xyz/second-brain/second-brain` |
| `imagePullSecrets` | private registry pull secret 목록 | `[]` |
| `config.env.AUTH_MODE` | 인증 모드 | `disabled` |
| `secretRefs.existingSecret` | env 키를 담은 기존 Secret 이름 | `""` |
| `worker.enabled` | sync worker Deployment 생성 | `true` |
| `worker.appBaseUrl` | worker가 호출할 앱 URL. 비우면 내부 Service URL | `""` |
| `migration.enabled` | migration Job 실행 | `false` |
| `migration.runSeed` | migration 후 seed 실행 | `false` |
| `ingress.enabled` | Ingress 생성 | `false` |
| `persistence.enabled` | legacy `.data` PVC 사용 | `false` |
| `aiProxy.enabled` | AI API proxy 보조 리소스 생성 | `false` |
| `aiProxy.mode` | `internal` 또는 `external` | `external` |
| `aiProxy.useAsAppAiBaseUrl` | 앱에 `AI_BASE_URL` 자동 주입 | `true` |
