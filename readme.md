# hello-world-cortex
Cortex는 Prometheus를 위해 horizontally scalable, high available, multi-tenant, long term storage를 제공한다.

- **Horizontally scalable**: Cortex는 클러스터 내부 여러 machine에서 동작할 수 있으며, 단일 시스템에서의 처리량 및 storage의 한계를 뛰어넘을 수 있다. 이를 통해 여러 Prometheus 서버의 metric을 단일 Cortex 클러스터에 저장할 수 있으며 모든 데이터에 대해 "globally aggregated" 쿼리를 실행할 수 있다.
- **Highly available**: 클러스터에서 동작할 때 Cortex는 machine 간에 데이터를 복제할 수 있다. 이를 통해 일부 machine에 장애가 발생할 경우에도 데이터에 대한 공백을 없앨 수 있다.
- **Multi-tenant**: Cortex는 단일 클러스터 내에서 서로 다른 여러 독립적인 Prometheus의 데이터와 쿼리를 격리할 수 있기 때문에 신뢰할 수 없는 제 3자와 동일한 클러스터를 공유할 수 있다.
- **Long term storage**: Cortex는 metric 데이터를 위한 S3, GCS, Microsoft Azure, Cassandra와 같은 long term storage를 지원한다. 이를 통해 단일 시스템에서의 수명보다 오래 데이터를 저장할 수 있다.

