param(
    [string]$LuaLibrary = 'C:\Program Files\VideoLAN\VLC\plugins\lua\liblua_plugin.dll',
    [switch]$SkipArtifacts
)
$ErrorActionPreference = 'Stop'
$libraryPath = (Resolve-Path -LiteralPath $LuaLibrary).Path
$dependencyPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $libraryPath))
if (-not ('ClarisGrowbloxLuaNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ClarisGrowbloxLuaNative {
    [DllImport("kernel32", CharSet = CharSet.Unicode)] public static extern IntPtr AddDllDirectory(string path);
    [DllImport("kernel32")] public static extern bool RemoveDllDirectory(IntPtr cookie);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("liblua_plugin.dll", CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr luaL_newstate();
    [DllImport("liblua_plugin.dll", CallingConvention = CallingConvention.Cdecl)] public static extern void luaL_openlibs(IntPtr state);
    [DllImport("liblua_plugin.dll", CallingConvention = CallingConvention.Cdecl)] public static extern int luaL_loadbuffer(IntPtr state, byte[] code, UIntPtr size, string name);
    [DllImport("liblua_plugin.dll", CallingConvention = CallingConvention.Cdecl)] public static extern int lua_pcall(IntPtr state, int args, int results, int errorHandler);
    [DllImport("liblua_plugin.dll", CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr lua_tolstring(IntPtr state, int index, IntPtr size);
    [DllImport("liblua_plugin.dll", CallingConvention = CallingConvention.Cdecl)] public static extern void lua_settop(IntPtr state, int index);
    [DllImport("liblua_plugin.dll", CallingConvention = CallingConvention.Cdecl)] public static extern void lua_close(IntPtr state);
}
'@
}
$cookie = [ClarisGrowbloxLuaNative]::AddDllDirectory($dependencyPath)
$loaded = [ClarisGrowbloxLuaNative]::LoadLibraryEx($libraryPath, [IntPtr]::Zero, 0x1100)
if ($loaded -eq [IntPtr]::Zero) { throw 'Cannot load the existing Lua library.' }
$state = [ClarisGrowbloxLuaNative]::luaL_newstate()
if ($state -eq [IntPtr]::Zero) { throw 'Cannot create the Lua state.' }
function Invoke-Lua([string]$Source, [string]$Name, [bool]$Execute) {
    [ClarisGrowbloxLuaNative]::lua_settop($state, 0)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Source)
    $result = [ClarisGrowbloxLuaNative]::luaL_loadbuffer($state, $bytes, [UIntPtr]::new([uint64]$bytes.Length), $Name)
    if ($result -eq 0 -and $Execute) {
        $result = [ClarisGrowbloxLuaNative]::lua_pcall($state, 0, 1, 0)
    }
    if ($result -ne 0) {
        $message = [Runtime.InteropServices.Marshal]::PtrToStringAnsi([ClarisGrowbloxLuaNative]::lua_tolstring($state, -1, [IntPtr]::Zero))
        throw "$Name failed: $message"
    }
    if ($Execute) {
        [Runtime.InteropServices.Marshal]::PtrToStringAnsi([ClarisGrowbloxLuaNative]::lua_tolstring($state, -1, [IntPtr]::Zero))
    } else {
        "Compiled $Name"
    }
}
try {
    [ClarisGrowbloxLuaNative]::luaL_openlibs($state)
    $projectPath = Split-Path -Parent $PSScriptRoot
    $coreSource = [IO.File]::ReadAllText((Join-Path $projectPath 'src\core.lua'))
    Invoke-Lua $coreSource 'src/core.lua' $false
    Invoke-Lua ([IO.File]::ReadAllText((Join-Path $projectPath 'src\main.lua'))) 'src/main.lua' $false
    if (-not $SkipArtifacts) {
        foreach ($artifact in @('main.lua', 'loader.lua')) {
            Invoke-Lua ([IO.File]::ReadAllText((Join-Path $projectPath $artifact))) $artifact $false
        }
    }
    $fixture = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'core.lua')).Replace('-- CLARIS_CORE_SOURCE', $coreSource)
    Invoke-Lua $fixture 'core offline tests' $true
    if (-not $SkipArtifacts) {
        $runtimeSource = [IO.File]::ReadAllText((Join-Path $projectPath 'main.lua'))
        $runtimeFixture = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'runtime.lua')).Replace('-- CLARIS_RUNTIME_SOURCE', $runtimeSource)
        Invoke-Lua $runtimeFixture 'actual script offline runtime tests' $true
    }
} finally {
    [ClarisGrowbloxLuaNative]::lua_close($state)
    if ($cookie -ne [IntPtr]::Zero) { [void][ClarisGrowbloxLuaNative]::RemoveDllDirectory($cookie) }
}
