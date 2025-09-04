# CUBRID JDBC Bundle (Maven Central)
미리 빌드된 CUBRID JDBC 아티팩트를 Maven Central 업로드용으로 번들링합니다.
빌드는 수행하지 않으며, **GPG 서명, 체크섬 생성, Maven 디렉터리 레이아웃 구성, ZIP 패키징**을 자동화합니다.

## 디렉터리 구조
```text
.
├── clear.sh                                 # 정리 스크립트
├── jdbc-bundle.sh                           # 번들링 스크립트
├── README.md
└── bundle/                                  # 작업 디렉터리(입력/중간 산출물)
    ├── cubrid-jdbc-<ver>.jar
    ├── cubrid-jdbc-<ver>-sources.jar
    ├── cubrid-jdbc-<ver>-javadoc.jar
    ├── README.md                            # placeholder에 포함될 문서
    ├── release.pom                          # POM 템플릿
    └── VERSION-DIST                         # 선택: 파일 내용에 버전 기입
```
- 최종 ZIP: 저장소 루트(`./`)에 생성
- 스테이징/서명/체크섬 등 중간 산출물: 기본적으로 `bundle/`아래에 생성

## 요구사항
- bash, zip, gpg(2.x+), md5sum/sha*sum, awk, sed
- 로컬에 GPG 비밀키 존재(서명용)
- `--make-empty-docs` 사용 시 `jar` 필요

## 빠른 시작

1) GPG 정보 설정 (환경변수 또는 CLI로 전달)
```
export GPG_FINGERPRINT='ABC...XYZ'
export SIGN_PASSPHRASE='your-passphrase'
```

2) bundle/ 디렉터리에 파일 배치
- `cubrid-jdbc-<version>.jar`
- `cubrid-jdbc-<version>-sources.jar`
- `cubrid-jdbc-<version>-javadoc.jar`

3) 실행
```bash
./jdbc-bundle.sh
```
> `-v` 옵션과 `VERSION_DIST`가 없으면 `cubrid-jdbc-<version>.jar` 파일명에서 버전을 자동 추론합니다.

## 사용법
```text
./jdbc-bundle.sh -f <GPG_FINGERPRINT> -s <SIGN_PASSPHRASE> [-v <VERSION>] [--make-empty-docs]

옵션:
  -f, --fingerprint     GPG 키 지문  (env: GPG_FINGERPRINT)
  -s, --sign            GPG 서명 패스프레이즈 (env: SIGN_PASSPHRASE)
  -v, --version         버전 (기본: VERSION-DIST 또는 JAR 파일명에서 추론)
      --make-empty-docs sources/javadoc JAR이 없으면 WORK_DIR의 README.md로 placeholder 생성

환경변수:
  WORK_DIR   입력/중간 산출물 위치 (기본: ./bundle)
  OUT_DIR    최종 zip 출력 위치   (기본: 저장소 루트)
```
예시:
```bash
# 환경변수만 사용
export GPG_FINGERPRINT='ABC...XYZ'
export SIGN_PASSPHRASE='your-passphrase'
echo '1.0.0.0000' > bundle/VERSION-DIST
./jdbc-bundle.sh

# CLI 옵션 + placeholder 생성
./jdbc-bundle.sh -f ABC...XYZ -s 'your-passphrase' -v 1.0.0.0000 --make-empty-docs
```

## Placeholder 모드 (`--make-empty-docs`)
- `bundle/README.md`를 포함해 placeholder `-sources.jar` / `-javadoc.jar`를 생성합니다.
- `-sources.jar` / `-javadoc.jar`가 이미 존재한다면, 생성하지 않고 경고 로그만 출력합니다.
