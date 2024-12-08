const std = @import("std");

pub const WINAPI = std.os.windows.WINAPI;

pub const BOOL = c_int;
pub const CHAR = u8;
pub const ATOM = u16;
pub const HBRUSH = *opaque {};
pub const HCURSOR = *opaque {};
pub const HICON = *opaque {};
pub const HINSTANCE = *opaque {};
pub const HMENU = *opaque {};
pub const HGLRC = *opaque {};
pub const HMODULE = *opaque {};
pub const PROC = *opaque {};
pub const HMONITOR = *opaque {};
pub const HWND = std.os.windows.HWND;
pub const HRGN = *opaque {};
pub const HDC = *opaque {};
pub const INT = c_int;
pub const LPCSTR = [*:0]const CHAR;
pub const LPSTR = [*:0]CHAR;
pub const LPCVOID = *const anyopaque;
pub const LPVOID = *anyopaque;
pub const UINT = c_uint;
pub const LONG_PTR = isize;
pub const ULONG_PTR = usize;
pub const WORD = u16;
pub const DWORD = u32;
pub const LONG = i32;
pub const BYTE = u8;
pub const SHORT = i16;
pub const HRESULT = c_long;
pub const USHORT = u16;
pub const WCHAR = u16;
pub const HANDLE = *const anyopaque;
pub const HBITMAP = *opaque {};

pub const HGDIOBJ = *opaque {};

pub const WPARAM = usize;
pub const LPARAM = LONG_PTR;
pub const LRESULT = LONG_PTR;

pub const CW_USEDEFAULT = @as(i32, @bitCast(@as(u32, 0x80000000)));

pub const RECT = extern struct {
    left: LONG = 0,
    top: LONG = 0,
    right: LONG = 0,
    bottom: LONG = 0,
};

pub const POINT = extern struct {
    x: LONG = 0,
    y: LONG = 0,
};

pub const IDC_ARROW: LPCSTR = @ptrFromInt(32512);
pub const IDC_IBEAM: LPCSTR = @ptrFromInt(32513);
pub const IDC_WAIT: LPCSTR = @ptrFromInt(32514);
pub const IDC_CROSS: LPCSTR = @ptrFromInt(32515);
pub const IDC_UPARROW: LPCSTR = @ptrFromInt(32516);
pub const IDC_SIZE: LPCSTR = @ptrFromInt(32640);
pub const IDC_ICON: LPCSTR = @ptrFromInt(32641);
pub const IDC_SIZENWSE: LPCSTR = @ptrFromInt(32642);
pub const IDC_SIZENESW: LPCSTR = @ptrFromInt(32643);
pub const IDC_SIZEWE: LPCSTR = @ptrFromInt(32644);
pub const IDC_SIZENS: LPCSTR = @ptrFromInt(32645);
pub const IDC_SIZEALL: LPCSTR = @ptrFromInt(32646);
pub const IDC_NO: LPCSTR = @ptrFromInt(32648);
pub const IDC_HAND: LPCSTR = @ptrFromInt(32649);
pub const IDC_APPSTARTING: LPCSTR = @ptrFromInt(32650);
pub const IDC_HELP: LPCSTR = @ptrFromInt(32651);
pub const IDC_PIN: LPCSTR = @ptrFromInt(32671);
pub const IDC_PERSON: LPCSTR = @ptrFromInt(32672);

pub extern "user32" fn LoadCursorA(hInstance: ?HINSTANCE, lpCursorName: LPCSTR) callconv(WINAPI) ?HCURSOR;

pub extern "user32" fn RegisterClassExA(*const WNDCLASSEXA) callconv(WINAPI) ATOM;

pub extern "user32" fn UnregisterClassA(lpClassName: LPCSTR, hInstance: HINSTANCE) callconv(WINAPI) BOOL;

pub extern "user32" fn AdjustWindowRectEx(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL, dwExStyle: DWORD) callconv(WINAPI) BOOL;

