"""Lanza Godot en un escritorio de Windows aparte (CreateDesktop) para que la ventana del juego
nunca aparezca en la pantalla del usuario ni le robe el foco, aunque se renderice de verdad.

Uso: python tools/run_hidden.py [--timeout=600] -- <argumentos de Godot...>
Ej.: python tools/run_hidden.py -- --path . --audio-driver Dummy -- --ib-look --only=plaza
La salida de Godot se vuelca en la consola; el código de salida es el de Godot.
"""
import ctypes, os, subprocess, sys, tempfile
from ctypes import wintypes as wt

GODOT = r"C:\Users\juanm\work\project-night-shift\.tools\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
DESKTOP = "IslaBrisaOculto"

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
u32 = ctypes.WinDLL("user32", use_last_error=True)


class STARTUPINFO(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD), ("lpReserved", wt.LPWSTR), ("lpDesktop", wt.LPWSTR),
                ("lpTitle", wt.LPWSTR), ("dwX", wt.DWORD), ("dwY", wt.DWORD),
                ("dwXSize", wt.DWORD), ("dwYSize", wt.DWORD), ("dwXCountChars", wt.DWORD),
                ("dwYCountChars", wt.DWORD), ("dwFillAttribute", wt.DWORD), ("dwFlags", wt.DWORD),
                ("wShowWindow", wt.WORD), ("cbReserved2", wt.WORD), ("lpReserved2", ctypes.c_void_p),
                ("hStdInput", wt.HANDLE), ("hStdOutput", wt.HANDLE), ("hStdError", wt.HANDLE)]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [("hProcess", wt.HANDLE), ("hThread", wt.HANDLE),
                ("dwProcessId", wt.DWORD), ("dwThreadId", wt.DWORD)]


class SECURITY_ATTRIBUTES(ctypes.Structure):
    _fields_ = [("nLength", wt.DWORD), ("lpSecurityDescriptor", ctypes.c_void_p), ("bInheritHandle", wt.BOOL)]


u32.CreateDesktopW.restype = wt.HANDLE
u32.CreateDesktopW.argtypes = [wt.LPCWSTR, wt.LPCWSTR, ctypes.c_void_p, wt.DWORD, wt.DWORD, ctypes.c_void_p]
k32.CreateFileW.restype = wt.HANDLE
k32.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, ctypes.c_void_p, wt.DWORD, wt.DWORD, wt.HANDLE]
k32.CreateProcessW.argtypes = [wt.LPCWSTR, wt.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, wt.BOOL, wt.DWORD,
                               ctypes.c_void_p, wt.LPCWSTR, ctypes.POINTER(STARTUPINFO), ctypes.POINTER(PROCESS_INFORMATION)]
GENERIC_ALL = 0x10000000
STARTF_USESHOWWINDOW, STARTF_USESTDHANDLES = 0x1, 0x100
SW_SHOWNOACTIVATE = 4
CREATE_NO_WINDOW = 0x08000000


def main() -> int:
    args = sys.argv[1:]
    timeout = 600
    while args and args[0] != "--":
        if args[0].startswith("--timeout="):
            timeout = int(args[0][10:])
        args.pop(0)
    args = args[1:]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    hdesk = u32.CreateDesktopW(DESKTOP, None, None, 0, GENERIC_ALL, None)
    if not hdesk:
        print("CreateDesktop falló:", ctypes.get_last_error())
        return 2
    log = tempfile.NamedTemporaryFile(prefix="ib_hidden_", suffix=".log", delete=False)
    log.close()
    sa = SECURITY_ATTRIBUTES(ctypes.sizeof(SECURITY_ATTRIBUTES), None, True)
    hlog = k32.CreateFileW(log.name, 0x40000000, 3, ctypes.byref(sa), 2, 0x80, None)  # GENERIC_WRITE, CREATE_ALWAYS
    si = STARTUPINFO()
    si.cb = ctypes.sizeof(STARTUPINFO)
    si.lpDesktop = "WinSta0\\" + DESKTOP
    si.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES
    si.wShowWindow = SW_SHOWNOACTIVATE
    si.hStdOutput = si.hStdError = hlog
    pi = PROCESS_INFORMATION()
    cmd = subprocess.list2cmdline([GODOT] + args)
    ok = k32.CreateProcessW(None, cmd, None, None, True, CREATE_NO_WINDOW, None, root, ctypes.byref(si), ctypes.byref(pi))
    if not ok:
        print("CreateProcess falló:", ctypes.get_last_error())
        return 2
    WAIT_TIMEOUT = 0x102
    if k32.WaitForSingleObject(pi.hProcess, timeout * 1000) == WAIT_TIMEOUT:
        k32.TerminateProcess(pi.hProcess, 124)
        k32.WaitForSingleObject(pi.hProcess, 5000)
        print("run_hidden: tiempo agotado, proceso terminado")
    code = wt.DWORD()
    k32.GetExitCodeProcess(pi.hProcess, ctypes.byref(code))
    for h in (pi.hProcess, pi.hThread, hlog):
        k32.CloseHandle(h)
    u32.CloseDesktop(hdesk)
    with open(log.name, encoding="utf-8", errors="replace") as f:
        sys.stdout.write(f.read())
    os.remove(log.name)
    return code.value


if __name__ == "__main__":
    sys.exit(main())
