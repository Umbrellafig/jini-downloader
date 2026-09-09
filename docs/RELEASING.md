# 업데이트와 릴리스

## 다운로드 버튼 유지

README의 최신 앱 링크는 다음 고정 주소입니다.

https://github.com/Umbrellafig/jini-downloader/releases/latest/download/JiniDownloader-macOS-arm64.zip

정식 릴리스에 같은 이름의 앱 ZIP을 올리면 README의 버튼을 수정하지 않아도 최신 파일로 연결됩니다. Source code ZIP과 앱 ZIP은 별개입니다.

## 다음 버전 만들기

1. 코드를 수정하고 `bash scripts/test.sh`로 검증합니다.
2. `Resources/Info.plist`의 `CFBundleShortVersionString`과 `CFBundleVersion`을 올립니다.
3. 화면의 버전 표시, CHANGELOG.md와 문서의 내용도 맞춥니다.
4. `bash scripts/package.sh`로 빌드하고 실제 앱을 테스트합니다.
5. 변경 사항을 main에 커밋·푸시합니다.
6. 같은 버전의 태그를 만들어 푸시합니다. 예를 들어 앱 버전이 1.2.1이면:

```bash
git tag v1.2.1
git push origin v1.2.1
```

GitHub Actions가 테스트·빌드 후 앱 ZIP과 SHA256SUMS.txt를 정식 Release로 공개합니다. Actions 탭에서 성공 여부를 확인하세요. 이미 같은 태그의 릴리스가 있으면 기존 파일을 덮어쓰지 않습니다. 수정 배포에는 새 버전을 사용하세요.

초기 1.2.0은 로컬에서 검증한 파일을 수동 Release로 올릴 수도 있습니다. 자동화는 후속 버전 태그부터 사용할 수 있습니다.

## 엔진 버전 갱신

`Resources/engines.json`의 버전·고정 URL·SHA-256·파일 크기를 함께 업데이트합니다. GitHub 배포물은 공식 Release 자산 digest와 실제 다운로드 파일을 비교하고, FFmpeg/FFprobe는 빌드 배포처의 .sha256과 비교합니다. 목록의 revision도 바꿉니다. 설치 확인·분석·다운로드를 다시 테스트한 후 앱 새 버전을 배포하세요. 체크섬 검증을 끄거나 URL만 최신으로 바꾸면 안 됩니다.

## Apple 서명·공증

현재 스크립트는 로컬 임시 서명만 수행합니다. Developer ID 서명·공증을 자동화하려면 Apple Developer 계정과 인증서·공증 자격을 별도로 준비해야 합니다. 비밀 키나 토큰은 저장소 파일에 넣지 말고 필요한 GitHub Actions Secret으로 관리하세요. 현재 저장소에는 이러한 비밀정보가 없습니다.
