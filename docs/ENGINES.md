# 다운로드 엔진과 라이선스

Jini Downloader의 앱 ZIP에는 외부 다운로드 엔진·미디어 라이브러리 바이너리가 포함되지 않습니다. 사용자가 앱에서 '필수 도구 설치'를 선택하면 아래 원 배포처에서 직접 가져옵니다. 버전과 SHA-256은 [engines.json](../Resources/engines.json)에 고정되어 있습니다.

| 도구 | 용도 | 설치 버전 | 배포처 / 소스 / 라이선스 |
| --- | --- | --- | --- |
| yt-dlp | 동영상 분석·다운로드 | 2026.08.19 | [프로젝트](https://github.com/yt-dlp/yt-dlp), [라이선스 안내](https://github.com/yt-dlp/yt-dlp#licensing) |
| gallery-dl | 갤러리 메타데이터 추출 | 2026.09.09 배포 빌드 | [소스](https://github.com/mikf/gallery-dl), [빌드 배포](https://github.com/gdl-org/builds), [GPL 라이선스](https://github.com/mikf/gallery-dl/blob/master/LICENSE) |
| Deno | yt-dlp의 JavaScript 처리 | 2.9.6 | [프로젝트](https://github.com/denoland/deno), [라이선스](https://github.com/denoland/deno/blob/main/LICENSE.md) |
| FFmpeg | 영상·음성 병합 | 9.0.1, macOS arm64 | [소스·라이선스](https://ffmpeg.org/legal.html), [Martin Riedl 배포처](https://ffmpeg.martin-riedl.de/) |
| FFprobe | 완료 영상 정보 확인 | 9.0.1, macOS arm64 | FFmpeg와 동일 |

FFmpeg와 FFprobe는 FFmpeg 프로젝트의 소스를 바탕으로 Martin Riedl이 제공하는 별도 macOS 빌드입니다. 이 프로젝트가 제작하거나 FFmpeg 공식 프로젝트가 직접 배포하는 바이너리가 아닙니다.

yt-dlp 소스의 Unlicense와 PyInstaller 실행 파일의 라이선스는 같지 않습니다. 공식 문서에 따르면 PyInstaller 실행 파일에는 GPLv3+ 코드가 포함됩니다. FFmpeg 설치 대상으로 지정한 빌드도 GPL 옵션이 활성화되어 있습니다. 각 실행 파일 및 포함 구성요소의 권리는 원 저작권자에게 있습니다.

Jini Downloader는 별도 프로세스를 실행하는 방식으로 이 도구를 사용합니다. 앱 소스에 붙인 MIT 라이선스가 외부 도구의 라이선스를 변경하지 않습니다. 설치된 엔진을 다시 묶어 배포하려면 해당 실행 파일과 종속 라이브러리의 라이선스, 저작권 고지, 대응 소스 제공 조건 등을 별도로 충족해야 합니다.

## 무결성과 설치

1. 고정된 HTTPS URL에서 설치 파일을 내려받습니다.
2. 파일 전체의 SHA-256을 앱에 포함된 값과 비교합니다.
3. 일치한 파일만 압축 해제하고 실행을 확인합니다.
4. 모든 도구가 준비된 후 새 설치 폴더를 적용합니다.

체크섬이 다르면 실행하지 않고 중단합니다. 운영체제 보안 설정을 전역으로 변경하거나 관리자 암호를 요청하지 않습니다. 체크섬은 내려받은 파일이 지정한 배포물과 같은지 확인하는 수단이며, 모든 취약점이 없음을 보장하는 검사는 아닙니다.

설치 도중 취소·실패하면 새 임시 설치 폴더를 정리합니다. 엔진 파일은 앱 번들 바깥의 사용자 Application Support 폴더에 저장합니다. 앱을 휴지통으로 옮기는 것만으로 이 별도 폴더까지 삭제되지는 않습니다.
