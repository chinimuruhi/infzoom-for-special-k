Add-Type -AssemblyName System.Windows.Forms

$ScriptName = [Regex]::Match( 
    $MyInvocation.InvocationName,
    '[^\\]+\Z', 
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::SingleLine
    ).Value

Write-Host "Executing: $ScriptName"

$ScriptIsUsta = $ScriptName -match '.*kr.ps1$'
if ($ScriptIsUsta) {
    Write-Host "KR USTA mode"
    $ScriptIsUsta = $true
} else {
    Write-Host "JP eamusement mode"
    $ScriptIsUsta = $false
}

# Use to get INFINITAS registry installation path
$InfRegistry = "HKLM:\SOFTWARE\KONAMI\beatmania IIDX INFINITAS"

# Path of the game itself Usually obtained from the registry
#$InfPath = "C:\Games\beatmania IIDX INFINITAS\"
$InfPath = Get-ItemPropertyValue -LiteralPath $InfRegistry -Name "InstallDir"
$InfExe = Join-Path $InfPath "\game\app\bm2dx.exe"
$InfLauncher = Join-Path $InfPath "\launcher\modules\bm2dx_launcher.exe"
cd $InfPath | Out-Null

# bm2dxinf:// registry
$InfOpen = "HKCR:bm2dxinf\shell\open\command\"
if ($ScriptIsUsta) {
    $InfOpen = "HKCR:bm2dx-kr\shell\open\command\"
}

# full path to this script
$ScriptPath = $MyInvocation.MyCommand.Path

# setting file
$ConfigJson = Join-Path $PSScriptRoot "config.json"

$Config = [ordered]@{
    "Option"="0"
    "WindowWidth"="1280"
    "WindowHeight"="720"
    "WindowPositionX"="0"
    "WindowPositionY"="0"
    "Borderless"=$false
}

# window style
# see https://learn.microsoft.com/en-us/windows/win32/winmsg/window-styles
$WSDefault = 0x14CC0000
$WSBorderless = 0x14080000

# Define Win32 API functions
$Source = @"
    using System;
    using System.Runtime.InteropServices;

    public class Win32Api {
        [DllImport("user32.dll")]
        public static extern int MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll")]
        public static extern int SetWindowLong(IntPtr hWnd, int nIndex, long dwLong);

        [DllImport("user32.dll")]
        public static extern long GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        internal static extern bool GetWindowRect(IntPtr hwnd, out RECT lpRect);

        [DllImport("user32.dll")]
        internal static extern bool GetClientRect(IntPtr hwnd, out RECT lpRect);
        
        [DllImport("User32.dll")]
        public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);

        [StructLayout(LayoutKind.Sequential)]
        internal struct RECT
        {
            public int left, top, right, bottom;
        }
        
        public static void MoveWindow2(IntPtr hndl, int x, int y, int w, int h, bool isBl){
            if(isBl){
                MoveWindow(hndl, x, y, w, h, true);
            }else{
                RECT cRect = new RECT();
                RECT wRect = new RECT();

                GetClientRect(hndl, out cRect);
                GetWindowRect(hndl, out wRect);

                int cWidth = cRect.right - cRect.left;
                int cHeight = cRect.bottom - cRect.top;

                int wWidth = wRect.right - wRect.left;
                int wHeight = wRect.bottom - wRect.top;

                int newW = w + (wWidth - cWidth);
                int newH = h + (wHeight - cHeight);

                MoveWindow(hndl, x, y, newW, newH, true);
            }

        }
    }
"@
Add-Type -TypeDefinition $Source -Language CSharp 

function Save-Config() {
    $Config | ConvertTo-Json | Out-File -FilePath $ConfigJson -Encoding utf8
}

function Start-Exe($exe, $workDir, $arg){
    Write-Host "Start-Exe launching:`n  EXE:  $exe`n  ARG: $arg`n  DIR: $workDir`n"

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $exe
    $info.WorkingDirectory = $workDir
    $info.Arguments = $arg
    $info.UseShellExecute = $false

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $info

    $p.Start() | Out-Null
    return $p
}

