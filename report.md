# 요구사항 수행 내역서 (System Engineering & Automation Report)

- **실습 일자**: 2026-11-16
- **실습 환경**: Ubuntu 24.04 LTS

---

## 1. 필수 증거 자료 체크리스트

| 번호 | 요구사항 항목 | 만족 여부 | 증거 자료 위치 |
| :---: | :--- | :---: | :--- |
| **1** | SSH 포트 변경(20022) 및 Root 원격 접속 차단 | [x] 완료 | [섹션 2-1](#2-1-ssh-보안-설정) |
| **2** | 방화벽(UFW) 활성화 및 포트(20022/tcp, 15034/tcp) 허용 | [x] 완료 | [섹션 2-2](#2-2-방화벽-설정-ufw) |
| **3** | 역할 기반 계정/그룹(agent-admin/dev/test, agent-common/core) 구성 | [x] 완료 | [섹션 2-3](#2-3-계정-및-그룹-체계-구성) |
| **4** | 디렉토리 구조 및 접근 권한(SetGID / ACL) 구성 | [x] 완료 | [섹션 2-4](#2-4-디렉토리-구조-및-권한-설정) |
| **5** | 애플리케이션 Boot Sequence 5단계 [OK] 및 "Agent READY" 확인 | [x] 완료 | [섹션 2-5](#2-5-애플리케이션-실행-및-부팅-검증) |
| **6** | `monitor.sh` 실행 및 상태/자원/경고 점검 확인 | [x] 완료 | [섹션 2-6](#2-6-시스템-관제-스크립트-monitorsh-실행) |
| **7** | `/var/log/agent-app/monitor.log` 표준 포맷 누적 기록 확인 | [x] 완료 | [섹션 2-7](#2-7-로그-누적-기록-확인) |
| **8** | crontab 매분 자동 실행 및 로그 라인 증가 확인 | [x] 완료 | [섹션 2-8](#2-8-crontab-매분-자동-실행-검증) |
| **B1**| [보너스 1] `report.sh` 요약 리포트 자동 생성 | [x] 완료 | [섹션 3-1](#3-1-보너스-1-reportsh-요약-리포트) |
| **B2**| [보너스 2] `cleanup_archive.sh` 시간 기반 로그 보존 정책 | [x] 완료 | [섹션 3-2](#3-2-보너스-2-시간-기반-로그-보존-정책) |

---

## 2. 항목별 수행 내역 및 증빙

### 2-1. SSH 보안 설정
- **설정 내용**:
  - 포트: `22` -> `20022` 변경
  - Root 원격 로그인: `PermitRootLogin no` 설정
- **수행 명령어**:
  ```bash
  # 설정 파일 확인
  cat /etc/ssh/sshd_config.d/agent-security.conf
  # 또는
  grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null

  # 포트 LISTEN 상태 확인
  ss -tulnp | grep ssh
  ```
- **실행 결과 증빙**:
  ```bash
  agent-admin@95b33f6705aa:~$ cat /etc/ssh/sshd_config.d/agent-security.conf
  Port 20022
  PermitRootLogin no

  agent-admin@95b33f6705aa:~$ ss -tulnp | grep 20022
  tcp   LISTEN 0      4096         0.0.0.0:20022      0.0.0.0:*
  tcp   LISTEN 0      4096            [::]:20022         [::]:*
  ```

---

### 2-2. 방화벽 설정 (UFW)
- **설정 내용**:
  - UFW 활성화, 기본 인바운드 차단(deny), 기본 아웃바운드 허용(allow)
  - `20022/tcp` (SSH), `15034/tcp` (Agent App) 인바운드 허용
- **수행 명령어**:
  ```bash
  sudo ufw status verbose
  ```
- **실행 결과 증빙**:
  ```bash
  root@95b33f6705aa:/workspace# ufw status verbose
  Status: active
  Logging: on (low)
  Default: deny (incoming), allow (outgoing), deny (routed)
  New profiles: skip

  To                         Action      From
  --                         ------      ----
  20022/tcp                  ALLOW IN    Anywhere                   # SSH Custom Port
  15034/tcp                  ALLOW IN    Anywhere                   # Agent App Port
  20022/tcp (v6)             ALLOW IN    Anywhere (v6)              # SSH Custom Port
  15034/tcp (v6)             ALLOW IN    Anywhere (v6)              # Agent App Port
  ```

---

### 2-3. 계정 및 그룹 체계 구성
- **설정 내용**:
  - 그룹: `agent-common` (공통), `agent-core` (핵심 운영/개발)
  - 계정별 소속:
    - `agent-admin`: `agent-common`, `agent-core`
    - `agent-dev`: `agent-common`, `agent-core`
    - `agent-test`: `agent-common`
- **수행 명령어**:
  ```bash
  id agent-admin
  id agent-dev
  id agent-test
  ```
- **실행 결과 증빙**:
  ```bash
  agent-admin@95b33f6705aa:~$ id agent-admin
  uid=1001(agent-admin) gid=1003(agent-admin) groups=1003(agent-admin),1001(agent-common),1002(agent-core)
  agent-admin@95b33f6705aa:~$ id agent-dev
  uid=1002(agent-dev) gid=1004(agent-dev) groups=1004(agent-dev),1001(agent-common),1002(agent-core)
  agent-admin@95b33f6705aa:~$ id agent-test
  uid=1003(agent-test) gid=1005(agent-test) groups=1005(agent-test),1001(agent-common)
  ```

---

### 2-4. 디렉토리 구조 및 권한 설정
- **설정 내용**:
  - `$AGENT_HOME/upload_files`: 그룹 `agent-common`, 권한 `2775 (rwxrwsr-x)`
  - `$AGENT_HOME/api_keys`: 그룹 `agent-core`, 권한 `2770 (rwxrws---)`
  - `/var/log/agent-app`: 그룹 `agent-core`, 권한 `2770 (rwxrws---)`
  - `$AGENT_HOME/bin/monitor.sh`: 소유자 `agent-dev`, 그룹 `agent-core`, 권한 `750 (rwxr-x---)`
- **수행 명령어**:
  ```bash
  ls -ld /home/agent-admin/agent-app/upload_files
  ls -ld /home/agent-admin/agent-app/api_keys
  ls -ld /var/log/agent-app
  ls -l /home/agent-admin/agent-app/bin/monitor.sh
  cat /home/agent-admin/agent-app/api_keys/t_secret.key
  ```
- **실행 결과 증빙**:
  ```plaintext
  agent-admin@95b33f6705aa:~$ ls -ld /home/agent-admin/agent-app/upload_files
  drwxrwsr-x 2 agent-admin agent-common 4096 Nov 16 04:44 /home/agent-admin/agent-app/upload_files
  agent-admin@95b33f6705aa:~$ ls -ld /home/agent-admin/agent-app/api_keys
  drwxrws--- 2 agent-admin agent-core 4096 Nov 16 04:44 /home/agent-admin/agent-app/api_keys
  agent-admin@95b33f6705aa:~$ ls -ld /var/log/agent-app
  drwxrws--- 2 agent-admin agent-core 4096 Nov 16 04:45 /var/log/agent-app
  agent-admin@95b33f6705aa:~$ ls -l /home/agent-admin/agent-app/bin/monitor.sh
  -rwxr-x--- 1 agent-dev agent-core 9242 Nov 16 04:44 /home/agent-admin/agent-app/bin/monitor.sh
  agent-admin@95b33f6705aa:~$ cat /home/agent-admin/agent-app/api_keys/t_secret.key
  agent_api_key_test
  ```

---

### 2-5. 애플리케이션 실행 및 부팅 검증
- **설정 내용**:
  - 환경변수 로드 확인 (`AGENT_HOME`, `AGENT_PORT`, `AGENT_KEY_PATH` 등)
  - 일반 계정(`agent-admin`)으로 앱 실행
  - Boot Sequence 5단계 [OK] 통과 및 `Agent READY` 확인
  - 15034 포트 LISTEN 상태 확인
- **수행 명령어**:
  ```bash
  # 계정 전환 및 실행
  su - agent-admin
  env | grep AGENT_
  ./agent-app
  
  # 다른 터미널에서 포트 리슨 확인
  ss -tuln | grep 15034
  ```
- **실행 결과 증빙**:
  ```bash
  root@95b33f6705aa:/workspace# su - agent-admin
  agent-admin@95b33f6705aa:~$ env | grep AGENT_
  AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
  AGENT_PORT=15034
  AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
  AGENT_HOME=/home/agent-admin/agent-app
  AGENT_LOG_DIR=/var/log/agent-app
  agent-admin@95b33f6705aa:~$ agent-app
  >>> Starting Agent Boot Sequence...
  [1/5] Checking User Account               [OK]
    ... Running as service user 'agent-admin' (uid=1001)
  [2/5] Verifying Environment Variables     [OK]
    ... All required Envs correct
  [3/5] Checking Required Files             [OK]
    ... Verified 'secret.key' with correct key string.
  [4/5] Checking Port Availability          [OK]
    ... Port 15034 is available.
  [5/5] Verifying Log Permission            [OK]
    ... Log directory is writable: /var/log/agent-app
  ------------------------------------------------------------
  All Boot Checks Passed!
  Agent READY
  2026-11-16 03:42:18,741 [INFO] [SafetyGuard] Process priority lowered (nice=10).
  2026-11-16 03:42:18,742 [INFO] Agent listening at port 15034
  2026-11-16 03:42:18,742 [INFO] === Agent Worker Started ===
  2026-11-16 03:42:18,742 [INFO]    > Cycle: 0 -> 256MB/Lv10 -> 0
  2026-11-16 03:42:18,742 [INFO] --- Step Info: Mode=UP, CPU Lv=1, Mem=0MB ---
  2026-11-16 03:42:18,773 [INFO] [Memory] Increasing... (+25 MB) Total: 25 MB
  2026-11-16 03:42:18,773 [INFO] [CPU] Occupy core for 1s (Level 1)
  2026-11-16 03:42:20,779 [INFO] --- Step Info: Mode=UP, CPU Lv=2, Mem=25MB ---
  2026-11-16 03:42:20,811 [INFO] [Memory] Increasing... (+25 MB) Total: 50 MB
  2026-11-16 03:42:20,811 [INFO] [CPU] Occupy core for 2s (Level 2)
  2026-11-16 03:42:23,817 [INFO] --- Step Info: Mode=UP, CPU Lv=3, Mem=50MB ---
  2026-11-16 03:42:23,849 [INFO] [Memory] Increasing... (+25 MB) Total: 75 MB
  2026-11-16 03:42:23,849 [INFO] [CPU] Occupy core for 3s (Level 3)
  2026-11-16 03:42:27,856 [INFO] --- Step Info: Mode=UP, CPU Lv=4, Mem=75MB ---
  2026-11-16 03:42:27,886 [INFO] [Memory] Increasing... (+25 MB) Total: 100 MB
  2026-11-16 03:42:27,887 [INFO] [CPU] Occupy core for 4s (Level 4)
  2026-11-16 03:42:32,893 [INFO] --- Step Info: Mode=UP, CPU Lv=5, Mem=100MB ---
  2026-11-16 03:42:32,927 [INFO] [Memory] Increasing... (+25 MB) Total: 125 MB
  2026-11-16 03:42:32,928 [INFO] [CPU] Occupy core for 5s (Level 5)
  2026-11-16 03:42:38,933 [INFO] --- Step Info: Mode=UP, CPU Lv=6, Mem=125MB ---
  2026-11-16 03:42:38,970 [INFO] [Memory] Increasing... (+25 MB) Total: 150 MB
  ```
  ```bash
  agent-admin@95b33f6705aa:~$ ss -tuln | grep 15034
  tcp   LISTEN 0      1            0.0.0.0:15034      0.0.0.0:*
  ```

---

### 2-6. 시스템 관제 스크립트 (`monitor.sh`) 실행
- **점검 내용**:
  - 프로세스 정상 동작 확인 (PID 추출)
  - 포트 15034 정상 확인
  - 리소스 수집 (CPU, MEM, DISK) 및 임계값 점검
  - 비정상 상태(앱 종료 시) `exit 1` 반환 검증
- **수행 명령어**:
  ```bash
  # agent-admin 계정으로 monitor.sh 수동 실행
  /home/agent-admin/agent-app/bin/monitor.sh
  echo "Exit Code: $?"
  ```
- **실행 결과 증빙**:
  ```bash
  agent-admin@95b33f6705aa:/workspace$ /home/agent-admin/agent-app/bin/monitor.sh
  ====== SYSTEM MONITOR RESULT ======

  [HEALTH CHECK]
  Checking process 'agent[-_]app'... [OK] (PID: 426)
  Checking port 15034... [OK]

  [RESOURCE MONITORING]
  CPU Usage : 77.6%
  MEM Usage : 14.0%
  DISK Used  : 1%

  [WARNING] CPU threshold exceeded (77.6% > 20.0%)
  [WARNING] Memory threshold exceeded (14.0% > 10.0%)

  ====== STATISTICS REPORT ======
  [CPU]
  Average : 77.6%
  Maximum : 77.6% at 2026-11-16 03:42:47
  Minimum : 77.6% at 2026-11-16 03:42:47
  [Memory]
  Average : 14.0%
  Maximum : 14.0% at 2026-11-16 03:42:47
  Minimum : 14.0% at 2026-11-16 03:42:47
  [Samples]
  Data Points: 1 samples

  [INFO] Log appended: /var/log/agent-app/monitor.log
  agent-admin@95b33f6705aa:/workspace$ tail -f /var/log/agent-app/monitor.log
  [2026-11-16 03:42:47] PID:426 CPU:77.6% MEM:14.0% DISK_USED:1%
  [2026-11-16 03:43:01] PID:426 CPU:77.7% MEM:14.8% DISK_USED:1%
  [2026-11-16 03:44:02] PID:426 CPU:77.5% MEM:12.3% DISK_USED:1%
  ```

---

### 2-7. 로그 누적 기록 확인
- **점검 내용**:
  - `/var/log/agent-app/monitor.log`에 표준 형식(`[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%`)으로 누적되는지 확인
- **수행 명령어**:
  ```bash
  tail -n 5 /var/log/agent-app/monitor.log
  ```
- **실행 결과 증빙**:
  ```bash
  agent-admin@95b33f6705aa:/workspace$ tail -f /var/log/agent-app/monitor.log
  [2026-11-16 03:23:23] PID:426 CPU:74.7% MEM:12.9% DISK_USED:1%
  [2026-11-16 03:24:01] PID:426 CPU:75.1% MEM:15.6% DISK_USED:1%
  [2026-11-16 03:25:02] PID:426 CPU:74.8% MEM:13.0% DISK_USED:1%
  [2026-11-16 03:26:02] PID:426 CPU:75.3% MEM:15.6% DISK_USED:1%
  [2026-11-16 03:27:01] PID:426 CPU:75.4% MEM:14.3% DISK_USED:1%
  [2026-11-16 03:28:02] PID:426 CPU:75.6% MEM:14.3% DISK_USED:1%
  [2026-11-16 03:29:01] PID:426 CPU:75.7% MEM:14.9% DISK_USED:1%
  [2026-11-16 03:30:02] PID:426 CPU:75.1% MEM:12.8% DISK_USED:1%
  [2026-11-16 03:31:02] PID:426 CPU:75.8% MEM:15.6% DISK_USED:1%
  ```

---

### 2-8. crontab 매분 자동 실행 검증
- **점검 내용**:
  - `agent-admin` 계정 crontab 등록 내역 확인
  - 1~2분 대기 후 로그 라인이 자동으로 증가하는지 확인
- **수행 명령어**:
  ```bash
  # crontab 등록 내용 확인
  crontab -u agent-admin -l

  # 로그 파일 타임스탬프 및 라인 수 변화 확인
  wc -l /var/log/agent-app/monitor.log
  sleep 65
  wc -l /var/log/agent-app/monitor.log
  ```
- **실행 결과 증빙**:
  ```bash
  agent-admin@95b33f6705aa:~$ crontab -u agent-admin -l

  * * * * * /home/agent-admin/agent-app/bin/monitor.sh > /dev/null 2>&1
  ```
  ```bash
  agent-admin@95b33f6705aa:~$ wc -l /var/log/agent-app/monitor.log
  29 /var/log/agent-app/monitor.log
  
  (1분 대기 후)
  agent-admin@95b33f6705aa:~$ wc -l /var/log/agent-app/monitor.log
  30 /var/log/agent-app/monitor.log
  ```

---

## 3. 보너스 과제 수행 내역 (선택)

### 3-1. [보너스 1] `report.sh` 요약 리포트
- **수행 내용**: `monitor.log`를 파싱하여 CPU/MEM/DISK 통계 집계 및 기간 필터링 기능 검증
- **수행 명령어**:
  ```bash
  # 전체 통계
  /home/agent-admin/agent-app/bin/report.sh

  # 특정 시간 구간 필터링 통계
  /home/agent-admin/agent-app/bin/report.sh -s "2026-XX-XX 14:00:00" -e "2026-XX-XX 14:30:00"
  ```
- **실행 결과 증빙**:
  ```bash
  agent-admin@95b33f6705aa:/workspace$ /home/agent-admin/agent-app/bin/report.sh
    ====== STATISTICS REPORT ======
      [CPU]
        Average : 77.6%
        Maximum : 77.7% at 2026-11-16 03:43:01
        Minimum : 77.5% at 2026-11-16 03:44:02
      [Memory]
        Average : 13.7%
        Maximum : 14.8% at 2026-11-16 03:43:01
        Minimum : 12.3% at 2026-11-16 03:44:02
      [Disk (Root)]
        Average : 1.0%
        Maximum : 1% at 2026-11-16 03:42:47
        Minimum : 1% at 2026-11-16 03:42:47
      [Samples]
        Data Points: 3 samples

  agent-admin@95b33f6705aa:/workspace$ /home/agent-admin/agent-app/bin/report.sh -s "2026-11-16 04:00:00" -e "2026-11-16 05:00:00"
    ====== STATISTICS REPORT ======
      [CPU]
        Average : 40.2%
        Maximum : 43.3% at 2026-11-16 04:59:02
        Minimum : 36.8% at 2026-11-16 04:46:01
      [Memory]
        Average : 14.6%
        Maximum : 16.6% at 2026-11-16 04:47:02
        Minimum : 12.5% at 2026-11-16 04:58:02
      [Disk (Root)]
        Average : 1.0%
        Maximum : 1% at 2026-11-16 04:45:02
        Minimum : 1% at 2026-11-16 04:45:02
      [Samples]
        Data Points: 16 samples
  ```

---

### 3-2. [보너스 2] 시간 기반 로그 보존 정책
- **수행 내용**:
  - 7일 경과 로그 압축 및 `/var/log/monitor/agent-app/archive/` 이동
  - 30일 경과 압축 아카이브(`.gz`) 삭제
  - 예외 상황(디렉토리 미존재, 권한 등)에 대한 안전한 방어 로직 검증
- **수행 명령어**:
  ```bash
  /home/agent-admin/agent-app/bin/cleanup_archive.sh
  ls -la /var/log/monitor/agent-app/archive/
  ```
- **실행 결과 증빙**:
  ```bash
  /home/agent-admin/agent-app/bin/cleanup_archive.sh
  [2026-11-16 05:26:02] Starting log archive & retention task...
  [STEP 1] Checking for logs older than 7 days in /var/log/agent-app...
  [INFO] No log files older than 7 days found to compress.
  [STEP 2] Checking for archives older than 30 days in /var/log/monitor/agent-app/archive...
  [INFO] No archive files older than 30 days found to delete.
  [2026-11-16 05:26:02] Log retention task completed successfully.
  ```
  ```bash
  agent-admin@95b33f6705aa:~$ ls -la /var/log/monitor/agent-app/archive/
  total 8
  drwxrws--- 2 agent-admin agent-core 4096 Nov 16 05:23 .
  drwxrws--- 3 agent-admin agent-core 4096 Nov 16 05:23 ..
  ```