pub extern "user32" fn CreateWindowExA(dwExStyle: DWORD, lpClassName: ?LPCSTR, lpWindowName: ?LPCSTR, dwStyle: DWORD, X: i32, Y: i32, nWidth: i32, nHeight: i32, hWindParent: ?HWND, hMenu: ?HMENU, hInstance: ?HINSTANCE, lpParam: ?LPVOID) callconv(WINAPI) ?HWND;

pub extern "user32" fn DestroyWindow(hWnd: ?HWND) BOOL;

pub extern "user32" fn DefWindowProcA(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) LRESULT;

pub const PM_NOREMOVE = 0x0000;
pub const PM_REMOVE = 0x0001;
pub const PM_NOYIELD = 0x0002;

pub extern "user32" fn PeekMessageA(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(WINAPI) BOOL;

pub extern "user32" fn DispatchMessageA(lpMsg: *const MSG) callconv(WINAPI) LRESULT;

pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(WINAPI) BOOL;

pub const WS_BORDER = 0x00800000;
pub const WS_OVERLAPPED = 0x00000000;
pub const WS_SYSMENU = 0x00080000;
pub const WS_DLGFRAME = 0x00400000;
pub const WS_CAPTION = WS_BORDER | WS_DLGFRAME;
pub const WS_MINIMIZEBOX = 0x00020000;
pub const WS_MAXIMIZEBOX = 0x00010000;
pub const WS_THICKFRAME = 0x00040000;
pub const WS_OVERLAPPEDWINDOW = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
pub const WS_VISIBLE = 0x10000000;
pub const WS_POPUP = 0x80000000;
pub const WS_CLIPSIBLINGS = 0x04000000;
pub const WS_CLIPCHILDREN = 0x02000000;
pub const WS_SIZEBOX = WS_THICKFRAME;

pub const SIZE_RESTORED = 0;
pub const SIZE_MINIMIZED = 1;
pub const SIZE_MAXIMIZED = 2;
pub const SIZE_MAXSHOW = 3;
pub const SIZE_MAXHIDE = 4;

pub const WM_MOUSEMOVE = 0x0200;
pub const WM_LBUTTONDOWN = 0x0201;
pub const WM_LBUTTONUP = 0x0202;
pub const WM_LBUTTONDBLCLK = 0x0203;
pub const WM_RBUTTONDOWN = 0x0204;
pub const WM_RBUTTONUP = 0x0205;
pub const WM_RBUTTONDBLCLK = 0x0206;
pub const WM_MBUTTONDOWN = 0x0207;
pub const WM_MBUTTONUP = 0x0208;
pub const WM_MBUTTONDBLCLK = 0x0209;
pub const WM_MOUSEWHEEL = 0x020A;
pub const WM_MOUSELEAVE = 0x02A3;
pub const WM_INPUT = 0x00FF;
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_CHAR = 0x0102;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;
pub const WM_SETFOCUS = 0x0007;
pub const WM_KILLFOCUS = 0x0008;
pub const WM_CREATE = 0x0001;
pub const WM_DESTROY = 0x0002;
pub const WM_MOVE = 0x0003;
pub const WM_SIZE = 0x0005;
pub const WM_ACTIVATE = 0x0006;
pub const WM_ENABLE = 0x000A;
pub const WM_PAINT = 0x000F;
pub const WM_CLOSE = 0x0010;
pub const WM_QUIT = 0x0012;
pub const WM_GETMINMAXINFO = 0x0024;
pub const WM_SETICON = 0x0080;
pub const WM_DROPFILES = 0x0233;
pub const WM_SETCURSOR = 0x0020;
pub const WM_DPICHANGED = 0x02E0;
pub const WM_XBUTTONDOWN = 0x020B;
pub const WM_XBUTTONUP = 0x020C;
pub const WM_MOUSEHWHEEL = 0x020E;
pub const WM_SYSCOMMAND = 0x0112;
pub const WM_INPUT_DEVICE_CHANGE = 0x00FE;

pub const SC_KEYMENU = 0xF100;

pub extern "kernel32" fn GetModuleHandleA(lpModuleName: ?LPCSTR) callconv(WINAPI) ?HINSTANCE;

pub const WNDPROC = *const fn (hwnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) LRESULT;

pub const MSG = extern struct {
    hWnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};

pub const CS_VREDRAW = 0x0001;
pub const CS_HREDRAW = 0x0002;
pub const CS_DBLCLKS = 0x0008;
pub const CS_OWNDC = 0x0020;
pub const CS_CLASSDC = 0x0040;
pub const CS_PARENTDC = 0x0080;
pub const CS_NOCLOSE = 0x0200;
pub const CS_SAVEBITS = 0x0800;
pub const CS_BYTEALIGNCLIENT = 0x1000;
pub const CS_BYTEALIGNWINDOW = 0x2000;
pub const CS_GLOBALCLASS = 0x4000;
pub const CS_IME = 0x00010000;
pub const CS_DROPSHADOW = 0x00020000;

pub const WNDCLASSEXA = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXA),
    style: UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?LPCSTR = null,
    lpszClassName: LPCSTR,
    hIconSm: ?HICON = null,
};

