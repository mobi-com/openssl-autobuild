function Build-OpenSSL {
    param ($Branch, $Dst)

    if ($Env:VSCMD_ARG_TGT_ARCH -like '*x64') {
        $target = 'VC-WIN64A'
    } else {
        $target = 'VC-WIN32'
    }
    if ($Branch -eq 'openssl-1.1.1') {
        perl Configure --prefix=$Dst --openssldir=. $target
    } else {
        perl Configure enable-fips --prefix=$Dst --openssldir=. $target
    }
    if ($lastexitcode -ne 0) {
        Write-Host 'Failed to configure'
        Exit 1
    }

    nmake
    if ($lastexitcode -ne 0) {
        Write-Host 'Failed to make'
        Exit 1
    }

    nmake test
    if ($lastexitcode -ne 0) {
        Write-Host 'Failed to test'
        Exit 1
    }

    nmake install
    if ($lastexitcode -ne 0) {
        Write-Host 'Failed to install'
        Exit 1
    }
}

$ErrorActionPreference = 'Stop'

$Env:PATH += ';C:\Strawberry\perl\bin;C:\Program Files\NASM'
$source = 'https://www.openssl.org/source/'
$site = Invoke-WebRequest $source
$links = $site.Links | Where-Object {$_.href -like 'openssl-*.tar.gz'}
foreach ($tarball in $links.href) {
    $arch = $Env:VSCMD_ARG_TGT_ARCH
    $basename = $tarball -replace '\.tar\.gz$'
    if ($basename -like 'openssl-1.*') {
        $branch = $basename -replace '^(openssl-[0-9]+\.[0-9]+\.[0-9]+).*', '$1'
    } else {
        $branch = $basename -replace '^(openssl-[0-9]+\.[0-9]+).*', '$1'
    }

    $zip = $basename + '-' + $arch + '.zip'
    $download_url = 'https://www.stunnel.org/openssl/windows/archive/' + $zip
    try {
        $result = Invoke-WebRequest -Method HEAD -Uri $download_url
        if ($result.StatusCode -ne 200) {
            throw 'Could not find the previous build'
        }
        Write-Host $download_url 'date:' $result.Headers['Last-Modified']
        $culture = Get-Culture -Name en-US
        $datetime = $result.Headers['Last-Modified'].ToDateTime($culture)
        $zip_time = [int64](Get-Date -Date $datetime -UFormat '%s')
        $scripts_time = git log -1 --format=%ct .github/workflows/autobuild.yml .scripts/autobuild.ps1
        if ($zip_time -gt $scripts_time) {
            Write-Host $zip 'does not need rebuilding'
            continue
        }
    } catch {
        Write-Host 'Could not find the previous build'
    }

    $openssl_url = $source + $tarball
    if (Test-Path -Path $tarball -PathType Leaf) {
        Write-Host $tarball 'already downloaded'
    } else {
        Write-Host 'Downloading' $tarball
        Invoke-RestMethod -Uri $openssl_url -OutFile $tarball
    }

    if (-Not (Test-Path -Path $arch -PathType Container)) {
        $result = New-Item -ItemType Directory -Name $arch
    }
    $build = $arch + '/' + $basename
    if (Test-Path -Path $build -PathType Container) {
        Write-Host 'Removing' $build
        Remove-Item -Recurse -Force $build
    }
    Write-Host 'Extracting' $tarball
    tar -xz -C $arch -f $tarball
    if ($lastexitcode -ne 0) {
        Write-Host 'Failed to extract the tarball'
        Exit 1
    }

    $dst = '/' + $branch + '-' + $arch
    Set-Location $build
    Build-OpenSSL -Branch $branch -Dst $dst
    Set-Location ../..

    Write-Host 'Compressing' $zip
    Compress-Archive -Path $dst -DestinationPath $zip -Force
}
