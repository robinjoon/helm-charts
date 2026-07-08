# Zot 사설 컨테이너 레지스트리 도입 설계

작성일: 2026-07-08

## 배경 / 목표

homelab k3s(단일 노드)에 `second-brain` 앱을 배포하려면 직접 빌드한 앱 이미지를
**공개하지 않고** 담을 사설 레지스트리가 필요하다. 기존 차트는
`harbor.homelab.robinjoon.xyz` 를 참조하지만 homelab 초기화로 Harbor는 사라졌다.

**결정: Harbor 대신 Zot(경량 OCI 레지스트리)를 도입한다.**
단일 노드·1인·소수 이미지 환경에서 Harbor(파드 8~10개, 자체 postgres/redis, 스캔/서명/RBAC)는
과하다. Zot은 파드 1개로 "사설 push/pull"이라는 핵심 요구를 충족한다. 스캔·서명·멀티테넌시가
필요해지면 그때 Harbor로 승격한다.

이 문서는 **Phase 1(레지스트리 구축)** 만 다룬다. `second-brain` 앱 자체 배포
(DB/CNPG·valkey·시크릿·마이그레이션)는 이미지가 준비된 뒤 **Phase 2**로 분리한다.

## 기존 환경 (조사 결과)

- k3s 단일 노드(`homw-werver`, amd64, containerd), 리소스 여유 충분(mem 12%)
- GitOps: **ArgoCD app-of-apps** (`argocd/apps/<name>.yaml`), repo `github.com/robinjoon/helm-charts`
- cert-manager `letsencrypt-prod` (**Cloudflare DNS-01**) → 외부 노출 없이도 유효한 LE 인증서 발급
- `*.homelab.robinjoon.xyz` **와일드카드 DNS** 이미 존재 → `registry.` 추가 DNS 작업 불필요
- ingress: traefik / StorageClass: `local-path`(default)
- 관례(headlamp): 업스트림 차트를 App의 `helm.valuesObject`로 인라인, ingress+cert-manager로 TLS,
  **비밀번호 시크릿은 git에 안 올리고 out-of-band 생성**

## 아키텍처

```
argocd/apps/registry.yaml  ─(ArgoCD sync)→  namespace: registry
  └ chart: zot (https://zotregistry.dev/helm-charts, classic HTTP repo)  # headlamp와 동일 패턴
       ├ Deployment/StatefulSet (zot pod ×1)
       ├ PVC (local-path, 20Gi)                 → /var/lib/registry
       ├ mountConfig → /etc/zot/config.json      (인증·accessControl·zui, git 커밋; 비밀 없음)
       ├ externalSecrets → /secret/htpasswd      (out-of-band Secret, git 미커밋)
       └ Ingress(traefik) → https://registry.homelab.robinjoon.xyz
            └ cert-manager letsencrypt-prod → registry-tls
```

## 핵심 설계 결정

1. **인증은 Zot 자체 htpasswd로 처리. Traefik basic-auth 미들웨어는 쓰지 않는다.**
   레지스트리는 `/v2/`에서 자기 `WWW-Authenticate` 헤더로 docker/containerd와 인증 협상을
   해야 한다. 앞단 Traefik이 basic-auth를 가로채면 push/pull이 깨진다. Ingress는
   TLS 종단·라우팅만 담당한다.
2. **완전 사설**: accessControl `defaultPolicy: []` + `anonymousPolicy: []`, admin 유저만
   read/create/update/delete. 익명 pull 불가.
3. **자격증명은 git에 넣지 않는다**: htpasswd는 out-of-band Secret(`zot-htpasswd`)을
   `externalSecrets`로 마운트. probe(`/livez`·`/readyz`·`/startupz`)는 zot 소스상 **인증
   미들웨어 이전에 등록**되어 인증 없이 접근되므로 `authHeader`(자격증명) 불필요 — 확인 완료.
4. **zui 웹 UI 활성화**(`extensions.ui.enable`, `extensions.search.enable`). 동일 바이너리 내장.

## Zot config.json (mountConfig, git 커밋 — 비밀 없음)

```json
{
  "storage": { "rootDirectory": "/var/lib/registry" },
  "http": {
    "address": "0.0.0.0",
    "port": "5000",
    "auth": { "htpasswd": { "path": "/secret/htpasswd" } },
    "accessControl": {
      "repositories": { "**": { "defaultPolicy": [], "anonymousPolicy": [] } },
      "adminPolicy": { "users": ["<ADMIN_USER>"], "actions": ["read","create","update","delete"] }
    }
  },
  "log": { "level": "info" },
  "extensions": { "search": { "enable": true }, "ui": { "enable": true } }
}
```

## 구성 요소 / 산출물

### git 커밋 대상 (helm-charts repo)
1. `argocd/apps/registry.yaml` — ArgoCD Application (zot 차트 + 위 valuesObject: ingress/TLS/
   mountConfig/externalSecrets/persistence 20Gi/zui)
2. `second-brain` 차트 수정
   - `values.yaml`, `values/values-k3s.yaml`: 이미지 호스트 `harbor.homelab.robinjoon.xyz`
     → `registry.homelab.robinjoon.xyz`, pull secret 이름 `harbor-pull-secret` → `regcred`
3. 본 설계 문서

### out-of-band (git 미커밋, kubectl로 생성)
4. `registry/zot-htpasswd` Secret — key `htpasswd`(user + bcrypt)
5. `second-brain/regcred` Secret — dockerconfigjson (동일 자격증명, k3s pull용)
   - 자격증명은 사용자에게 별도 전달 → CI/`docker login`에도 사용

## 작업 분담

- **내가(Claude) 수행**: 위 git 산출물 작성·커밋, out-of-band 시크릿 생성, 자격증명 생성·전달,
  ArgoCD sync 후 레지스트리 기동 검증
- **사용자 수행**: `second-brain` 시드 이미지 빌드·푸시 (기존 CI/수동). Mac이 arm64이므로
  `--platform linux/amd64` 크로스빌드 필요. LAN에서 공인 IP 헤어핀이 안 되면 `/etc/hosts`로
  `registry.homelab.robinjoon.xyz → 192.168.0.195` 고정 후 push.

## 검증 기준

1. ArgoCD `registry` App Synced/Healthy, zot pod Ready(1/1)
2. `https://registry.homelab.robinjoon.xyz/v2/` 가 유효한 LE 인증서로 응답, 미인증 시 401
3. 자격증명으로 `docker login` 성공 → (사용자) push/pull 왕복 성공
4. zui(`https://registry.homelab.robinjoon.xyz`) 로그인 후 이미지 목록 확인
5. (Phase 2 진입 조건) `second-brain` 네임스페이스에서 `regcred`로 이미지 pull 성공

## 미결/구현 시 확인

- zot 차트 ingress values 키 정확한 스키마(className/hosts/tls) — 매니페스트 작성 시 대조
- classic repo의 최신 chart 버전(targetRevision) — index.yaml 확인 후 고정
- 대용량 레이어 push용 zot `readTimeout`/`writeTimeout`(기본 60s) 상향 필요 여부