Prometheus와 관련된 기초는 [hello-world-prometheus](https://github.com/pyo-counting/hello-world-prometheus) 프로젝트를 참고한다.

## 1. Architecture overview
이 프로젝트는 여러 node로 구성된 Docker Swarm cluster에서 동작한다. 단일 machine에서 배포할 경우 Cortex를 실행하는 방법은 [Getting started with chunks storage](https://cortexmetrics.io/docs/chunks-storage/getting-started-chunks-storage/) 페이지를 참고한다.

### 1.1 Consideration
- Cortex 인스턴스의 개수: Cortex는 cluster 내 여러 node에서 동작하며 실제로 Prometheus로부터 인입되는 시계열을 실시간으로 backend storage에 저장하지 않는다. 대신 ingester가 in-memory에 시계열을 저장하며, 주기적으로 backend storage에 flush한다. 이 때 ingester가 정상적으로 shutdown 되지 않을 경우를 in-memory 내 데이터가 유실될 수도 있기 때문에 Cortex는 WAL(Write-Ahead Log), replication 두 가지 기능을 제공한다. 해당 프로젝트에서는 replication 기능(replication factor=2이므로 적어도 2개의 Cortex ingester가 보장)을 사용한다.
  - replication의 경우 in-memory 데이터 유실을 막기 위해 동일한 데이터를 다른 ingester에도 복제(replication)한다. 이는 Cortex 설정 파일에 설정 가능(ingester.lifecycler.ring.kvstore.replication_factor)하며, Cortex startup 시 적절한 Cortex ingester 개수가 없으면 오류가 발생할 수 있다.
  - WAL의 경우 ingester가 데이터를 in-memory가 아닌 노드의 물리 저장 장치에 저장하기 때문에 ingester가 비정상 종료 시에도 데이터가 유실되지 않는다. 대신, 새로운 ingester가 해당 데이터를 사용할 수 있도록 마운트 될 수 있도록 보장해야 한다.
- backend storage: 현재 Cortex에서 지원하는 storage는 chunks storage(deprecated), blcoks storage가 있다. 지원하는 blocks storage의 경우 모두 cloud 환경이기 때문에 이러한 환경이 제한된 경우에는 chunks storage를 사용해야 한다. 이 프로젝트에서도 기본적으로 chunks storage인 Cassandra를 사용한다.


## 2. Configuration
정상 설치 및 실행하기 위해 사용자 환경에 따라 기본적으로 변경되어야 하는 설정은 다음과 같다.

- Prometheus:
  - ./docker-stack.yml
    - services.prometheus.deploy.replicas: service task 배포 개수 설정
  - service task 배포 대상 swarm node 지정
    - swarm node label 설정 필요(monitoring_stack.prometheus.deployable=true). label 설정 node의 개수 >= service task 배포 개수
  - ./prometheus/sd_configs/file/*.yml
    - scrape target 추가를 위한 endpoint(IP 및 PORT 정보) 설정 필요
  - ./prometheus/prometheus.yml
    - scrape_configs.remote_write.header.X-Scope-OrgID: tenant ID 설정 필요(grafana 설정 참고)
    - global.external_labels.cluster: Prometheus HA cluster label 설정 필요
- Grafana:
  - service task 배포 대상 swarm node 지정
    - swarm node label 설정 필요(monitoring_stack.grafana.deployable=true)
  - ./grafana/cert/*
    - HTTPS 인증서 및 키 파일 추가 필요
  - ./grafana/grafana.ini
    - server.domain: 도메인 설정 필요
    - server.cert_file, server.cert_key: 인증서 관련 파일 경로 설정 필요
    - security.admin_password: Grafana 관리자 계정 비밀번호 설정 필요
  - ./grafana/provisioning/datasources/datasources.yml
    - datasources.secureJsonData: tenant ID 설정 필요
  - ./docker-stack.yml
    - configs.grafana_cert.file, configs.grafana_cert_key.file: 인증서 관련 파일 경로 설정 필요
    - services.grafana.configs: 인증서 관련 파일 경로 설정 필요
- Cortex:
  - ./docker-stack.yml
    - services.cortex.deploy.replicas: service task 배포 개수 설정
  - service task 배포 대상 swarm node 지정
    - swarm node label 설정 필요(monitoring_stack.cortex.deployable=true). label 설정 node의 개수 >= service task 배포 개수
  - ./cortex/microservices-mode-config.yml
    - ingester.lifecycler.ring.kvstore.replication_factor: >= service task 배포 개수
- Cassandra:
  - service task 배포 대상 swarm node 지정
    - swarm node label 설정 필요(monitoring_stack.cassandra.deployable=true)

## 3. Installation
Cortex는 여러 클러스터링 환경에서 운영되며, 이를 위해 Docker Swarm 환경에서 배포한다.

### 3.1 Execution environment info
해당 프로젝트는 아래 환경에서 정상 동작했음을 테스트했다.
- OS: CentOS Linux release 7.8.2003 (Core)
- Kernel version: 3.10.0-1127.18.2.el7.x86_64 #1 SMP Sun Jul 26 15:27:06 UTC 2020
- Docker version: 20.10.5

### 3.2 Software Version Info
- Prometheus: [v2.32.0](https://github.com/prometheus/prometheus/releases/tag/v2.32.0)
- Cadvisor: [v0.37.5](https://github.com/google/cadvisor/releases/tag/v0.37.5)
- Node-exporter: [v1.3.1](https://github.com/prometheus/node_exporter/releases/tag/v1.3.1)
- Grafana: [8.3.3](https://github.com/grafana/grafana/releases/tag/v8.3.3)
- SpringBoot (maven dependency):
    - spring-boot-starter-parent: [2.3.1.RELEASE](https://github.com/spring-projects/spring-boot/releases/tag/v2.3.1.RELEASE)
    - micrometer-registry-prometheus: [1.8.2](https://github.com/micrometer-metrics/micrometer/releases/tag/v1.8.2)
- Cortex:1.11.0
- Consul: 1.10.4
- Cassandra: 3.11.11
    
### 3.3 Step by step
1. project clone하기
   ```bash
   git clone https://github.com/pyo-counting/hello-world-cortex.git
   ```
2. 프로젝트 디렉토리로 이동
   ```bash
   cd hello-world-cortex
   ```
3. docker service 배포 및 확인
   ```bash
   docker stack deploy -c docker-stack.yml monitoring_stack
   docker stack ps monitoring_stack
   ```
3. docker service down
   ```bash
   # service down
   docker stack rm monitoring_stack
   # remove volume
   docker volume rm $(docker volume ls --filter name=monitoring_stack --format {{.Name}})
   ```

## 4. Documentation
- [Prometheus](https://prometheus.io/docs/introduction/overview/)
- [Cadvisor](https://github.com/google/cadvisor)
- [Node-exporter](https://github.com/prometheus/node_exporter)
- [Grafana](https://grafana.com/docs/grafana/latest/)
- [SpringBoot](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html)
- [Cortex](https://cortexmetrics.io/docs/)
- [Consul](https://www.consul.io/docs)
- [Cassandra](https://cassandra.apache.org/doc/latest/)

## 5. Etc
- Architecture overview은 [draw.io](https://www.draw.io)를 통해 작성
- [hello-world-prometheus](https://github.com/pyo-counting/hello-world-prometheus) 프로젝트의 Alertmanager는 Grafana의 알람 기능으로 대체할 예정이다.