pub inline fn GET_X_LPARAM(lparam: LPARAM) i32 {
    return @as(i32, @intCast(@as(i16, @bitCast(@as(u16, @intCast(lparam & 0xffff))))));
}

pub inline fn GET_Y_LPARAM(lparam: LPARAM) i32 {
    return @as(i32, @intCast(@as(i16, @bitCast(@as(u16, @intCast((lparam >> 16) & 0xffff))))));
}

pub inline fn LOWORD(dword: anytype) WORD {
    return @as(WORD, @bitCast(@as(u16, @intCast(dword & 0xffff))));
}

pub inline fn HIWORD(dword: anytype) WORD {
    return @as(WORD, @bitCast(@as(u16, @intCast((dword >> 16) & 0xffff))));
}

pub const SW_HIDE = 0;
pub const SW_SHOWNORMAL = 1;
pub const SW_NORMAL = 1;
pub const SW_SHOWMINIMIZED = 2;
pub const SW_SHOWMAXIMIZED = 3;
pub const SW_MAXIMIZE = 3;
pub const SW_SHOWNOACTIVATE = 4;
pub const SW_SHOW = 5;
pub const SW_MINIMIZE = 6;
pub const SW_SHOWMINNOACTIVE = 7;
pub const SW_SHOWNA = 8;
pub const SW_RESTORE = 9;
pub const SW_SHOWDEFAULT = 10;
pub const SW_FORCEMINIMIZE = 11;

pub extern "user32" fn ShowWindow(hWnd: ?HWND, nCmdShow: u32) callconv(WINAPI) BOOL;

pub extern "user32" fn GetDC(hwnd: ?HWND) callconv(WINAPI) ?HDC;

pub extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: ?HDC) callconv(WINAPI) INT;

pub const DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
pub const DWMWA_WINDOW_CORNER_PREFERENCE = 33;

pub extern "dwmapi" fn DwmSetWindowAttribute(hwnd: ?HWND, dwAttribute: DWORD, pvAttribute: LPCVOID, cbAttribute: DWORD) callconv(WINAPI) HRESULT;

pub extern "user32" fn LoadIconA(hInstance: ?HINSTANCE, lpIconName: ?[*:0]const u8) callconv(WINAPI) ?HICON;

pub extern "user32" fn GetLastError() callconv(WINAPI) DWORD;

pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(WINAPI) void;

pub extern "user32" fn GetKeyState(nVirtKey: i32) callconv(WINAPI) u16;

pub const PFD_TYPE_RGBA: BYTE = 0;
pub const PFD_MAIN_PLANE: BYTE = 0;

