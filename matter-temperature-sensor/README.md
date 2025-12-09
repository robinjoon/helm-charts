# Matter Temperature Sensor Helm Chart

Matter 프로토콜을 사용하는 가상 IoT 온도 센서를 Kubernetes에 배포하기 위한 Helm Chart입니다.

## 개요

이 Helm Chart는 Matter.js를 사용하여 구현된 실시간 온도 센서를 배포합니다. **OpenWeatherMap API**를 통해 실제 날씨 데이터를 가져와 Matter 디바이스로 제공합니다.

**🎉 별도의 Docker 이미지 빌드가 필요 없습니다!**
- 소스 코드는 ConfigMap으로 관리
- 공식 Node.js 이미지 사용 (node:22)
- 런타임에 자동으로 npm 의존성 설치

**🌡️ 실시간 날씨 연동**
- OpenWeatherMap API를 사용하여 실제 온도 측정
- 10분마다 자동 업데이트
- API 키 없이도 동작 (fallback 온도 10°C)

## 특징

- ✅ Matter 프로토콜 지원
- ✅ 온도 센서 디바이스 타입 구현
- ✅ **OpenWeatherMap API 실시간 연동**
- ✅ **10분마다 자동 온도 업데이트**
- ✅ 블루투스 지원 노드에 자동 배포 (high-perf)
- ✅ 데이터 영구 저장 (PVC)
- ✅ Host 네트워크 모드 지원 (mDNS 검색용)
- ✅ Node.js 22 및 matter.js 0.15.6 사용
- ✅ ConfigMap 기반 소스 코드 관리 - Docker 빌드 불필요!
- ✅ InitContainer를 통한 자동 의존성 설치

## 전제 조건

