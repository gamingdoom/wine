/*
 * USER driver support
 *
 * Copyright 2000, 2005 Alexandre Julliard
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 */

#include <stdarg.h>
#include <stdio.h>
#include <wchar.h>

#include "windef.h"
#include "winbase.h"
#include "winnls.h"
#include "wingdi.h"
#include "winuser.h"
#include "wine/debug.h"
#include "wine/gdi_driver.h"

#include "user_private.h"
#include "controls.h"

WINE_DEFAULT_DEBUG_CHANNEL(user);
WINE_DECLARE_DEBUG_CHANNEL(winediag);

static USER_DRIVER null_driver, lazy_load_driver;

const USER_DRIVER *USER_Driver = &lazy_load_driver;
static char driver_load_error[80];

static BOOL CDECL nodrv_CreateWindow( HWND hwnd );

static BOOL load_desktop_driver( HWND hwnd, HMODULE *module )
{
    BOOL ret = FALSE;
    HKEY hkey;
    DWORD size;
    WCHAR path[MAX_PATH];
    WCHAR key[ARRAY_SIZE(L"System\\CurrentControlSet\\Control\\Video\\{}\\0000") + 40];
    UINT guid_atom;

    USER_CheckNotLock();

    strcpy( driver_load_error, "The explorer process failed to start." );  /* default error */
    wait_graphics_driver_ready();

    guid_atom = HandleToULong( GetPropW( hwnd, L"__wine_display_device_guid" ));
    lstrcpyW( key, L"System\\CurrentControlSet\\Control\\Video\\{" );
    if (!GlobalGetAtomNameW( guid_atom, key + lstrlenW(key), 40 )) return 0;
    lstrcatW( key, L"}\\0000" );
    if (RegOpenKeyW( HKEY_LOCAL_MACHINE, key, &hkey )) return 0;
    size = sizeof(path);
    if (!RegQueryValueExW( hkey, L"GraphicsDriver", NULL, NULL, (BYTE *)path, &size ))
    {
        if ((ret = !wcscmp( path, L"null" ))) *module = NULL;
        else ret = (*module = LoadLibraryW( path )) != NULL;
        if (!ret) ERR( "failed to load %s\n", debugstr_w(path) );
        TRACE( "%s %p\n", debugstr_w(path), *module );
    }
    else
    {
        size = sizeof(driver_load_error);
        *module = NULL;
        RegQueryValueExA( hkey, "DriverError", NULL, NULL, (BYTE *)driver_load_error, &size );
    }
    RegCloseKey( hkey );
    return ret;
}

