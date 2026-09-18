# AWS 인프라 실습 절차 정리

`aws.sh`와 터미널(zsh) 히스토리에 남아 있는 AWS CLI 작업 흐름을 정리한 문서입니다.
`Course=infra-training` 태그가 붙은 실습성 리소스이며, 이 리포지토리(`spring-test-ci-cd`)의
애플리케이션 코드와는 직접적인 관련이 없습니다.

## 1. `aws.sh`의 역할

`aws.sh`는 리소스를 생성하지 않고, 이후 명령에서 재사용할 **환경변수만 정의**합니다.

1. `STUDENT_ID`, `AWS_PROFILE`, `AWS_REGION`(서울, `ap-northeast-2`), `AWS_PAGER` 지정
2. 리소스 이름 규칙 정의: `MY_KEY_NAME`, `MY_SG_NAME`, `MY_INSTANCE_NAME`
3. 기본 VPC ID(`VPC_ID`) 조회 → 해당 VPC 내 보안그룹 ID(`MY_SG_ID`) 조회
4. 로컬 공인 IP(`MY_IP`) 조회 (`https://checkip.amazonaws.com`)
5. Ubuntu 26.04 ARM64 최신 AMI ID(`BASE_AMI_ID`)를 SSM 파라미터에서 조회
6. 이름 태그로 기존 인스턴스 ID(`INSTANCE_ID`) 조회
7. 해당 인스턴스의 퍼블릭 IP(`PUBLIC_IP`) 조회

## 2. 터미널에서 실제로 수행된 절차

### ① 인증
- `aws configure sso --profile student09`
- `aws sso login --profile student09`
- `aws sts get-caller-identity --profile student09`
- `export AWS_PROFILE="student09"`

### ② 네트워크 / 보안그룹 준비
- `aws ec2 describe-availability-zones`, `describe-vpcs` (기본 VPC 조회)
- `aws ec2 create-security-group` (`student09-web-sg` 생성, 없을 때만 생성하는 조건 분기로 반복 실행)
- `aws ec2 authorize-security-group-ingress` : 22번(내 IP만), 80번, 8080번 포트 인바운드 허용

### ③ 키 페어 및 EC2 인스턴스
- `aws ec2 create-key-pair` → `student09-key.pem` 생성 후 `chmod 400`
- `aws ssm get-parameter`로 최신 Ubuntu AMI ID 조회
- `aws ec2 run-instances`로 인스턴스 생성 → `wait instance-running` / `wait instance-status-ok`
- `aws ec2 describe-instances`로 퍼블릭 IP 조회 → `ssh -i student09-key.pem ubuntu@$PUBLIC_IP` 접속
- `stop-instances` / `start-instances`를 여러 차례 반복하며 실습 (키 페어 삭제 후 재발급도 여러 번 발생)
- 다른 실습 디렉터리(`260914_aws-cli`)에 있던 `.pem` 파일을 복사해 재사용한 이력도 있음

### ④ 애플리케이션 서버 스케일아웃 준비
- 실행 중인 인스턴스를 기반으로 `aws ec2 create-image`로 커스텀 AMI(`student09-app-image`) 생성 → `wait image-available`
- 해당 AMI로 두 번째 인스턴스(`INSTANCE_ID_2`) 추가 생성 및 SSH 접속 확인

### ⑤ 데이터 계층(RDS/ElastiCache) 및 스토리지
- `student09-data-sg` 보안그룹 생성 → EC2 보안그룹으로부터 3306(MySQL), 6379(Redis) 인바운드 허용
- 서브넷 목록(`SUBNET_IDS`) 조회 → RDS(`student09-mysql-db`) / ElastiCache(`student09-redis`)용 서브넷 그룹 구성
- `aws s3 mb`로 `student09-app-assets-<계정ID>` 버킷 생성 및 태깅

### ⑥ 로드밸런서(ALB) 구성
- `student09-alb-sg` 보안그룹 생성 (HTTP 공개 진입점)
- `aws elbv2 create-target-group` (`student09-app-tg`) 생성
- `aws elbv2 register-targets`로 두 EC2 인스턴스를 타겟그룹에 등록
- `aws elbv2 create-load-balancer` (`student09-app-alb`, internet-facing) 생성
- `aws elbv2 create-listener`로 80번 포트를 타겟그룹으로 포워딩
- `aws elbv2 describe-load-balancers`로 ALB DNS 조회 → `wait target-in-service`
- `curl http://$ALB_DNS/`를 반복 실행해 로드밸런싱 동작 확인

## 3. 참고 사항

- `student09-key.pem` 파일은 저장소 루트에 존재하지만 `.gitignore`의 `*.pem` 규칙에 의해
  git 추적에서 제외되어 있습니다.
- `aws.sh`는 애플리케이션 코드가 아닌 개인 실습용 스크립트이므로, 리포지토리에 커밋할지 여부를
  별도로 결정할 필요가 있습니다.