pub const PFD_DOUBLEBUFFER = 0x00000001;
pub const PFD_STEREO = 0x00000002;
pub const PFD_DRAW_TO_WINDOW = 0x00000004;
pub const PFD_DRAW_TO_BITMAP = 0x00000008;
pub const PFD_SUPPORT_GDI = 0x00000010;
pub const PFD_SUPPORT_OPENGL = 0x00000020;
pub const PFD_GENERIC_FORMAT = 0x00000040;
pub const PFD_NEED_PALETTE = 0x00000080;
pub const PFD_NEED_SYSTEM_PALETTE = 0x00000100;
pub const PFD_SWAP_EXCHANGE = 0x00000200;
pub const PFD_SWAP_COPY = 0x00000400;
pub const PFD_SWAP_LAYER_BUFFERS = 0x00000800;
pub const PFD_GENERIC_ACCELERATED = 0x00001000;
pub const PFD_SUPPORT_DIRECTDRAW = 0x00002000;
pub const PFD_DIRECT3D_ACCELERATED = 0x00004000;
pub const PFD_SUPPORT_COMPOSITION = 0x00008000;
pub const PFD_DEPTH_DONTCARE = 0x20000000;
pub const PFD_DOUBLEBUFFER_DONTCARE = 0x40000000;
pub const PFD_STEREO_DONTCARE = 0x80000000;

pub const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion: WORD = 0,
    dwFlags: DWORD = 0,
    iPixelType: BYTE = 0,
    cColorBits: BYTE = 0,
    cRedBits: BYTE = 0,
    cRedShift: BYTE = 0,
    cGreenBits: BYTE = 0,
    cGreenShift: BYTE = 0,
    cBlueBits: BYTE = 0,
    cBlueShift: BYTE = 0,
    cAlphaBits: BYTE = 0,
    cAlphaShift: BYTE = 0,
    cAccumBits: BYTE = 0,
    cAccumRedBits: BYTE = 0,
    cAccumGreenBits: BYTE = 0,
    cAccumBlueBits: BYTE = 0,
    cAccumAlphaBits: BYTE = 0,
    cDepthBits: BYTE = 0,
    cStencilBits: BYTE = 0,
    cAuxBuffers: BYTE = 0,
    iLayerType: BYTE = 0,
    bReserved: BYTE = 0,
    dwLayerMask: DWORD = 0,
    dwVisibleMask: DWORD = 0,
    dwDamageMask: DWORD = 0,
};

pub extern "gdi32" fn SetPixelFormat(hdc: ?HDC, iPixelFormat: i32, ppfd: [*c]const PIXELFORMATDESCRIPTOR) callconv(WINAPI) BOOL;

pub extern "gdi32" fn ChoosePixelFormat(hdc: ?HDC, ppfd: [*c]const PIXELFORMATDESCRIPTOR) callconv(WINAPI) i32;

pub extern "gdi32" fn DescribePixelFormat(hdc: ?HDC, iPixelFormat: i32, nBytes: UINT, ppfd: [*c]PIXELFORMATDESCRIPTOR) callconv(WINAPI) i32;

pub extern "opengl32" fn wglCreateContext(hdc: ?HDC) callconv(WINAPI) ?HGLRC;

pub extern "opengl32" fn wglDeleteContext(hdc: ?HGLRC) callconv(WINAPI) BOOL;

pub extern "opengl32" fn wglMakeCurrent(hdc: ?HDC, hglrc: ?HGLRC) callconv(WINAPI) BOOL;

pub extern "opengl32" fn wglGetProcAddress(lpszProc: LPCSTR) callconv(WINAPI) ?PROC;

pub extern "kernel32" fn LoadLibraryA(lpLibFileName: LPCSTR) callconv(WINAPI) ?HMODULE;

pub extern "kernel32" fn FreeLibrary(hLibModule: ?HMODULE) callconv(WINAPI) BOOL;

pub extern "kernel32" fn GetProcAddress(hModule: ?HMODULE, lpProcName: LPCSTR) callconv(WINAPI) ?PROC;

pub extern "gdi32" fn SwapBuffers(hdc: ?HDC) callconv(WINAPI) BOOL;

pub const GWLP_USERDATA: i32 = -21;
pub const GWL_STYLE: i32 = -16;
pub const GWLP_WNDPROC: i32 = -4;

pub extern "user32" fn GetWindowLongA(hWnd: ?HWND, nIndex: i32) callconv(WINAPI) i32;

pub extern "user32" fn SetWindowLongA(hWnd: ?HWND, nIndex: i32, dwNewLong: i32) callconv(WINAPI) i32;

