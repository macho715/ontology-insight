# Java 설치 가이드 (Windows)

## 🎯 Java 11+ 설치 (Fuseki 실행 필수)

### 방법 1: Microsoft OpenJDK (권장)
1. **다운로드**: https://learn.microsoft.com/en-us/java/openjdk/download
2. **Windows x64 MSI 설치**: `microsoft-jdk-17.0.9-windows-x64.msi`
3. **자동 PATH 설정**: MSI 설치 시 자동으로 환경변수 설정됨

### 방법 2: Oracle JDK
1. **다운로드**: https://www.oracle.com/java/technologies/downloads/
2. **Java SE Development Kit 17**: Windows x64 Installer
3. **수동 PATH 설정** (필요시):
   ```
   JAVA_HOME = C:\Program Files\Java\jdk-17
   PATH += %JAVA_HOME%\bin
   ```

### 방법 3: Chocolatey (개발자 권장)
```powershell
# PowerShell 관리자 권한으로 실행
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Java 설치
choco install openjdk17 -y
```

## ✅ 설치 확인

PowerShell에서 다음 명령 실행:
```powershell
java -version
javac -version
```

**예상 출력:**
```
openjdk version "17.0.9" 2023-10-17
OpenJDK Runtime Environment Microsoft-8526440 (build 17.0.9+8)
OpenJDK 64-Bit Server VM Microsoft-8526440 (build 17.0.9+8, mixed mode, sharing)
```

## 🔧 문제 해결

### "java is not recognized" 오류
1. **새 PowerShell 창** 열기 (환경변수 반영)
2. **수동 PATH 확인**:
   ```powershell
   $env:PATH -split ';' | Select-String java
   ```
3. **JAVA_HOME 확인**:
   ```powershell
   echo $env:JAVA_HOME
   ```

### 여러 Java 버전 충돌
```powershell
# 설치된 Java 버전 확인
where java
# 또는
Get-Command java -All
```

---

**설치 완료 후 이 창을 닫고 새 PowerShell에서 다음 명령으로 Fuseki 테스트를 계속하세요:**
```powershell
java -version
.\setup-fuseki.ps1
```