function Switch-Borderless($isBl){
    if ($isBl) {
        [Win32Api]::SetWindowLong($handle, -16, $WSBorderless) | Out-Null
    }else{
        [Win32Api]::SetWindowLong($handle, -16, $WSDefault) | Out-Null
    }
}

function Get-Monitor($monitor_number){
    $monitor_number = [int]$monitor_number
    # https://stackoverflow.com/questions/7967699/get-screen-resolution-using-wmi-powershell-in-windows-7
    # get a lit of monitors...
    $screens  = [system.windows.forms.screen]::AllScreens

    # find primary monitor first
    $primary = $screens[0]
    $col_screens | ForEach-Object {
        if ("$($_.Primary)" -eq "True") {
            $primary = $_
            break
        }
    }

    # 0 = primary, 1 and up = monitor number
    if ($monitor_number -eq 0) {
        return $primary
    }

    if ($monitor_number -gt $screens.Count) {
        return $primary
    }

    return $screens[$monitor_number - 1]
}

# change registry when no argument is specified
if ([string]::IsNullOrEmpty($Args[0])) {
    echo("Script install / uninstall")
    if (!(New-Object Security.Principal.WindowsPrincipal(
                [Security.Principal.WindowsIdentity]::GetCurrent()
            )).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERROR: please run the script as administrator!" -ForegroundColor Red
        Pause
        exit;
    }
    
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null
    $val = Get-ItemPropertyValue -LiteralPath $InfOpen -Name "(default)"

    echo("current command: " + $val)
    echo ""
    echo("script path: " + $ScriptPath)
    echo("game path: " + $InfPath)
    echo ""
    
    echo "0 : revert to default (uninstall)"
    echo "1 : set to this script path"
    echo "3 : copy script file to game directory and set to new script path (install)"
    $num = Read-Host "number->"

    switch ($num) {
        0 {
            $val = """${InfLauncher}"" ""%1"""
        }
        1 {
            $val = """powershell"" ""-file"" ""${ScriptPath}"" ""%1"""
        }
        3 {
            $From = Join-Path $PSScriptRoot $ScriptName
            Copy-Item -Path $From -Destination $InfPath

            $From = Join-Path $PSScriptRoot "infzoom.exe"
            Copy-Item -Path $From -Destination $InfPath

            $From = Join-Path $PSScriptRoot "infzoom.ini"
            Copy-Item -Path $From -Destination $InfPath

            $NewScriptPath = Join-Path $InfPath $ScriptName
            $val = """powershell"" ""-file"" ""${NewScriptPath}"" ""%1"""
        }
        Default {
            exit
        }
    }
    Set-ItemProperty $InfOpen -name "(default)" -value $val
    echo "done. Press enter key to exit."
    Read-Host
    exit
}

# Something to start the game from here
# read configuration file
if(Test-Path $ConfigJson){
    $Config = [ordered]@{}
(ConvertFrom-Json (Get-Content $ConfigJson -Encoding utf8 -Raw )).psobject.properties | Foreach { $Config[$_.Name] = $_.Value }
}

# Arguments to pass to the game itself
$InfArgs = ""

# pick up the token from the arguments
$Args[0] -match "tk=(.{64})" | Out-Null
$InfArgs += " -t "+$Matches[1]

# add --trial for trial mode
if ($Args[0].Contains("trial")) {
    $InfArgs += " --trial"
}

echo "Please select option."
echo "0 : Launcher (required for game updates)"
echo "1 : WASAPI"
echo "2 : WASAPI + window mode (60Hz only)"
echo "3 : ASIO"
echo "4 : ASIO + window mode (60Hz only)"
echo "5 : WASAPI + fullscreen borderless (60Hz only) with zoom"
echo "6 : ASIO + fullscreen borderless (60Hz only) with zoom"
echo "7 : WASAPI + zoom (required Special K)"
echo "8 : ASIO + zoom (required Special K)"

