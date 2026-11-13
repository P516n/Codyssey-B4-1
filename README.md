# Codyssey Linux Server Operation & Automation Mission (Ubuntu 24.04 LTS)

본 프로젝트는 리눅스 다중 사용자 환경에서의 보안/네트워크 설정, 최소 권한 원칙 기반 권한 체계 구축, 서비스 애플리케이션 실행 환경 세팅 및 시스템 관제 자동화 쉘 스크립트(`monitor.sh`)를 구현한 프로젝트입니다.

---

## 📂 프로젝트 구조

```plaintext
├── bin/
│   ├── agent-app-linux-x86     # Linux x86_64 실행 바이너리
│   ├── agent-app-linux-arm64   # Linux ARM64 (Apple Silicon 등) 실행 바이너리
│   ├── monitor.sh              # 시스템 관제 및 로깅 자동화 스크립트
│   ├── report.sh               # 로그 분석 및 통계 리포트 생성 스크립트
│   └── cleanup_archive.sh      # 로그 압축/아카이빙/삭제 정책 스크립트
├── Dockerfile                  # Ubuntu 24.04 LTS systemd 실습 컨테이너 이미지 빌드 파일
├── docker-compose.yml          # 원클릭 컨테이너 실행 Compose 설정 파일
├── setup_environment.sh        # Ubuntu 24.04 LTS 환경 자동 구성 스크립트
└── README.md                   # 프로젝트 가이드 문서
```

---

## 🛠️ 스크립트 상세 설명

### 1. `bin/monitor.sh`
- **위치 및 권한**: `$AGENT_HOME/bin/monitor.sh` (소유자: `agent-dev`, 그룹: `agent-core`, 권한: `750`)
- **Health Check (비정상 시 `exit 1`)**:
  - `agent-app` / `agent_app.py` 프로세스 동작 여부 점검 (`pgrep` 기반)
  - TCP `15034` 포트의 LISTEN 상태 점검 (`ss -tuln` 기반)
- **상태 점검 (경고만 출력)**:
  - UFW / firewalld 방화벽 활성화 상태 점검 (비활성 시 `[WARNING]`, 스크립트 유지)
- **리소스 수집 및 임계치 경고**:
  - CPU 사용률 (`/proc/stat` 기반 정밀 측정, `> 20%` 시 경고)
  - 메모리 사용률 (`free -m` 기반, `> 10%` 시 경고)
  - 루트 파티션 디스크 사용률 (`df -h /` 기반, `> 80%` 시 경고)
- **로그 기록 & 회전 (Rotation)**:
  - 로그 파일: `/var/log/agent-app/monitor.log`
  - 포맷: `[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%`
  - 파일 용량 관리: 10MB 초과 시 최대 10개 파일(`.1` ~ `.10`) 자동 로테이션

### 2. `bin/report.sh`
- `/var/log/agent-app/monitor.log`를 파싱하여 CPU/MEM/DISK의 평균, 최대(발생 시간), 최소(발생 시간) 및 샘플 수 집계
- 특정 시간 구간 필터링 지원:
  ```bash
  ./bin/report.sh -s "2026-02-25 13:58:00" -e "2026-02-25 14:05:00"
  ```

### 3. `bin/cleanup_archive.sh`
- 7일 이상 경과된 로그 파일 압축 후 `/var/log/monitor/agent-app/archive/` 디렉터리로 이동
- 30일 이상 경과된 아카이브(`.gz`) 자동 정리
- 디렉터리 부재, 권한 부족, 대상 파일 0건 등의 예외 상황을 고려하여 안전하게 종료/경고 처리

---

## 🚀 Ubuntu 24.04 LTS 실행 및 검증 가이드

실습 환경에 따라 **[방법 1: Docker / Docker Compose]**(Windows, macOS, Linux 공통 권장) 또는 **[방법 2: 네이티브 Linux VM/머신]** 중 하나를 선택하여 진행합니다.

---

### 방법 1. Docker / Docker Compose 환경 (Windows / macOS / Linux 권장)

본 레포지토리에 포함된 `Dockerfile`과 `docker-compose.yml`을 사용하여 `systemd`, `SSH`, `UFW`, `Cron`이 완벽하게 지원되는 Ubuntu 24.04 환경을 원클릭으로 구동할 수 있습니다.

