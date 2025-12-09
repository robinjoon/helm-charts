# Matter Temperature Sensor Helm Chart

Matter 프로토콜을 사용하는 가상 IoT 온도 센서를 Kubernetes에 배포하기 위한 Helm Chart입니다.

## 개요

이 Helm Chart는 Matter.js를 사용하여 구현된 가상 온도 센서를 배포합니다. 현재는 고정값 10°C를 반환하며, 향후 날씨 API와 연동할 수 있도록 설계되었습니다.

**🎉 별도의 Docker 이미지 빌드가 필요 없습니다!**
- 소스 코드는 ConfigMap으로 관리
- 공식 Node.js 이미지 사용 (node:22-alpine)
- 런타임에 자동으로 npm 의존성 설치

## 특징

- ✅ Matter 프로토콜 지원
- ✅ 온도 센서 디바이스 타입 구현
- ✅ 블루투스 지원 노드에 자동 배포 (high-perf)
- ✅ 데이터 영구 저장 (PVC)
- ✅ Host 네트워크 모드 지원 (mDNS 검색용)
- ✅ Node.js 22 및 matter.js 라이브러리 사용
- ✅ ConfigMap 기반 소스 코드 관리 - Docker 빌드 불필요!
- ✅ InitContainer를 통한 자동 의존성 설치

## 전제 조건

- Kubernetes 1.19+
- Helm 3.0+
- 블루투스 기능이 있는 노드 (label: `kubernetes.io/hostname: high-perf`)
- PersistentVolume 프로비저너 (기본: local-path)

## 설치

### Helm Chart 설치 (Docker 빌드 불필요!)

```bash
# 기본 설정으로 설치
helm install matter-sensor ./matter-temperature-sensor

# 네임스페이스 지정하여 설치
helm install matter-sensor ./matter-temperature-sensor -n iot --create-namespace

# 커스텀 values 파일 사용
helm install matter-sensor ./matter-temperature-sensor -f custom-values.yaml
```

## 동작 방식

1. **ConfigMap**: `index.js`와 `package.json` 파일이 ConfigMap으로 저장됩니다
2. **InitContainer**: Pod 시작 시 `npm install --production`을 실행하여 의존성을 설치합니다
3. **Main Container**: Node.js 애플리케이션이 실행되어 Matter 온도 센서로 동작합니다

소스 코드를 수정하려면 `templates/configmap.yaml` 파일의 `index.js` 또는 `package.json` 섹션을 수정하고 Helm 차트를 업그레이드하면 됩니다:

```bash
helm upgrade matter-sensor ./matter-temperature-sensor
```

## 설정

주요 설정 옵션은 `values.yaml`에서 확인할 수 있습니다:

### 이미지 설정

```yaml
image:
  repository: node  # 공식 Node.js 이미지 사용
  pullPolicy: IfNotPresent
  tag: "22-alpine"
```

### 노드 선택기 (필수)

블루투스 기능이 있는 high-perf 노드에 배포하도록 설정:

```yaml
nodeSelector:
  kubernetes.io/hostname: high-perf
```

### 리소스 설정

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

### 스토리지 설정

```yaml
persistence:
  enabled: true
  storageClass: "local-path"
  accessMode: ReadWriteOnce
  size: 1Gi
```

### 네트워크 설정

Matter 프로토콜의 mDNS 검색을 위해 Host 네트워크 사용:

```yaml
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
```

## 사용 방법

### 1. Pod 상태 확인

```bash
kubectl get pods -l app.kubernetes.io/name=matter-temperature-sensor
```

### 2. 로그 확인

InitContainer의 npm install 로그를 확인:
```bash
kubectl logs -l app.kubernetes.io/name=matter-temperature-sensor -c npm-install
```

애플리케이션 로그 확인:
```bash
kubectl logs -l app.kubernetes.io/name=matter-temperature-sensor -f
```

### 3. Matter 디바이스 페어링

- Apple Home, Google Home, SmartThings 등 Matter 호환 앱 실행
- 새 디바이스 추가
- Matter 디바이스 검색
- 화면의 지시에 따라 페어링 진행

### 4. 온도 확인

페어링 후 Matter 컨트롤러 앱에서 온도 센서의 현재 값(10°C)을 확인할 수 있습니다.

### 5. 소스 코드 수정

`templates/configmap.yaml` 파일을 수정한 후:

```bash
# Helm 차트 업그레이드
helm upgrade matter-sensor ./matter-temperature-sensor

# ConfigMap이 변경되면 자동으로 Pod가 재시작됩니다
```

## 제거

```bash
helm uninstall matter-sensor
```

PVC도 함께 삭제하려면:

```bash
kubectl delete pvc -l app.kubernetes.io/name=matter-temperature-sensor
```

## 향후 개발 계획

- [ ] 날씨 API 연동 (실시간 온도 데이터)
- [ ] 추가 센서 타입 지원 (습도, 기압 등)
- [ ] 환경 변수를 통한 센서 값 설정
- [ ] Prometheus 메트릭 노출

## 문제 해결

### Pod가 시작되지 않음

1. 노드 레이블 확인:
   ```bash
   kubectl get nodes --show-labels | grep high-perf
   ```

2. InitContainer 로그 확인 (npm install 실패 가능성):
   ```bash
   kubectl logs -l app.kubernetes.io/name=matter-temperature-sensor -c npm-install
   ```

### npm install이 실패함

1. 네트워크 연결 확인 (npmjs.com 접근 가능한지)
2. 프록시 설정이 필요한 경우 initContainer에 환경 변수 추가

### Matter 디바이스가 검색되지 않음

1. hostNetwork가 활성화되어 있는지 확인
2. 블루투스가 노드에서 활성화되어 있는지 확인
3. 파드 로그에서 에러 메시지 확인

## 참고 자료

- [Matter.js GitHub](https://github.com/matter-js/matter.js)
- [Matter 프로토콜 공식 사이트](https://buildwithmatter.com)
- [@matter.js/examples](https://www.npmjs.com/package/@matter.js/examples)

## 라이선스

This project uses Matter.js which is Apache-2.0 licensed.