$num = Read-Host "number (press enter for option $($Config["Option"]))"
if([string]::IsNullOrEmpty($num)){
    $num=$Config["Option"]
}

$WithZoom = $false
$RequiredSpecialK = $false
switch ($num) {
    0 {
        Start-Process -FilePath $InfLauncher -ArgumentList $Args[0]
        exit
    }
    1 {

    }
    2 {
        $InfArgs += " -w"
    }
    3 {
        $InfArgs += " --asio"
    }
    4 {
        $InfArgs += " -w"
        $InfArgs += " --asio"
    }
    5 {
        $InfArgs += " -w"
        $WithZoom = $true
    }
    6 {
        $InfArgs += " -w"
        $InfArgs += " --asio"
        $WithZoom = $true
    }
    7 {
        $WithZoom = $true
        $RequiredSpecialK = $true
    }
    8 {
        $InfArgs += " --asio"
        $WithZoom = $true
        $RequiredSpecialK = $true
    }
    Default {
        exit
    }
}

if ($ScriptIsUsta) {
    $InfArgs += " --kr"
}

# save settings
$Config["Option"] = [string]$num
Save-Config

# wait start INFINITAS
if ($RequiredSpecialK) { 
    echo 'Please disable Special K before starting Infinitas.'
    echo 'After a splash screen is displayed, please enable Special K and set windowmode borderless.'
    echo "Press any key to start Infinitas."
    while($true){
        if([Console]::KeyAvailable){
            [Console]::ReadKey($true) >$null
            break
        }
        Start-Sleep 1
    }
}

# start INFINITAS
$p = Start-Exe $InfExe "" $InfArgs

if ($WithZoom) {
    # wait for window creation
    $p.WaitForInputIdle() | Out-Null
    $handle = $p.MainWindowHandle

    # we let the separate EXE handle everything for this mode
    $InfZoomExe = Join-Path $PSScriptRoot "infzoom.exe"
    $infzoom_p = Start-Exe $InfZoomExe $PSScriptRoot $handle
    $infzoom_p.WaitForExit() | Out-Null
    Pause
} elseif ($InfArgs.Contains("-w")){
    # wait for window creation
    $p.WaitForInputIdle() | Out-Null
    $handle = $p.MainWindowHandle

    # set to previous position and size
    Switch-Borderless($Config["Borderless"])
    [Win32Api]::MoveWindow2(
        $handle,
        $Config["WindowPositionX"],
        $Config["WindowPositionY"],
        $Config["WindowWidth"],
        $Config["WindowHeight"],
        $Config["Borderless"])

    echo ""
    echo "window mode setting"
    echo "example:"
    echo "  window size -> type 1280x720"
    echo "  window position -> type 100,100"
    echo "Press enter key to switch to Borderless window, or use mouse cursor to resize window"

    while($true){
        $inputStr=Read-Host " "
        if([string]::IsNullOrEmpty($inputStr)){
            $Config["Borderless"] = (-Not $Config["Borderless"])
        }elseif($inputStr.Contains("x")){
            $val = $inputStr.Split('x')
            $Config["WindowWidth"]=$val[0]
            $Config["WindowHeight"]=$val[1]
        }elseif($inputStr.Contains(",")){
            $val = $inputStr.Split(',')
            $Config["WindowPositionX"]=$val[0]
            $Config["WindowPositionY"]=$val[1]
        }

        # make borderless
        Switch-Borderless($Config["Borderless"])

        # Reflect position and size
        [Win32Api]::MoveWindow2(
            $handle,
            $Config["WindowPositionX"],
            $Config["WindowPositionY"],
            $Config["WindowWidth"],
            $Config["WindowHeight"],
            $Config["Borderless"])

        # write to config file
        Save-Config
    
    }
}
