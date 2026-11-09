# GitLab → Synology NAS 배포

## 배포 구성

- 서비스: K-AGORA / Compose 프로젝트: `k-agora`
- 포트: **8086 후보**. 모니터링의 연결 그림만으로 빈 포트라고 확정하지 않습니다. 최초 배포의 preflight가 실제 bind 검사 후 충돌 시 중지합니다.
- NAS Docker host 네트워크, 빌드도 host 네트워크. 포트 매핑·새 bridge 네트워크·cpus 옵션은 사용하지 않습니다.
- Python 3.12 표준 라이브러리 앱. 비root UID/GID `10001:10001`, 읽기 전용 컨테이너 파일시스템, 상태 확인.
- DB: 컨테이너의 `/data/k-agora.sqlite3` → **NAS Docker 영구 볼륨 `k-agora-data`**.
- 첫 운영 DB는 **0건**입니다. 기본 실제 37건이나 예시 8건을 자동 등록하지 않습니다. 현재 PC의 전체 JSON 백업을 웹에서 가져오세요.
- 재배포 전 SQLite online backup을 `/data/backups`에 만들고 정상 상태를 확인합니다.

영구 볼륨은 소스 폴더·컨테이너 교체와 독립적입니다. 시놀로지 Docker 저장소에 보관되며 `/volume1/docker/apps/...` bind 폴더를 별도로 만들거나 UID 권한을 수동 지정할 필요가 없습니다. 운영 볼륨에 `docker compose down -v`나 `docker volume rm`을 사용하지 마세요. NAS 자체 장애에 대비한 외부 백업은 별도로 보관하세요.

## 사전 조건

첨부 EDUMATE 가이드의 기존 그룹 Runner를 사용합니다. Runner가 **같은 NAS Docker 소켓**을 마운트하고 host 네트워크로 실행되는 환경을 전제로 합니다. 파이프라인은 같은 NAS Docker에 검증 이미지를 커밋 SHA로 보관합니다. 다른 서버의 Runner를 섞지 마세요. 필요하면 NAS 관리자가 모든 잡에 같은 Runner 태그를 지정합니다.

Runner 이미지에 Docker Compose v2 명령이 필요합니다. 배포는 `main` 파이프라인의 수동 잡입니다. 브랜치/MR에서는 운영 변수를 쓰거나 배포하지 않습니다. K-AGORA는 사용자별 열람 로그인이 없는 내부 시제품이므로 접근은 사내/Tailscale 네트워크로 제한합니다.

## 1. 데이터 백업

PC에서 현재 DB로 실행한 웹의 **안건 등록·관리 → 전체 JSON 내보내기**를 사용합니다. 실제 DB 파일과 `.env`는 Git으로 옮기지 않습니다.

## 2. 코드와 배포 파일 업로드

새 GitHub 저장소를 별도 폴더로 복제합니다. 기존 K-AGORA 폴더는 유지합니다.

```powershell
git clone https://github.com/wtg1021/K-AGORA-NAS.git
cd K-AGORA-NAS
git remote add gitlab <GitLab 화면에서 복사한 SSH 주소>
git switch -c feature/nas-deploy
git -c core.sshCommand="ssh -i '$env:USERPROFILE/.ssh/id_ed25519' -o IdentitiesOnly=yes" push -u gitlab feature/nas-deploy
```

GitLab 주소에는 프로젝트 화면의 SSH 복제 주소를 넣습니다. 이 저장소는 기존 K-AGORA의 Git 이력을 유지하므로 사용자가 이미 올린 GitLab 프로젝트에 feature 브랜치를 push하고 MR로 반영할 수 있습니다. 강제 push로 기존 main을 바꾸지 않습니다.

GitLab에서 이 브랜치의 MR을 만들고 main을 대상으로 선택합니다. 테스트/검사를 통과한 후 리뷰와 머지를 진행합니다. 기존에 같은 브랜치가 있으면 새 브랜치 이름을 사용합니다.

## 3. GitLab 운영 변수

프로젝트 **Settings → CI/CD → Variables → Add variable**:

- Type: **File**
- Key: **PROD_ENV_FILE**
- Value: `.env.example`의 내용을 복사한 뒤 `ADMIN_TOKEN=` 오른쪽에 직접 정한 충분히 긴 임의 관리자 키를 입력합니다.
- **Protected** 체크. `main`을 보호 브랜치로 설정합니다.
- 여러 줄 File 변수는 Masked 제약에 걸릴 수 있습니다. 실제 비밀값은 GitLab 변수에만 입력하고 채팅이나 커밋에 넣지 않습니다.

`PORT=8086`은 첫 배포의 충돌 검사에서 확인됩니다. 충돌하면 사용 가능한 포트로 변경합니다. Compose는 DB 위치 `/data/k-agora.sqlite3`와 자동 시드 비활성화를 고정합니다. 운영 명령에 **`--real`을 붙이지 않습니다**. 이 옵션은 로컬 전용 DB 경로를 강제하므로 NAS 영구 볼륨 설정과 맞지 않습니다.

## 4. 검사와 배포

1. scan: Gitleaks로 현재 소스의 비밀정보 검사.
2. verify: Docker 이미지 빌드, 비root 확인, Python 테스트, JS 텍스트 테스트, Trivy CRITICAL 취약점 차단.
3. MR 승인 후 main에 머지합니다.
4. **Build → Pipelines → main 파이프라인 → deploy-nas ▶**를 누릅니다.
5. preflight가 영구 볼륨 쓰기 권한·포트를 검사하고 기존 DB가 있으면 백업합니다.
6. 컨테이너를 교체하고 healthcheck가 healthy이면 성공합니다.

이미지 취약점 검사가 실패하면 로그를 확인하고 기반 이미지를 갱신해야 합니다. 검사를 우회하지 않습니다. 로컬 Docker 검증 통과는 실제 NAS Runner·방화벽·포트·보안 검사 통과를 보장하지 않습니다.

## 5. 첫 접속과 데이터 복원

Tailscale 연결 상태에서 브라우저로 **NAS 주소의 8086 포트**에 접속합니다. 처음에는 등록 안건 0건이 정상입니다. 웹에서 관리자 키 입력 → JSON 가져오기 → 1단계 백업 파일 선택. 복원 후 건수와 수정한 내용을 확인합니다. 같은 파일을 다시 올리면 중복 관리번호로 전체 취소됩니다.

서비스 주소는 사용하는 NAS/Tailscale 주소를 기준으로 정하며, 이 저장소에 NAS 로그인 정보는 넣지 않습니다.

## 장애 확인

- pending: 그룹 Runner 연결, 태그와 다른 잡의 실행 여부를 확인합니다.
- Docker 소켓 오류: Runner의 소켓 마운트와 권한을 NAS 관리자가 확인합니다.
- 포트 충돌: 다른 서비스를 종료하지 말고 운영 변수의 PORT를 사용 가능한 번호로 바꿉니다.
- 관리자 키 누락: Protected File 변수와 main 보호 상태를 확인합니다.
- 검증 이미지가 없음: 이 main 파이프라인의 build-test와 image-scan을 다시 실행합니다.
- healthcheck 실패: NAS에서 `docker compose -f compose.prod.yaml ps`와 컨테이너 로그를 확인합니다. 환경변수 전체나 관리자 키는 공유하지 않습니다.

이미지 롤백은 DB 스키마를 되돌리지 않습니다. 실패 시 운영 볼륨을 지우지 말고 predeploy 백업과 이전 버전의 스키마 호환성을 먼저 확인합니다.
