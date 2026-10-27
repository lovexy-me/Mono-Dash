# Runs on the Windows build host (DEV). Uploaded next to src.zip and job.json
# by remote_build_android.sh; do not run it by hand.
$ErrorActionPreference = 'Stop'

$Inbox = Split-Path -Parent $MyInvocation.MyCommand.Path
$job = Get-Content (Join-Path $Inbox 'job.json') -Raw | ConvertFrom-Json

$Root    = if ($env:MONO_BUILD_ROOT) { $env:MONO_BUILD_ROOT } else { 'D:\Builds\mono_dash' }
$Staging = Join-Path $Root 'staging'
$Src     = Join-Path $Root 'src'
$Secrets = Join-Path $Root 'secrets'
$OutDir  = Join-Path $Inbox 'out'

# Toolchain. Gradle 8.14 does not run on Android Studio's bundled JBR 25,
# so pin JDK 21 to match the Mac.
$env:JAVA_HOME = if ($env:MONO_JAVA_HOME) { $env:MONO_JAVA_HOME } else { 'C:\Program Files\Java\jdk-21.0.12.1' }
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
# Kotlin incremental compilation fails ("different roots") when plugin sources
# in the pub cache sit on another drive than the project, so keep them together.
$env:PUB_CACHE = if ($env:MONO_PUB_CACHE) { $env:MONO_PUB_CACHE } else { Join-Path (Split-Path -Qualifier $Root) 'Builds\pub-cache' }

# dl.google.com fails the TLS handshake from this host, direct or via the local
# proxy, so point Google's Maven repo at a mirror. The init script is a no-op
# unless GOOGLE_MAVEN_MIRROR is set, leaving other Gradle builds here untouched.
$env:GOOGLE_MAVEN_MIRROR = if ($env:MONO_GOOGLE_MAVEN_MIRROR) { $env:MONO_GOOGLE_MAVEN_MIRROR } else { 'https://maven.aliyun.com/repository/google' }
$initDir = Join-Path $env:USERPROFILE '.gradle\init.d'
New-Item -ItemType Directory -Force $initDir | Out-Null
Set-Content (Join-Path $initDir 'google-maven-mirror.gradle') -Encoding ASCII -Value @'
// Written by scripts/remote_build/build.ps1; active only when GOOGLE_MAVEN_MIRROR is set.
def mirror = System.getenv('GOOGLE_MAVEN_MIRROR')
if (mirror) {
    def redirect = { RepositoryHandler repos ->
        repos.withType(MavenArtifactRepository).configureEach { repo ->
            if (repo.url?.host == 'dl.google.com') repo.url = mirror
        }
    }
    beforeSettings { settings ->
        redirect(settings.pluginManagement.repositories)
        redirect(settings.dependencyResolutionManagement.repositories)
    }
    allprojects { project ->
        redirect(project.buildscript.repositories)
        redirect(project.repositories)
    }
}
'@

# Prefer an SDK pinned to the Mac's Flutter version (D:\Dev\flutter-<ver>).
$FlutterRoot = $env:MONO_FLUTTER_ROOT
if (-not $FlutterRoot) {
    $pinned = "D:\Dev\flutter-$($job.flutterVersion)"
    $FlutterRoot = if (Test-Path $pinned) { $pinned } else { 'D:\Dev\flutter' }
}
$env:PATH = "$FlutterRoot\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$versionFile = Join-Path $FlutterRoot 'bin\cache\flutter.version.json'
$remoteVersion = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw | ConvertFrom-Json).frameworkVersion } else { 'unknown' }
Write-Host "==> Flutter $remoteVersion at $FlutterRoot (Mac: $($job.flutterVersion)); JAVA_HOME=$env:JAVA_HOME"
if ($remoteVersion -ne $job.flutterVersion -and -not $job.allowFlutterMismatch) {
    Write-Host "Flutter version mismatch. Install $($job.flutterVersion) at D:\Dev\flutter-$($job.flutterVersion) or pass --allow-flutter-mismatch."
    exit 3
}

# Unpack into a clean staging dir, then mirror into the persistent src dir so
# build/, .dart_tool/ and Gradle state survive between builds.
Write-Host '==> Unpacking'
if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Force $Staging, $Src | Out-Null
tar -xf (Join-Path $Inbox 'src.zip') -C $Staging
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

robocopy $Staging $Src /MIR /NFL /NDL /NJH /NJS /NP `
    /XD build .dart_tool .gradle .cxx .idea `
    /XF local.properties key.properties *.jks gradlew gradlew.bat gradle-wrapper.jar `
        GeneratedPluginRegistrant.java .flutter-plugins .flutter-plugins-dependencies | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Host "robocopy failed ($LASTEXITCODE)"; exit 4 }

# Signing files live only on this machine.
foreach ($f in 'key.properties', 'upload-keystore.jks') {
    $p = Join-Path $Secrets $f
    if (Test-Path $p) { Copy-Item $p (Join-Path $Src "android\$f") -Force }
    elseif ($job.mode -eq 'release') { Write-Host "Missing $p; release builds need it."; exit 5 }
}

Set-Location $Src
$buildArgs = @('build', $job.kind, "--$($job.mode)")
if ($job.extraArgs) { $buildArgs += $job.extraArgs }

Write-Host '==> flutter pub get'
& flutter.bat pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "==> flutter $($buildArgs -join ' ')"
& flutter.bat @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$artifacts = if ($job.kind -eq 'appbundle') {
    Get-ChildItem "build\app\outputs\bundle\$($job.mode)\*.aab"
} else {
    Get-ChildItem "build\app\outputs\flutter-apk\*-$($job.mode).apk"
}
$artifacts | Copy-Item -Destination $OutDir
$artifacts | ForEach-Object { Write-Host "==> Artifact $($_.Name) ($([math]::Round($_.Length / 1MB, 1)) MB)" }
exit 0