pub extern "user32" fn SetWindowLongPtrA(hWnd: ?HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(WINAPI) LONG_PTR;

pub extern "user32" fn GetWindowLongPtrA(hWnd: ?HWND, nIndex: i32) callconv(WINAPI) LONG_PTR;

pub const MONITOR_DEFAULTTOPRIMARY = 1;
pub const MONITOR_DEFAULTTONEAREST = 2;

pub extern "user32" fn MonitorFromWindow(hwnd: ?HWND, dwFlags: u32) callconv(WINAPI) ?HMONITOR;

pub const MONITORINFO = extern struct {
    cbSize: u32 = @sizeOf(MONITORINFO),
    rcMonitor: RECT = .{},
    rcWork: RECT = .{},
    dwFlags: u32 = 0,
};

pub extern "user32" fn GetMonitorInfoA(hMonitor: ?HMONITOR, lpmi: ?*MONITORINFO) callconv(WINAPI) BOOL;

pub const SWP_NOSIZE = 1;
pub const SWP_NOMOVE = 2;
pub const SWP_NOZORDER = 4;
pub const SWP_NOREDRAW = 8;
pub const SWP_NOACTIVATE = 16;
pub const SWP_DRAWFRAME = 32;
pub const SWP_SHOWWINDOW = 64;
pub const SWP_HIDEWINDOW = 128;
pub const SWP_NOCOPYBITS = 256;
pub const SWP_NOOWNERZORDER = 512;
pub const SWP_NOSENDCHANGING = 1024;
pub const SWP_DEFERERASE = 8192;
pub const SWP_ASYNCWINDOWPOS = 16384;
pub const SWP_FRAMECHANGED = SWP_DRAWFRAME;
pub const SWP_NOREPOSITION = SWP_NOOWNERZORDER;

pub extern "user32" fn SetWindowPos(hWnd: ?HWND, hWndInsertAfter: ?HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: u32) callconv(WINAPI) BOOL;

pub const WINDOWPLACEMENT = extern struct {
    length: u32 = @sizeOf(WINDOWPLACEMENT),
    flags: u32 = 0,
    showCmd: u32 = 0,
    ptMinPosition: POINT = .{},
    ptMaxPosition: POINT = .{},
    rcNormalPosition: RECT = .{},
};

pub extern "user32" fn GetWindowPlacement(hWnd: ?HWND, lpwndpl: ?*WINDOWPLACEMENT) callconv(WINAPI) BOOL;

pub extern "user32" fn SetWindowPlacement(hWnd: ?HWND, lpwndpl: ?*const WINDOWPLACEMENT) callconv(WINAPI) BOOL;

pub extern "user32" fn SetWindowTextA(hWnd: ?HWND, lpString: LPCSTR) callconv(WINAPI) BOOL;

pub extern "xinput1_4" fn XInputEnable(enable: BOOL) callconv(WINAPI) void;

pub const GAMEPAD = extern struct {
    wButtons: WORD,
    bLeftTrigger: BYTE,
    bRightTrigger: BYTE,
    sThumbLX: SHORT,
    sThumbLY: SHORT,
    sThumbRX: SHORT,
    sThumbRY: SHORT,
};

pub const STATE = extern struct {
    dwPacketNumber: DWORD,
    Gamepad: GAMEPAD,
};

pub extern "xinput1_4" fn XInputGetState(dwUserIndex: DWORD, pState: *STATE) callconv(WINAPI) DWORD;

pub const HORZRES = 8;
pub const VERTRES = 10;
pub extern "gdi32" fn GetDeviceCaps(hdc: ?HDC, index: i32) callconv(WINAPI) i32;

pub extern "user32" fn GetWindowRect(hWnd: HWND, lpRect: *RECT) callconv(WINAPI) BOOL;

pub extern "user32" fn GetClientRect(hWnd: ?HWND, lpRect: *RECT) callconv(WINAPI) BOOL;

pub extern "gdi32" fn DeleteDC(hdc: HDC) callconv(WINAPI) BOOL;

pub extern "user32" fn IsWindow(hWnd: ?HWND) callconv(WINAPI) BOOL;

pub extern "user32" fn GetForegroundWindow() callconv(WINAPI) ?HWND;

pub const WA_INACTIVE = 0;

pub const LARGE_INTEGER = extern union {
    u: extern struct { LowPart: DWORD, HighPart: LONG },
    QuadPart: c_longlong,
};

pub extern "winmm" fn timeBeginPeriod(uPeriod: u32) callconv(WINAPI) u32;

pub extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *LARGE_INTEGER) callconv(WINAPI) BOOL;