- Kubernetes 1.19+
- Helm 3.0+
- 블루투스 기능이 있는 노드 (label: `type: high-perf`)
- PersistentVolume 프로비저너 (기본: local-path)
- (선택) OpenWeatherMap API 키 - [무료 가입](https://openweathermap.org/api)

## 설치

### 1. OpenWeatherMap API 키 발급 (선택)

실제 날씨 데이터를 사용하려면:

1. [OpenWeatherMap](https://openweathermap.org/api)에서 무료 계정 생성
2. API 키 발급

**API 키 없이도 설치 가능**합니다. 이 경우 고정값 10°C를 사용합니다.

### 2. Kubernetes Secret 생성 (선택)

API 키를 발급받았다면, Kubernetes Secret으로 생성합니다:

```bash
# Secret 생성
kubectl create secret generic matter-sensor-openweather \
  --from-literal=api-key="your-api-key-here" \
  -n iot

# Secret 확인
kubectl get secret matter-sensor-openweather -n iot
```

**중요**: Secret은 Git에 올리지 않고 직접 Kubernetes에 생성합니다.

### 3. Helm Chart 설치

```bash
# 기본 설치 (Secret 있으면 자동으로 사용)
helm install matter-sensor ./matter-temperature-sensor -n iot --create-namespace

# 다른 Secret 이름을 사용하는 경우
helm install matter-sensor ./matter-temperature-sensor \
  --set openweathermap.secretName="my-openweather-secret" \
  -n iot --create-namespace
```

## 동작 방식

1. **ConfigMap**: `index.js`와 `package.json` 파일이 ConfigMap으로 저장됩니다
2. **Secret**: OpenWeatherMap API 키는 사용자가 직접 생성한 Secret에서 가져옵니다
3. **InitContainer**: Pod 시작 시 `npm install --production`을 실행하여 의존성을 설치합니다
4. **Main Container**:
   - Node.js 애플리케이션이 실행되어 Matter 온도 센서로 동작
   - OpenWeatherMap API를 통해 현재 온도 조회
   - 10분마다 자동으로 온도 업데이트
   - API 키가 없거나 실패 시 fallback 온도(10°C) 사용

### 온도 업데이트 주기

- **초기 시작**: 즉시 온도 조회
- **정기 업데이트**: 10분(600초)마다 자동 조회
- **위치**: 경도 127.09286670930126, 위도 37.324146498307215

소스 코드나 설정을 변경하려면:

```bash
# ConfigMap 수정 후
helm upgrade matter-sensor ./matter-temperature-sensor -n iot

# API 키 변경 (Secret 업데이트)
kubectl delete secret matter-sensor-openweather -n iot
kubectl create secret generic matter-sensor-openweather \
  --from-literal=api-key="new-api-key" \
  -n iot
kubectl rollout restart deployment/matter-sensor -n iot
```

## 설정

주요 설정 옵션은 `values.yaml`에서 확인할 수 있습니다:

### OpenWeatherMap API 설정

```yaml
openweathermap:
  enabled: true
  secretName: "matter-sensor-openweather"  # Secret 이름
  secretKey: "api-key"  # Secret의 키 이름
```

- `enabled`: OpenWeatherMap 통합 활성화 (true/false)
- `secretName`: API 키가 저장된 Secret 이름
- `secretKey`: Secret 내의 API 키 필드 이름
- Secret이 없으면 fallback 온도(10°C) 사용

### 이미지 설정

```yaml
image:
  repository: node  # 공식 Node.js 이미지 사용
  pullPolicy: IfNotPresent
  tag: "22"  # 전체 이미지 (빌드 도구 포함)
```

### 노드 선택기 (필수)

블루투스 기능이 있는 high-perf 노드에 배포하도록 설정:

```yaml
nodeSelector:
  type: high-perf
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
kubectl logs -l app.kubernetes.io/name=matter-temperature-sensor -c setup-app
```

애플리케이션 로그 확인 (실시간 온도 업데이트 확인):
```bash
kubectl logs -l app.kubernetes.io/name=matter-temperature-sensor -f
```

로그 예시:
```
Starting Matter Temperature Sensor (OpenWeatherMap Integration)...
Location: Latitude 37.324146498307215, Longitude 127.09286670930126
Update interval: 10 minutes
Fetching temperature from OpenWeatherMap...
✓ Weather data received: 12.5°C (clear sky)
  Location: Yongin-si, KR
  Humidity: 45%, Pressure: 1013hPa
✓ Matter Temperature Sensor is running!
✓ Current temperature: 12.5°C

[Update #1] Updating temperature...
✓ Temperature updated successfully: 12.8°C
Next update in 10 minutes
```

### 3. Matter 디바이스 페어링

- Apple Home, Google Home, SmartThings 등 Matter 호환 앱 실행
- 새 디바이스 추가
- Matter 디바이스 검색
- 화면의 지시에 따라 페어링 진행

### 4. 온도 확인

페어링 후 Matter 컨트롤러 앱에서 **실시간 온도**를 확인할 수 있습니다. 온도는 10분마다 자동으로 업데이트됩니다.

### 5. API 키 변경

운영 중에도 API 키를 변경할 수 있습니다:

```bash
# Secret 삭제 후 재생성
kubectl delete secret matter-sensor-openweather -n iot
kubectl create secret generic matter-sensor-openweather \
  --from-literal=api-key="new-api-key" \
  -n iot

# Pod 재시작하여 새 API 키 적용
kubectl rollout restart deployment -l app.kubernetes.io/name=matter-temperature-sensor -n iot
```

### 6. 위치 변경

다른 위치의 온도를 측정하려면 `templates/configmap.yaml`에서 LATITUDE와 LONGITUDE를 수정:

```javascript
const LATITUDE = 37.324146498307215;   // 새 위도
const LONGITUDE = 127.09286670930126;  // 새 경도
```

수정 후:
```bash
helm upgrade matter-sensor ./matter-temperature-sensor
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

- [x] 날씨 API 연동 (실시간 온도 데이터) ✅ **완료**
- [ ] OpenWeatherMap API에서 습도, 기압 데이터도 추가
- [ ] 추가 센서 타입 지원 (습도 센서, 기압 센서 등)
- [ ] 위치 좌표를 환경 변수로 설정 가능하게
- [ ] Prometheus 메트릭 노출

## 문제 해결

### Pod가 시작되지 않음

1. 노드 레이블 확인:
   ```bash
   kubectl get nodes --show-labels | grep high-perf
   ```

2. InitContainer 로그 확인 (npm install 실패 가능성):
   ```bash
   kubectl logs -l app.kubernetes.io/name=matter-temperature-sensor -c setup-app
   ```

### npm install이 실패함

1. 네트워크 연결 확인 (npmjs.com 접근 가능한지)
2. 프록시 설정이 필요한 경우 initContainer에 환경 변수 추가

### OpenWeatherMap API에서 온도를 가져오지 못함

1. API 키가 올바른지 확인:
   ```bash
   kubectl get secret matter-sensor-openweather -o jsonpath='{.data.api-key}' | base64 -d
   ```

2. 로그에서 에러 확인:
   ```bash
   kubectl logs -l app.kubernetes.io/name=matter-temperature-sensor -f
   ```

3. API 키가 없으면 fallback 온도(10°C)를 사용합니다

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
