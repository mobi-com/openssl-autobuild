function Build-OpenSSL {
    param ($Dst)

    if ($Env:VSCMD_ARG_TGT_ARCH -like '*x64') {
        $target = 'VC-WIN64A'
    } else {
        $target = 'VC-WIN32'
    }
    perl Configure --prefix=$Dst --openssldir=. $target
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
    if (Test-Path -Path $zip -PathType Leaf) {
        Write-Host $zip 'already exists'
        continue
    }

    $url = $source + $tarball
    if (Test-Path -Path $tarball -PathType Leaf) {
        Write-Host $tarball 'already downloaded'
    } else {
        Write-Host 'Downloading' $tarball
        Invoke-RestMethod -Uri $url -OutFile $tarball
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
    Build-OpenSSL -Dst $dst
    Set-Location ../..

    Write-Host 'Compressing' $zip
    Compress-Archive -Path $dst -DestinationPath $zip -Force
    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        $link = $branch + '-' + $arch + '.zip'
        Write-Host 'Linking' $link
        if (Test-Path -Path $link -PathType Leaf) {
            Remove-Item -Force $link
        }
        $result = New-Item -ItemType SymbolicLink -Path $link -Target $zip
    } else {
        Write-Host 'Linking' $link 'requires administrative privileges'
    }
}