pub extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *LARGE_INTEGER) callconv(WINAPI) BOOL;

pub extern "kernel32" fn Sleep(dwMilliseconds: DWORD) callconv(WINAPI) void;

pub const DISPLAY_DEVICEA = extern struct {
    cb: DWORD = @sizeOf(DISPLAY_DEVICEA),
    DeviceName: [32]CHAR = .{0} ** 32,
    DeviceString: [128]CHAR = .{0} ** 128,
    StateFlags: DWORD = 0,
    DeviceID: [128]CHAR = .{0} ** 128,
    DeviceKey: [128]CHAR = .{0} ** 128,
};

pub extern "user32" fn MonitorFromPoint(pt: POINT, dwFlags: DWORD) callconv(WINAPI) HMONITOR;

pub const MONITORENUMPROC = *const fn (HMONITOR, HDC, *RECT, LPARAM) callconv(WINAPI) BOOL;

pub extern "user32" fn EnumDisplayMonitors(hdc: ?HDC, lprcClip: ?*RECT, lpfnEnum: MONITORENUMPROC, dwData: LPARAM) callconv(WINAPI) BOOL;

pub extern "user32" fn EnumDisplayDevicesA(lpDevice: ?LPCSTR, iDevNum: DWORD, lpDisplayDevice: *DISPLAY_DEVICEA, dwFlags: DWORD) callconv(WINAPI) BOOL;

pub const SM_CXSCREEN = 0;
pub const SM_CYSCREEN = 1;
pub const LOGPIXELSX = 88;
pub const LOGPIXELSY = 90;

pub extern "user32" fn GetSystemMetrics(nIndex: i32) callconv(WINAPI) i32;

pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(WINAPI) BOOL;

pub extern "user32" fn ScreenToClient(hWnd: HWND, lpPoint: *POINT) callconv(WINAPI) BOOL;

pub const RAWINPUTDEVICE = extern struct {
    usUsagePage: USHORT,
    usUsage: USHORT,
    dwFlags: DWORD,
    hwndTarget: ?HWND,
};

pub extern "user32" fn ClientToScreen(hWnd: ?HWND, lpPoint: *POINT) callconv(WINAPI) BOOL;

pub extern "user32" fn ClipCursor(lpRect: ?*const RECT) callconv(WINAPI) BOOL;

pub extern "user32" fn RegisterRawInputDevices(pRawInputDevices: [*]const RAWINPUTDEVICE, uiNumDevices: UINT, cbSize: UINT) callconv(WINAPI) BOOL;

pub const OCR_NORMAL = 32512;
pub const OCR_IBEAM = 32513;
pub const OCR_WAIT = 32514;
pub const OCR_CROSS = 32515;
pub const OCR_UP = 32516;
pub const OCR_SIZE = 32640;
pub const OCR_ICON = 32641;
pub const OCR_SIZENWSE = 32642;
pub const OCR_SIZENESW = 32643;
pub const OCR_SIZEWE = 32644;
pub const OCR_SIZENS = 32645;
pub const OCR_SIZEALL = 32646;
pub const OCR_ICOCUR = 32647;
pub const OCR_NO = 32648;
pub const OCR_HAND = 32649;

pub extern "user32" fn IsWindowVisible(hWnd: ?HWND) callconv(WINAPI) BOOL;

pub const ERROR_DEVICE_NOT_CONNECTED = 1167;
pub const ERROR_EMPTY = 4306;

pub const XINPUT_KEYSTROKE_KEYDOWN = 0x0001;
pub const XINPUT_KEYSTROKE_KEYUP = 0x0002;
pub const XINPUT_KEYSTROKE_REPEAT = 0x0004;

