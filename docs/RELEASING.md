# 업데이트와 릴리스

## 다운로드 버튼 유지

README의 최신 앱 링크는 다음 고정 주소입니다.

https://github.com/Umbrellafig/jini-downloader/releases/latest/download/JiniDownloader-macOS-arm64.zip

정식 릴리스에 같은 이름의 앱 ZIP을 올리면 README의 버튼을 수정하지 않아도 최신 파일로 연결됩니다. Source code ZIP과 앱 ZIP은 별개입니다.

## 다음 버전 만들기

1. 코드를 수정하고 `bash scripts/test.sh`로 검증합니다.
2. `Resources/Info.plist`의 `CFBundleShortVersionString`과 `CFBundleVersion`을 올립니다.
3. 화면의 버전 표시, CHANGELOG.md와 문서의 내용도 맞춥니다.
4. 로컬 테스트는 `bash scripts/package.sh --local`, 공개용은 아래 인증 설정 후 `bash scripts/package.sh --release`로 빌드합니다. 실제 앱을 테스트합니다.
5. 변경 사항을 main에 커밋·푸시합니다.
6. 같은 버전의 태그를 만들어 푸시합니다. 예를 들어 앱 버전이 1.2.1이면:

```bash
git tag v1.2.1
git push origin v1.2.1
```

GitHub Actions가 테스트·Developer ID 서명·Apple 공증·티켓 첨부·Gatekeeper 검증 후 앱 ZIP과 SHA256SUMS.txt를 정식 Release로 공개합니다. 인증 설정 누락이나 공증 실패 시 배포를 중단합니다. Actions 탭에서 성공 여부를 확인하세요. 이미 같은 태그의 릴리스가 있으면 기존 파일을 덮어쓰지 않습니다. 수정 배포에는 새 버전을 사용하세요.

초기 1.2.0은 로컬에서 검증한 파일을 수동 Release로 올릴 수도 있습니다. 자동화는 후속 버전 태그부터 사용할 수 있습니다.

## 엔진 버전 갱신

`Resources/engines.json`의 버전·고정 URL·SHA-256·파일 크기를 함께 업데이트합니다. GitHub 배포물은 공식 Release 자산 digest와 실제 다운로드 파일을 비교하고, FFmpeg/FFprobe는 빌드 배포처의 .sha256과 비교합니다. 목록의 revision도 바꿉니다. 설치 확인·분석·다운로드를 다시 테스트한 후 앱 새 버전을 배포하세요. 체크섬 검증을 끄거나 URL만 최신으로 바꾸면 안 됩니다.

## Apple 서명·공증

현재 공개된 **1.2.0은 임시 서명 빌드**입니다. 아래 절차로 공증된 새 버전을 배포하기 전까지 기존 다운로드 파일의 경고는 그대로 남습니다. 일반적인 최초 실행 확인과 Apple의 미확인 개발자 차단은 다릅니다.

### 필요한 Apple 설정

Apple Developer Program 계정의 **Developer ID Application** 인증서와 개인 키가 필요합니다. `Apple Development` 인증서로는 외부 배포 공증을 대신할 수 없습니다. Xcode의 Accounts → Manage Certificates 또는 Apple Developer 계정에서 준비합니다. 인증서·비밀번호·개인 키는 Git에 넣지 않습니다.

### 이 Mac에서 정식 패키지 만들기

1. `security find-identity -v -p codesigning`으로 Developer ID Application 인증서가 있는지 확인합니다.
2. `xcrun notarytool store-credentials jini-release`를 실행해 대화형으로 공증 인증 정보를 Keychain에 저장합니다. Apple ID 방식에서는 앱 전용 암호를 사용합니다.
3. 다음 환경 변수로 빌드합니다. 인증서 이름은 실제 값으로 바꿉니다.

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE='jini-release'
bash scripts/package.sh --release
```

스크립트는 hardened runtime·타임스탬프로 서명하고 Apple의 Accepted 응답을 확인한 뒤 앱에 티켓을 첨부합니다. 최종 ZIP은 티켓 첨부 후 생성하며 체크섬도 새로 계산합니다. 임시 서명으로 자동 전환하지 않습니다.

### GitHub 자동 배포 설정

저장소 Settings → Secrets and variables → Actions에 아래 Secrets를 등록합니다.

- `APPLE_CERTIFICATE_BASE64`: 개인 키가 포함된 Developer ID Application 인증서 `.p12`의 Base64
- `APPLE_CERTIFICATE_PASSWORD`: 해당 `.p12` 내보내기 암호
- `DEVELOPER_ID_APPLICATION`: 인증서의 전체 이름 (`Developer ID Application: …`)
- `APPLE_ID`: 공증에 사용할 Apple ID
- `APPLE_TEAM_ID`: 인증서의 Team ID
- `APPLE_APP_PASSWORD`: 해당 Apple ID의 앱 전용 암호

일회용 GitHub macOS 러너의 임시 Keychain에 인증서를 설치합니다. 작업이 끝나면 Keychain과 임시 인증서 파일을 제거합니다. Secret을 코드·이슈·채팅에 붙여넣지 마세요.

새 버전을 배포한 뒤 브라우저에서 ZIP을 받아 압축을 풀고 실행해 미확인 개발자 차단이 없는지 확인합니다. 서명이나 공증은 폴더 접근 등 별도의 개인정보 보호 권한까지 없애지는 않습니다.

참고: [Apple의 공증 안내](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Developer ID](https://developer.apple.com/developer-id/)

## Sparkle 업데이트 배포

앱의 `SUPublicEDKey`와 짝을 이루는 개인 키는 이 Mac 로그인 Keychain의 `io.github.umbrellafig.jini-downloader` 계정에 생성했습니다. 개인 키를 잃으면 기존 사용자의 업데이트를 이어가기 어려우므로 안전하게 보관합니다. 공개 키는 저장소에, 개인 키는 Keychain/CI Secret에만 둡니다.

- 로컬: `bash scripts/package.sh --release` 성공 후 `bash scripts/appcast.sh`를 실행합니다.
- CI: 별도의 `SPARKLE_PRIVATE_KEY` Secret이 필요합니다. Sparkle `generate_keys --account io.github.umbrellafig.jini-downloader -x <보안경로>`로 내보낸 내용을 등록하고, 내보낸 파일을 저장소에 넣지 않습니다. 키를 임의로 새로 생성하면 안 됩니다.
- Release에 앱 ZIP, `SHA256SUMS.txt`, `appcast.xml`을 함께 올립니다. 피드는 버전별 고정 ZIP URL을 가리켜 새 릴리스가 나와도 검증 대상 파일이 바뀌지 않습니다.
- 피드는 앱의 `releases/latest/download/appcast.xml`에서 가져옵니다. 프리릴리스는 최신 안정 버전에 영향을 주지 않습니다.
- 앱 버전과 빌드 번호를 모두 올립니다. 개인 키가 앱의 공개 키와 다르면 피드 생성이 실패하며 배포를 중단해야 합니다.
- Sparkle 2.9.6을 체크섬으로 고정하고 빌드 때 받아 포함합니다. Sparkle helper와 XPC는 내부부터 서명하고 마지막에 앱을 서명합니다.

1.2.0 사용자는 첫 업데이트 지원 버전을 직접 설치해야 합니다. 이후 앱에서 확인·다운로드·설치·재시작합니다.