/* load the graphics driver */
static const USER_DRIVER *load_driver(void)
{
    void *ptr;
    HMODULE graphics_driver = NULL;
    USER_DRIVER *driver, *prev;

    driver = HeapAlloc( GetProcessHeap(), 0, sizeof(*driver) );
    *driver = null_driver;

    if (!load_desktop_driver( GetDesktopWindow(), &graphics_driver ))
    {
        USEROBJECTFLAGS flags;
        HWINSTA winstation;

        winstation = NtUserGetProcessWindowStation();
        if (!GetUserObjectInformationA(winstation, UOI_FLAGS, &flags, sizeof(flags), NULL)
            || (flags.dwFlags & WSF_VISIBLE))
            driver->pCreateWindow = nodrv_CreateWindow;
    }
    else if (graphics_driver)
    {
#define GET_USER_FUNC(name) \
    do { if ((ptr = GetProcAddress( graphics_driver, #name ))) driver->p##name = ptr; } while(0)

        GET_USER_FUNC(ActivateKeyboardLayout);
        GET_USER_FUNC(Beep);
        GET_USER_FUNC(GetKeyNameText);
        GET_USER_FUNC(GetKeyboardLayoutList);
        GET_USER_FUNC(MapVirtualKeyEx);
        GET_USER_FUNC(RegisterHotKey);
        GET_USER_FUNC(ToUnicodeEx);
        GET_USER_FUNC(UnregisterHotKey);
        GET_USER_FUNC(VkKeyScanEx);
        GET_USER_FUNC(DestroyCursorIcon);
        GET_USER_FUNC(SetCursor);
        GET_USER_FUNC(GetCursorPos);
        GET_USER_FUNC(SetCursorPos);
        GET_USER_FUNC(ClipCursor);
        GET_USER_FUNC(UpdateClipboard);
        GET_USER_FUNC(ChangeDisplaySettingsEx);
        GET_USER_FUNC(EnumDisplayMonitors);
        GET_USER_FUNC(EnumDisplaySettingsEx);
        GET_USER_FUNC(GetMonitorInfo);
        GET_USER_FUNC(CreateDesktopWindow);
        GET_USER_FUNC(CreateWindow);
        GET_USER_FUNC(DestroyWindow);
        GET_USER_FUNC(FlashWindowEx);
        GET_USER_FUNC(GetDC);
        GET_USER_FUNC(MsgWaitForMultipleObjectsEx);
        GET_USER_FUNC(ReleaseDC);
        GET_USER_FUNC(ScrollDC);
        GET_USER_FUNC(SetCapture);
        GET_USER_FUNC(SetFocus);
        GET_USER_FUNC(SetLayeredWindowAttributes);
        GET_USER_FUNC(SetParent);
        GET_USER_FUNC(SetWindowRgn);
        GET_USER_FUNC(SetWindowIcon);
        GET_USER_FUNC(SetWindowStyle);
        GET_USER_FUNC(SetWindowText);
        GET_USER_FUNC(ShowWindow);
        GET_USER_FUNC(SysCommand);
        GET_USER_FUNC(UpdateLayeredWindow);
        GET_USER_FUNC(WindowMessage);
        GET_USER_FUNC(WindowPosChanging);
        GET_USER_FUNC(WindowPosChanged);
        GET_USER_FUNC(SystemParametersInfo);
        GET_USER_FUNC(UpdateCandidatePos);
        GET_USER_FUNC(ThreadDetach);
#undef GET_USER_FUNC
    }

    prev = InterlockedCompareExchangePointer( (void **)&USER_Driver, driver, &lazy_load_driver );
    if (prev != &lazy_load_driver)
    {
        /* another thread beat us to it */
        HeapFree( GetProcessHeap(), 0, driver );
        driver = prev;
    }
    else LdrAddRefDll( 0, graphics_driver );

    __wine_set_display_driver( graphics_driver );
    register_builtin_classes();

    return driver;
}

/* unload the graphics driver on process exit */
void USER_unload_driver(void)
{
    USER_DRIVER *prev;
    /* make sure we don't try to call the driver after it has been detached */
    prev = InterlockedExchangePointer( (void **)&USER_Driver, &null_driver );
    if (prev != &lazy_load_driver && prev != &null_driver)
        HeapFree( GetProcessHeap(), 0, prev );
}


/**********************************************************************
 * Null user driver
 *
 * These are fallbacks for entry points that are not implemented in the real driver.
 */

static BOOL CDECL nulldrv_ActivateKeyboardLayout( HKL layout, UINT flags )
{
    return TRUE;
}

static void CDECL nulldrv_Beep(void)
{
}

static UINT CDECL nulldrv_GetKeyboardLayoutList( INT size, HKL *layouts )
{
    return ~0; /* use default implementation */
}

static INT CDECL nulldrv_GetKeyNameText( LONG lparam, LPWSTR buffer, INT size )
{
    return -1; /* use default implementation */
}

static UINT CDECL nulldrv_MapVirtualKeyEx( UINT code, UINT type, HKL layout )
{
    return -1; /* use default implementation */
}

static BOOL CDECL nulldrv_RegisterHotKey( HWND hwnd, UINT modifiers, UINT vk )
{
    return TRUE;
}

static INT CDECL nulldrv_ToUnicodeEx( UINT virt, UINT scan, const BYTE *state, LPWSTR str,
                                      int size, UINT flags, HKL layout )
{
    return -2; /* use default implementation */
}

static void CDECL nulldrv_UnregisterHotKey( HWND hwnd, UINT modifiers, UINT vk )
{
}

static SHORT CDECL nulldrv_VkKeyScanEx( WCHAR ch, HKL layout )
{
    return -256; /* use default implementation */
}

static void CDECL nulldrv_DestroyCursorIcon( HCURSOR cursor )
{
}

static void CDECL nulldrv_SetCursor( HCURSOR cursor )
{
}

static BOOL CDECL nulldrv_GetCursorPos( LPPOINT pt )
{
    return TRUE;
}

static BOOL CDECL nulldrv_SetCursorPos( INT x, INT y )
{
    return TRUE;
}

static BOOL CDECL nulldrv_ClipCursor( LPCRECT clip )
{
    return TRUE;
}

static void CDECL nulldrv_UpdateClipboard(void)
{
}

static LONG CDECL nulldrv_ChangeDisplaySettingsEx( LPCWSTR name, LPDEVMODEW mode, HWND hwnd,
                                             DWORD flags, LPVOID lparam )
{
    return DISP_CHANGE_FAILED;
}

static BOOL CDECL nulldrv_EnumDisplaySettingsEx( LPCWSTR name, DWORD num, LPDEVMODEW mode, DWORD flags )
{
    return FALSE;
}

static BOOL CDECL nulldrv_CreateDesktopWindow( HWND hwnd )
{
    return TRUE;
}

static BOOL CDECL nodrv_CreateWindow( HWND hwnd )
{
    static int warned;
    HWND parent = GetAncestor( hwnd, GA_PARENT );

    /* HWND_MESSAGE windows don't need a graphics driver */
    if (!parent || parent == get_user_thread_info()->msg_window) return TRUE;
    if (warned++) return FALSE;

    ERR_(winediag)( "Application tried to create a window, but no driver could be loaded.\n" );
    if (driver_load_error[0]) ERR_(winediag)( "%s\n", driver_load_error );
    return FALSE;
}

static BOOL CDECL nulldrv_CreateWindow( HWND hwnd )
{
    return TRUE;
}

static void CDECL nulldrv_DestroyWindow( HWND hwnd )
{
}

static void CDECL nulldrv_FlashWindowEx( FLASHWINFO *info )
{
}

static void CDECL nulldrv_GetDC( HDC hdc, HWND hwnd, HWND top_win, const RECT *win_rect,
                                 const RECT *top_rect, DWORD flags )
{
}

static DWORD CDECL nulldrv_MsgWaitForMultipleObjectsEx( DWORD count, const HANDLE *handles, DWORD timeout,
                                                        DWORD mask, DWORD flags )
{
    if (!count && !timeout) return WAIT_TIMEOUT;
    return WaitForMultipleObjectsEx( count, handles, flags & MWMO_WAITALL,
                                     timeout, flags & MWMO_ALERTABLE );
}

static void CDECL nulldrv_ReleaseDC( HWND hwnd, HDC hdc )
{
}

static BOOL CDECL nulldrv_ScrollDC( HDC hdc, INT dx, INT dy, HRGN update )
{
    RECT rect;

    GetClipBox( hdc, &rect );
    return BitBlt( hdc, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
                   hdc, rect.left - dx, rect.top - dy, SRCCOPY );
}

static void CDECL nulldrv_SetCapture( HWND hwnd, UINT flags )
{
}

static void CDECL nulldrv_SetFocus( HWND hwnd )
{
}

static void CDECL nulldrv_SetLayeredWindowAttributes( HWND hwnd, COLORREF key, BYTE alpha, DWORD flags )
{
}

static void CDECL nulldrv_SetParent( HWND hwnd, HWND parent, HWND old_parent )
{
}

static void CDECL nulldrv_SetWindowRgn( HWND hwnd, HRGN hrgn, BOOL redraw )
{
}

static void CDECL nulldrv_SetWindowIcon( HWND hwnd, UINT type, HICON icon )
{
}

static void CDECL nulldrv_SetWindowStyle( HWND hwnd, INT offset, STYLESTRUCT *style )
{
}

static void CDECL nulldrv_SetWindowText( HWND hwnd, LPCWSTR text )
{
}

static UINT CDECL nulldrv_ShowWindow( HWND hwnd, INT cmd, RECT *rect, UINT swp )
{
    return ~0; /* use default implementation */
}

static LRESULT CDECL nulldrv_SysCommand( HWND hwnd, WPARAM wparam, LPARAM lparam )
{
    return -1;
}

static BOOL CDECL nulldrv_UpdateLayeredWindow( HWND hwnd, const UPDATELAYEREDWINDOWINFO *info,
                                               const RECT *window_rect )
{
    return TRUE;
}

static LRESULT CDECL nulldrv_WindowMessage( HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam )
{
    return 0;
}

static BOOL CDECL nulldrv_WindowPosChanging( HWND hwnd, HWND insert_after, UINT swp_flags,
                                             const RECT *window_rect, const RECT *client_rect,
                                             RECT *visible_rect, struct window_surface **surface )
{
    return FALSE;
}

static void CDECL nulldrv_WindowPosChanged( HWND hwnd, HWND insert_after, UINT swp_flags,
                                            const RECT *window_rect, const RECT *client_rect,
                                            const RECT *visible_rect, const RECT *valid_rects,
                                            struct window_surface *surface )
{
}

static BOOL CDECL nulldrv_SystemParametersInfo( UINT action, UINT int_param, void *ptr_param, UINT flags )
{
    return FALSE;
}

static void CDECL nulldrv_UpdateCandidatePos( HWND hwnd, const RECT *caret_rect )
{
}

static void CDECL nulldrv_ThreadDetach( void )
{
}

static USER_DRIVER null_driver =
{
    /* keyboard functions */
    nulldrv_ActivateKeyboardLayout,
    nulldrv_Beep,
    nulldrv_GetKeyNameText,
    nulldrv_GetKeyboardLayoutList,
    nulldrv_MapVirtualKeyEx,
    nulldrv_RegisterHotKey,
    nulldrv_ToUnicodeEx,
    nulldrv_UnregisterHotKey,
    nulldrv_VkKeyScanEx,
    /* cursor/icon functions */
    nulldrv_DestroyCursorIcon,
    nulldrv_SetCursor,
    nulldrv_GetCursorPos,
    nulldrv_SetCursorPos,
    nulldrv_ClipCursor,
    /* clipboard functions */
    nulldrv_UpdateClipboard,
    /* display modes */
    nulldrv_ChangeDisplaySettingsEx,
    nulldrv_EnumDisplayMonitors,
    nulldrv_EnumDisplaySettingsEx,
    nulldrv_GetMonitorInfo,
    /* windowing functions */
    nulldrv_CreateDesktopWindow,
    nulldrv_CreateWindow,
    nulldrv_DestroyWindow,
    nulldrv_FlashWindowEx,
    nulldrv_GetDC,
    nulldrv_MsgWaitForMultipleObjectsEx,
    nulldrv_ReleaseDC,
    nulldrv_ScrollDC,
    nulldrv_SetCapture,
    nulldrv_SetFocus,
    nulldrv_SetLayeredWindowAttributes,
    nulldrv_SetParent,
    nulldrv_SetWindowRgn,
    nulldrv_SetWindowIcon,
    nulldrv_SetWindowStyle,
    nulldrv_SetWindowText,
    nulldrv_ShowWindow,
    nulldrv_SysCommand,
    nulldrv_UpdateLayeredWindow,
    nulldrv_WindowMessage,
    nulldrv_WindowPosChanging,
    nulldrv_WindowPosChanged,
    /* system parameters */
    nulldrv_SystemParametersInfo,
    /* candidate pos functions */
    nulldrv_UpdateCandidatePos,
    /* thread management */
    nulldrv_ThreadDetach
};

/* this line exists so that git won't apply this diff in the wrong place */

/**********************************************************************
 * Lazy loading user driver
 *
 * Initial driver used before another driver is loaded.
 * Each entry point simply loads the real driver and chains to it.
 */

static BOOL CDECL loaderdrv_ActivateKeyboardLayout( HKL layout, UINT flags )
{
    return load_driver()->pActivateKeyboardLayout( layout, flags );
}

static void CDECL loaderdrv_Beep(void)
{
    load_driver()->pBeep();
}

static INT CDECL loaderdrv_GetKeyNameText( LONG lparam, LPWSTR buffer, INT size )
{
    return load_driver()->pGetKeyNameText( lparam, buffer, size );
}

static UINT CDECL loaderdrv_GetKeyboardLayoutList( INT size, HKL *layouts )
{
    return load_driver()->pGetKeyboardLayoutList( size, layouts );
}

static UINT CDECL loaderdrv_MapVirtualKeyEx( UINT code, UINT type, HKL layout )
{
    return load_driver()->pMapVirtualKeyEx( code, type, layout );
}

static BOOL CDECL loaderdrv_RegisterHotKey( HWND hwnd, UINT modifiers, UINT vk )
{
    return load_driver()->pRegisterHotKey( hwnd, modifiers, vk );
}

static INT CDECL loaderdrv_ToUnicodeEx( UINT virt, UINT scan, const BYTE *state, LPWSTR str,
                                  int size, UINT flags, HKL layout )
{
    return load_driver()->pToUnicodeEx( virt, scan, state, str, size, flags, layout );
}

static void CDECL loaderdrv_UnregisterHotKey( HWND hwnd, UINT modifiers, UINT vk )
{
    load_driver()->pUnregisterHotKey( hwnd, modifiers, vk );
}

static SHORT CDECL loaderdrv_VkKeyScanEx( WCHAR ch, HKL layout )
{
    return load_driver()->pVkKeyScanEx( ch, layout );
}

static void CDECL loaderdrv_SetCursor( HCURSOR cursor )
{
    load_driver()->pSetCursor( cursor );
}

static BOOL CDECL loaderdrv_GetCursorPos( LPPOINT pt )
{
    return load_driver()->pGetCursorPos( pt );
}

static BOOL CDECL loaderdrv_SetCursorPos( INT x, INT y )
{
    return load_driver()->pSetCursorPos( x, y );
}

static BOOL CDECL loaderdrv_ClipCursor( LPCRECT clip )
{
    return load_driver()->pClipCursor( clip );
}

static void CDECL loaderdrv_UpdateClipboard(void)
{
    load_driver()->pUpdateClipboard();
}

static LONG CDECL loaderdrv_ChangeDisplaySettingsEx( LPCWSTR name, LPDEVMODEW mode, HWND hwnd,
                                                     DWORD flags, LPVOID lparam )
{
    return load_driver()->pChangeDisplaySettingsEx( name, mode, hwnd, flags, lparam );
}

static BOOL CDECL loaderdrv_EnumDisplayMonitors( HDC hdc, LPRECT rect, MONITORENUMPROC proc, LPARAM lp )
{
    return load_driver()->pEnumDisplayMonitors( hdc, rect, proc, lp );
}

static BOOL CDECL loaderdrv_EnumDisplaySettingsEx( LPCWSTR name, DWORD num, LPDEVMODEW mode, DWORD flags )
{
    return load_driver()->pEnumDisplaySettingsEx( name, num, mode, flags );
}

static BOOL CDECL loaderdrv_GetMonitorInfo( HMONITOR handle, LPMONITORINFO info )
{
    return load_driver()->pGetMonitorInfo( handle, info );
}

static BOOL CDECL loaderdrv_CreateDesktopWindow( HWND hwnd )
{
    return load_driver()->pCreateDesktopWindow( hwnd );
}

static BOOL CDECL loaderdrv_CreateWindow( HWND hwnd )
{
    return load_driver()->pCreateWindow( hwnd );
}

static void CDECL loaderdrv_FlashWindowEx( FLASHWINFO *info )
{
    load_driver()->pFlashWindowEx( info );
}

static void CDECL loaderdrv_GetDC( HDC hdc, HWND hwnd, HWND top_win, const RECT *win_rect,
                                   const RECT *top_rect, DWORD flags )
{
    load_driver()->pGetDC( hdc, hwnd, top_win, win_rect, top_rect, flags );
}

static void CDECL loaderdrv_SetLayeredWindowAttributes( HWND hwnd, COLORREF key, BYTE alpha, DWORD flags )
{
    load_driver()->pSetLayeredWindowAttributes( hwnd, key, alpha, flags );
}

static void CDECL loaderdrv_SetWindowRgn( HWND hwnd, HRGN hrgn, BOOL redraw )
{
    load_driver()->pSetWindowRgn( hwnd, hrgn, redraw );
}

static BOOL CDECL loaderdrv_UpdateLayeredWindow( HWND hwnd, const UPDATELAYEREDWINDOWINFO *info,
                                                 const RECT *window_rect )
{
    return load_driver()->pUpdateLayeredWindow( hwnd, info, window_rect );
}

static void CDECL loaderdrv_UpdateCandidatePos( HWND hwnd, const RECT *caret_rect )
{
    load_driver()->pUpdateCandidatePos( hwnd, caret_rect );
}

static USER_DRIVER lazy_load_driver =
{
    /* keyboard functions */
    loaderdrv_ActivateKeyboardLayout,
    loaderdrv_Beep,
    loaderdrv_GetKeyNameText,
    loaderdrv_GetKeyboardLayoutList,
    loaderdrv_MapVirtualKeyEx,
    loaderdrv_RegisterHotKey,
    loaderdrv_ToUnicodeEx,
    loaderdrv_UnregisterHotKey,
    loaderdrv_VkKeyScanEx,
    /* cursor/icon functions */
    nulldrv_DestroyCursorIcon,
    loaderdrv_SetCursor,
    loaderdrv_GetCursorPos,
    loaderdrv_SetCursorPos,
    loaderdrv_ClipCursor,
    /* clipboard functions */
    loaderdrv_UpdateClipboard,
    /* display modes */
    loaderdrv_ChangeDisplaySettingsEx,
    loaderdrv_EnumDisplayMonitors,
    loaderdrv_EnumDisplaySettingsEx,
    loaderdrv_GetMonitorInfo,
    /* windowing functions */
    loaderdrv_CreateDesktopWindow,
    loaderdrv_CreateWindow,
    nulldrv_DestroyWindow,
    loaderdrv_FlashWindowEx,
    loaderdrv_GetDC,
    nulldrv_MsgWaitForMultipleObjectsEx,
    nulldrv_ReleaseDC,
    nulldrv_ScrollDC,
    nulldrv_SetCapture,
    nulldrv_SetFocus,
    loaderdrv_SetLayeredWindowAttributes,
    nulldrv_SetParent,
    loaderdrv_SetWindowRgn,
    nulldrv_SetWindowIcon,
    nulldrv_SetWindowStyle,
    nulldrv_SetWindowText,
    nulldrv_ShowWindow,
    nulldrv_SysCommand,
    loaderdrv_UpdateLayeredWindow,
    nulldrv_WindowMessage,
    nulldrv_WindowPosChanging,
    nulldrv_WindowPosChanged,
    /* system parameters */
    nulldrv_SystemParametersInfo,
    /* candidate pos functions */
    loaderdrv_UpdateCandidatePos,
    /* thread management */
    nulldrv_ThreadDetach
};

/* this line exists so that git won't apply this diff in the wrong place */