pub const XINPUT_KEYSTROKE = extern struct {
    VirtualKey: WORD,
    Unicode: WCHAR,
    Flags: WORD,
    UserIndex: BYTE,
    HidCode: BYTE,
};

pub extern "user32" fn GetKeyNameTextA(lParam: LONG, lpString: LPSTR, cchSize: i32) callconv(WINAPI) i32;

pub extern "user32" fn CharLowerBuffA(lpsz: LPSTR, cchLength: DWORD) callconv(WINAPI) DWORD;

pub extern "user32" fn MapVirtualKeyA(uCode: UINT, uMapType: UINT) callconv(WINAPI) UINT;

pub extern "user32" fn ToAscii(uVirtKey: UINT, uScanCode: UINT, lpKeyState: ?[*]const u8, lpChar: *WORD, uFlags: UINT) callconv(WINAPI) i32;

pub const MAPVK_VK_TO_CHAR = 2;

pub const VK_SHIFT = 0x10;
pub const VK_CAPITAL = 0x14;
pub const VK_NUMLOCK = 0x90;

pub extern "user32" fn PostMessageA(hWnd: ?HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) BOOL;

pub extern "user32" fn MsgWaitForMultipleObjects(nCount: DWORD, pHandles: ?[*]HANDLE, fWaitAll: BOOL, dwMilliseconds: DWORD, dwWakeMask: DWORD) callconv(WINAPI) DWORD;

pub const QS_KEY = 0x0001;
pub const QS_MOUSEMOVE = 0x0002;
pub const QS_MOUSEBUTTON = 0x0004;
pub const QS_POSTMESSAGE = 0x0008;
pub const QS_TIMER = 0x0010;
pub const QS_PAINT = 0x0020;
pub const QS_SENDMESSAGE = 0x0040;
pub const QS_HOTKEY = 0x0080;
pub const QS_ALLPOSTMESSAGE = 0x0100;
pub const QS_RAWINPUT = 0x0400;
pub const QS_TOUCH = 0x0800;
pub const QS_POINTER = 0x1000;

pub const QS_ALLINPUT = QS_INPUT |
    QS_POSTMESSAGE |
    QS_TIMER |
    QS_PAINT |
    QS_HOTKEY |
    QS_SENDMESSAGE;

pub const QS_MOUSE = QS_MOUSEMOVE | QS_MOUSEBUTTON;

pub const QS_INPUT = QS_MOUSE |
    QS_KEY |
    QS_RAWINPUT |
    QS_TOUCH |
    QS_POINTER;

pub extern "shell32" fn DragAcceptFiles(hWnd: ?HWND, fAccept: BOOL) callconv(WINAPI) void;

