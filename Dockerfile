# Dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. 필수 패키지 설치 (systemd, SSH, UFW, Cron, 네트워크/프로세스 도구)
RUN apt-get update && apt-get install -y \
    systemd \
    systemd-sysv \
    sudo \
    openssh-server \
    ufw \
    iptables \
    cron \
    iproute2 \
    procps \
    curl \
    vim \
    nano \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. SSH 실행에 필요한 디렉터리 생성
RUN mkdir -p /var/run/sshd

# 3. systemd 기본 시그널 설정
STOPSIGNAL SIGRTMIN+3

# 작업 디렉터리
WORKDIR /workspace

# systemd init 프로세스로 시작
CMD ["/sbin/init"]