#### 1) 컨테이너 빌드 및 실행
호스트 터미널(Windows PowerShell, macOS/Linux 터미널)에서 레포지토리 루트로 이동 후 실행합니다:

```bash
# 컨테이너 빌드 및 백그라운드 실행
docker compose up -d --build
```

> **(참고) `docker run` 직접 사용 시:**
> ```bash
> # Windows (PowerShell)
> docker run -d --name ubuntu-lab --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw -v ${PWD}:/workspace -p 20022:20022 -p 15034:15034 ubuntu24-lab
>
> # macOS / Linux
> docker run -d --name ubuntu-lab --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw -v "$(pwd)":/workspace -p 20022:20022 -p 15034:15034 ubuntu24-lab
> ```

#### 2) 컨테이너 셸 접속 (Root 권한)
```bash
docker compose exec ubuntu-lab bash
```

#### 3) 초기 환경 구성 스크립트 실행
컨테이너 내부의 `/workspace`는 호스트 레포지토리와 실시간 동기화되어 있습니다.
```bash
cd /workspace
bash setup_environment.sh
```
*SSH 포트 20022 변경, UFW 방화벽 규칙 적용, 계정/그룹/디렉터리 권한, 바이너리 배포 및 crontab 등록이 자동으로 완료됩니다.*

#### 4) 애플리케이션 실행 (Terminal 1)
```bash
# agent-admin 계정으로 전환
su - agent-admin

# 앱 실행 (Boot Sequence 5단계 [OK] 및 "Agent READY" 확인)
./agent-app
```

#### 5) 모니터링 실행 및 로그 검증 (Terminal 2)
호스트에서 새 터미널을 열고 컨테이너에 접속합니다:
```bash
# 새 터미널에서 agent-admin 계정으로 접속
docker compose exec -u agent-admin ubuntu-lab bash

# 모니터링 스크립트 수동 실행
/home/agent-admin/agent-app/bin/monitor.sh

# cron에 의한 1분 주기 로그 누적 확인
tail -f /var/log/agent-app/monitor.log

# 보너스 통계 리포트 실행
/home/agent-admin/agent-app/bin/report.sh
```

#### 6) 호스트 머신에서 SSH 포트 포워딩 검증
호스트 머신 터미널에서 변경된 포트(20022)로 컨테이너 접속을 테스트합니다:
```bash
# agent-admin 원격 로그인 (비밀번호: agent-admin1234!)
ssh -p 20022 agent-admin@localhost

# root 원격 로그인 차단 확인 (Permission denied 정상 확인)
ssh -p 20022 root@localhost
```

#### 7) 실습 종료 및 컨테이너 정리
```bash
docker compose down
```

---

### 방법 2. 네이티브 Ubuntu 24.04 (VM / 물리 머신) 환경

가상머신(VMware, VirtualBox, UTM) 또는 클라우드 인스턴스(AWS, GCP 등)에서 직접 실습하는 경우입니다.

#### 1단계: 초기 환경 자동 구성
```bash
# 레포지토리 루트에서 root 권한으로 실행
sudo bash setup_environment.sh
```

#### 2단계: 애플리케이션 실행 (Terminal 1)
```bash
# agent-admin 계정으로 전환
su - agent-admin

# 앱 실행 (Boot Sequence 5단계 [OK] 및 "Agent READY" 확인)
./agent-app
```

#### 3단계: 모니터링 스크립트 수동 실행 및 확인 (Terminal 2)
새로운 터미널 창을 열고 `agent-admin` 계정으로 실행:
```bash
su - agent-admin

# monitor.sh 실행
/home/agent-admin/agent-app/bin/monitor.sh

# 누적된 로그 확인
tail -n 10 /var/log/agent-app/monitor.log
```

#### 4단계: cron 자동 실행 확인
`agent-admin` 계정의 crontab에 1분 간격으로 등록되어 있으므로:
```bash
crontab -l

# 1~2분 후 로그 파일 크기 및 새 라인 증가 확인
tail -f /var/log/agent-app/monitor.log
```

#### 5단계: 통계 리포트 실행
```bash
/home/agent-admin/agent-app/bin/report.sh
```