pub extern "user32" fn SetClassLongPtrA(hWnd: ?HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(WINAPI) ULONG_PTR;

pub extern "user32" fn DestroyIcon(hIcon: HICON) callconv(WINAPI) BOOL;

pub extern "user32" fn SetCursor(hCursor: ?HCURSOR) callconv(WINAPI) HCURSOR;

pub extern "user32" fn DestroyCursor(hCursor: HCURSOR) callconv(WINAPI) BOOL;

pub const GCLP_MENUNAME = -8;
pub const GCLP_HBRBACKGROUND = -10;
pub const GCLP_HCURSOR = -12;
pub const GCLP_HICON = -14;
pub const GCLP_HMODULE = -16;
pub const GCLP_WNDPROC = -24;
pub const GCLP_HICONSM = -34;

pub fn MAKEINTRESOURCEA(i: anytype) LPSTR {
    const x = @as(WORD, @intCast(i));
    const y = @as(ULONG_PTR, x);
    const z = @as(LPSTR, @ptrFromInt(y));
    return z;
}

pub const FXPT2DOT30 = c_long;

pub const CIEXYZ = extern struct {
    ciexyzX: FXPT2DOT30 = 0,
    ciexyzY: FXPT2DOT30 = 0,
    ciexyzZ: FXPT2DOT30 = 0,
};

pub const CIEXYZTRIPLE = extern struct {
    ciexyzRed: CIEXYZ = .{},
    ciexyzGreen: CIEXYZ = .{},
    ciexyzBlue: CIEXYZ = .{},
};

pub const BITMAPV5HEADER = extern struct {
    bV5Size: DWORD = @sizeOf(BITMAPV5HEADER),
    bV5Width: LONG = 0,
    bV5Height: LONG = 0,
    bV5Planes: WORD = 0,
    bV5BitCount: WORD = 0,
    bV5Compression: DWORD = 0,
    bV5SizeImage: DWORD = 0,
    bV5XPelsPerMeter: LONG = 0,
    bV5YPelsPerMeter: LONG = 0,
    bV5ClrUsed: DWORD = 0,
    bV5ClrImportant: DWORD = 0,
    bV5RedMask: DWORD = 0,
    bV5GreenMask: DWORD = 0,
    bV5BlueMask: DWORD = 0,
    bV5AlphaMask: DWORD = 0,
    bV5CSType: DWORD = 0,
    bV5Endpoints: CIEXYZTRIPLE = .{},
    bV5GammaRed: DWORD = 0,
    bV5GammaGreen: DWORD = 0,
    bV5GammaBlue: DWORD = 0,
    bV5Intent: DWORD = 0,
    bV5ProfileData: DWORD = 0,
    bV5ProfileSize: DWORD = 0,
    bV5Reserved: DWORD = 0,
};

pub const BITMAPINFOHEADER = extern struct {
    biSize: DWORD,
    biWidth: LONG,
    biHeight: LONG,
    biPlanes: WORD,
    biBitCount: WORD,
    biCompression: DWORD,
    biSizeImage: DWORD,
    biXPelsPerMeter: LONG,
    biYPelsPerMeter: LONG,
    biClrUsed: DWORD,
    biClrImportant: DWORD,
};

pub const RGBQUAD = extern struct {
    rgbBlue: BYTE,
    rgbGreen: BYTE,
    rgbRed: BYTE,
    rgbReserved: BYTE,
};

pub const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]RGBQUAD,
};

pub const DIB_RGB_COLORS = 0;
pub const DIB_PAL_COLORS = 1;

pub extern "gdi32" fn CreateDIBSection(hdc: ?HDC, pbmi: *const BITMAPINFO, usage: UINT, ppvBits: *?*anyopaque, hSection: ?HANDLE, offset: DWORD) callconv(WINAPI) HBITMAP;

pub extern "gdi32" fn CreateBitmap(nWidth: i32, nHeight: i32, nPlanes: UINT, nBitCount: UINT, lpBits: ?*const anyopaque) callconv(WINAPI) HBITMAP;

pub const ICONINFO = extern struct {
    fIcon: BOOL = 0,
    xHotspot: DWORD = 0,
    yHotspot: DWORD = 0,
    hbmMask: ?HBITMAP = null,
    hbmColor: ?HBITMAP = null,
};

pub extern "user32" fn CreateIconIndirect(piconinfo: *ICONINFO) callconv(WINAPI) HICON;

pub extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(WINAPI) BOOL;

pub extern "user32" fn SetCursorPos(X: i32, Y: i32) callconv(WINAPI) BOOL;

pub const MINMAXINFO = extern struct {
    ptReserved: POINT,
    ptMaxSize: POINT,
    ptMaxPosition: POINT,
    ptMinTrackSize: POINT,
    ptMaxTrackSize: POINT,
};

pub const USER_DEFAULT_SCREEN_DPI = 96;

pub extern "user32" fn GetDpiForWindow(hwnd: HWND) callconv(WINAPI) UINT;

pub const HTCLIENT = 1;

pub extern "user32" fn ShowCursor(bShow: BOOL) callconv(WINAPI) i32;

pub extern "user32" fn ValidateRgn(hwnd: HWND, hrgn: ?HRGN) callconv(WINAPI) BOOL;

pub const WHEEL_DELTA = 120;

pub const XBUTTON1 = 1;
pub const XBUTTON2 = 2;

pub const VK_PROCESSKEY = 229;
pub const VK_F4 = 115;

pub extern "user32" fn GetMessageTime() callconv(WINAPI) i32;

pub const KF_UP = 0x8000;