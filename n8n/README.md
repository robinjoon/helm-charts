# n8n Helm Chart

n8n 워크플로우 자동화 플랫폼을 Kubernetes에 배포하기 위한 Helm 차트입니다.

## 특징

- ✅ Queue 모드로 분산 처리 지원
- ✅ Worker 자동 스케일링 (2~5개)
- ✅ **외부 PostgreSQL** 데이터베이스 연동
- ✅ **외부 Valkey(Redis)** 기반 작업 큐
- ✅ Traefik Ingress 설정
- ✅ TLS 인증서 지원
- ✅ NFS 영구 스토리지

> **참고:** 이 차트는 PostgreSQL과 Valkey를 새로 배포하지 않습니다. 기존에 구축된 외부 서비스를 사용합니다.

## 아키텍처

```
┌─────────────┐
│   Traefik   │ ← https://homelab.robinjoon.xyz/n8n
└──────┬──────┘
       │
┌──────▼──────────┐
│  n8n Main (1)   │ ← UI, API
└──────┬──────────┘
       │
       ├──────────────────┐
       │                  │
┌──────▼──────────┐  ┌───▼────────────┐
│ 외부 Valkey     │  │ 외부 PostgreSQL │
│ (작업 큐)       │  │ (데이터베이스)   │
└──────┬──────────┘  └─────────────────┘
       │
┌──────▼───────────────┐
│  Worker (2~5개)      │ ← 워크플로우 실행
│  Autoscaling 활성화  │
└──────────────────────┘
```

## 배포 전 준비사항

> **중요:** 이 Helm 차트를 배포하기 전에 PostgreSQL과 Valkey가 이미 클러스터에 배포되어 있어야 합니다.

### 1. PostgreSQL 데이터베이스 준비

**외부 PostgreSQL 서비스가 필요합니다.** PostgreSQL에 n8n용 데이터베이스와 사용자를 생성해야 합니다:

```bash
# PostgreSQL pod에 접속
kubectl exec -it -n postgresql postgresql-primary-0 -- bash

# psql로 접속
psql -U postgres

# n8n 데이터베이스와 사용자 생성
CREATE DATABASE n8n;
CREATE USER n8n WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;
\q
```

### 2. Valkey(Redis) 준비

**외부 Valkey 서비스가 필요합니다.** n8n은 작업 큐를 위해 Valkey/Redis를 사용합니다.

예상되는 Valkey 서비스 주소:
- `valkey-primary.valkey.svc.cluster.local:6379`

다른 주소를 사용하는 경우 `values.yaml`의 `main.config.queue.bull.redis.host`를 수정하세요.

### 3. Kubernetes Secret 생성

```bash
# 네임스페이스 생성
kubectl create namespace n8n

# Secret 예시 파일 복사
cp secret.example.yaml secret.yaml

# secret.yaml 파일 수정 (비밀번호 입력)
nano secret.yaml

# Secret 적용
kubectl apply -f secret.yaml -n n8n
```

**⚠️ 중요:**
- `secret.yaml` 파일은 `.gitignore`에 포함되어 있어 Git에 커밋되지 않습니다.
- PostgreSQL 비밀번호는 외부 PostgreSQL에 설정한 n8n 사용자의 비밀번호와 일치해야 합니다.
- Redis 비밀번호는 외부 Valkey 서비스의 비밀번호와 일치해야 합니다.

### 4. 비밀번호 생성 팁

안전한 랜덤 비밀번호 생성:

```bash
# Redis 비밀번호 생성
openssl rand -base64 32
```

## 배포

### Helm으로 배포

```bash
# 차트 디렉토리로 이동
cd n8n

# values.yaml 확인 (필요시 수정)
cat values.yaml

# 헬름 차트 배포
helm install n8n . -n n8n

# 또는 업그레이드
helm upgrade --install n8n . -n n8n
```

### 배포 상태 확인

```bash
# Pod 상태 확인
kubectl get pods -n n8n

# 서비스 확인
kubectl get svc -n n8n

# Ingress 확인
kubectl get ingress -n n8n

# 로그 확인
kubectl logs -n n8n -l app.kubernetes.io/name=n8n -f
```

## 설정 정보

### 리소스 할당

이 차트가 배포하는 컴포넌트:

| 컴포넌트 | CPU (요청/제한) | Memory (요청/제한) | 스토리지 |
|----------|----------------|-------------------|----------|
| Main     | 500m / 1000m   | 512Mi / 1Gi       | 50Gi     |
| Worker   | 500m / 1000m   | 512Mi / 1Gi       | -        |

> **참고:** PostgreSQL과 Valkey는 별도로 배포되어 있으므로 위 리소스에 포함되지 않습니다.

### Worker 스케일링

- **초기**: 2개
- **최소**: 2개
- **최대**: 5개
- **각 워커 동시 처리**: 10개 작업
- **총 처리 능력**: 20~50개 워크플로우 동시 실행

### 접속 정보

- **URL**: https://homelab.robinjoon.xyz/n8n
- **네임스페이스**: n8n
- **외부 데이터베이스**: PostgreSQL (postgresql-primary.postgres.svc.cluster.local:5432)
- **외부 큐**: Valkey (valkey-primary.valkey.svc.cluster.local:6379)

## 문제 해결

### Pod가 시작되지 않는 경우

```bash
# Pod 상태 확인
kubectl describe pod -n n8n <pod-name>

# 로그 확인
kubectl logs -n n8n <pod-name>

# Secret 확인
kubectl get secret n8n-secrets -n n8n -o yaml
```

### 데이터베이스 연결 오류

```bash
# PostgreSQL 연결 테스트
kubectl run -it --rm debug --image=postgres:16 --restart=Never -n n8n -- \
  psql -h postgresql-primary.postgresql.svc.cluster.local -U n8n -d n8n
```

### Redis 연결 오류

```bash
# Valkey 연결 테스트
kubectl run -it --rm debug --image=redis:7 --restart=Never -n n8n -- \
  redis-cli -h n8n-valkey-master -a <redis-password> ping
```

## 업그레이드

```bash
# 차트 업그레이드
helm upgrade n8n . -n n8n

# 특정 값 오버라이드
helm upgrade n8n . -n n8n --set worker.replicaCount=3
```

## 삭제

```bash
# Helm 릴리스 삭제
helm uninstall n8n -n n8n

# Secret 삭제 (선택사항)
kubectl delete secret n8n-secrets -n n8n

# 네임스페이스 삭제 (선택사항)
kubectl delete namespace n8n
```

## 참고

- [n8n 공식 문서](https://docs.n8n.io/)
- [n8n Helm Chart GitHub](https://github.com/8gears/n8n-helm-chart)
- [n8n 환경변수 설정](https://docs.n8n.io/hosting/configuration/environment-variables/)
