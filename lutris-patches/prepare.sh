#!/bin/bash

set -e

GAME_PATCH=1
WINEX11_PATCH=1
CORE_PATCH=1
HOTFIX_PATCH=1
MFPLAT_PATCH=0
PERFORMANCE_PATCH=1
REVERT_PATCH=1

highlight_start='\033[7m'
highlight_end='\033[0m'

if [ $1 = fshack ]; then
    FSHACK=1
fi

if [ $1 = pa ]; then
    FSHACK=1
    PA_ENABLE=1
fi

### (1) PREP SECTION ###

    #WINE STAGING
    cd wine-staging-src
    git reset --hard HEAD
    git clean -dfx

    # faudio revert fix in staging:
    patch -Np1 < ../patches/hotfixes/staging/x3daudio_staging_revert.patch

    echo -e ""$highlight_start"Syscall emu"$highlight_end""
    patch -Np1 < ../patches/core/29-stg_syscall_emu-009.patch

    cd ..

### END PREP SECTION ###

### (2) WINE PATCHING ###

    cd wine-src
    git reset --hard HEAD
    git clean -dfx

### (2-1) PROBLEMATIC COMMIT REVERT SECTION ###

if [ $REVERT_PATCH = 1 ]; then

    echo -e ""$highlight_start"revert faudio updates -- WINE faudio does not have WMA decoding (notably needed for Skyrim voices) so we still need to provide our own with gstreamer support"$highlight_end""
    git revert --no-commit a80c5491600c00a54dfc8251a75706ce86d2a08f
    git revert --no-commit 22c26a2dde318b5b370fc269cab871e5a8bc4231
    patch -RNp1 < ../patches/hotfixes/pending/revert-d8be858-faudio.patch

fi

### END PROBLEMATIC COMMIT REVERT SECTION ###


### (2-2) WINE STAGING APPLY SECTION ###

    # these cause window freezes/hangs with origin
    # -W winex11-_NET_ACTIVE_WINDOW \
    # -W winex11-WM_WINDOWPOSCHANGING \

    # This was found to cause hangs in various games
    # Notably DOOM Eternal and Resident Evil Village
    # -W ntdll-NtAlertThreadByThreadId

    # Sancreed — 11/21/2021
    # Heads up, it appears that a bunch of Ubisoft Connect games (3/3 I had installed and could test) will crash
    # almost immediately on newer Wine Staging/TKG inside pe_load_debug_info function unless the dbghelp-Debug_Symbols staging # patchset is disabled.
    # -W dbghelp-Debug_Symbols

    # Disable when using external FAudio
    # -W xactengine3_7-callbacks \

    if [ $PA_ENABLE = 1 ]; then
        echo -e ""$highlight_start"applying staging patches"$highlight_end""
        ../wine-staging-src/patches/patchinstall.sh DESTDIR="." --all \
        -W winex11-_NET_ACTIVE_WINDOW \
        -W winex11-WM_WINDOWPOSCHANGING \
        -W winex11-MWM_Decorations \
        -W winex11-key_translation \
        -W dbghelp-Debug_Symbols \
        -W xactengine3_7-callbacks \
        -W winemenubuilder-integration \
        -W dwrite-FontFallback
    else
        echo -e ""$highlight_start"applying staging patches"$highlight_end""
        ../wine-staging-src/patches/patchinstall.sh DESTDIR="." --all \
        -W winex11-_NET_ACTIVE_WINDOW \
        -W winex11-WM_WINDOWPOSCHANGING \
        -W winex11-MWM_Decorations \
        -W winex11-key_translation \
        -W dbghelp-Debug_Symbols \
        -W xactengine3_7-callbacks \
        -W winemenubuilder-integration \
        -W dwrite-FontFallback \
        -W winepulse-PulseAudio_Support
    fi

### END WINE STAGING APPLY SECTION ###

### (2-3) GAME PATCH SECTION ###

if [ $GAME_PATCH = 1 ]; then

    echo -e ""$highlight_start"mech warrior online, enabled with WINE_MWO_HACK=1"$highlight_end""
    patch -Np1 < ../patches/app-patches/mwo.patch

    echo -e ""$highlight_start"ffxiv"$highlight_end""
    patch -Np1 < ../patches/app-patches/ffxiv-launcher-fix.patch

    echo -e ""$highlight_start"assetto corsa"$highlight_end""
    patch -Np1 < ../patches/app-patches/assettocorsa-hud.patch

    echo -e ""$highlight_start"mk11 patch"$highlight_end""
    # this is needed so that online multi-player does not crash
    patch -Np1 < ../patches/app-patches/mk11.patch

    echo -e ""$highlight_start"killer instinct vulkan fix"$highlight_end""
    patch -Np1 < ../patches/app-patches/killer-instinct-winevulkan_fix.patch

    echo -e ""$highlight_start"Castlevania Advance fix"$highlight_end""
    patch -Np1 < ../patches/app-patches/castlevania-advance-collection.patch

    echo -e ""$highlight_start"Lego Island fix"$highlight_end""
    patch -Np1 < ../patches/app-patches/legoisland_168726.patch

    echo -e ""$highlight_start"Planet Zoo fix"$highlight_end""
    patch -Np1 < ../patches/app-patches/planetzoo.patch

    echo -e ""$highlight_start"valve rdr2 fixes"$highlight_end""
    patch -Np1 < ../patches/app-patches/rdr2-fixes.patch

    echo -e ""$highlight_start"valve rdr2 bcrypt fixes"$highlight_end""
    patch -Np1 < ../patches/app-patches/bcrypt_rdr2_fixes.patch

    echo -e ""$highlight_start"proton quake champions patches"$highlight_end""
    patch -Np1 < ../patches/app-patches/quake_champions_syscall.patch

    echo -e ""$highlight_start"rockstar installer heap fix"$highlight_end""
    patch -Np1 < ../patches/app-patches/rockstar_installer_fix_heap.patch

    echo -e ""$highlight_start"Adds a stub for StorageDeviceSeekPenaltyProperty, needed for Star Citizen 3.13"$highlight_end""
    patch -Np1 < ../patches/app-patches/star-citizen-StorageDeviceSeekPenaltyProperty.patch

    echo -e ""$highlight_start"Makes macromedia director launchable"$highlight_end""
    patch -Np1 < ../patches/app-patches/macromedia_director.patch

    echo -e ""$highlight_start"dotnetfx35.exe: Add stub program."$highlight_end""
    patch -Np1 < ../patches/app-patches/dotnetfx35_stuf.patch
    
fi

### END GAME PATCH SECTION ###

### (2-4) CORE PATCH SECTION ###

if [ $CORE_PATCH = 1 ]; then

    echo -e ""$highlight_start"clock monotonic"$highlight_end""
    patch -Np1 < ../patches/core/01-use_clock_monotonic.patch

    echo -e ""$highlight_start"applying fsync patches"$highlight_end""
    patch -Np1 < ../patches/core/02-fsync_staging.patch

    echo -e ""$highlight_start"proton futex waitv patches"$highlight_end""
    patch -Np1 < ../patches/core/03-fsync_futex_waitv.patch

    echo -e ""$highlight_start"LAA"$highlight_end""
    patch -Np1 < ../patches/core/04-LAA_staging.patch

    echo -e ""$highlight_start"pa-audio"$highlight_end""
    patch -Np1 < ../patches/core/05-pa-staging.patch

    echo -e ""$highlight_start"Apply Lutris registry patch"$highlight_end""
    patch -Np1 < ../patches/registry/LutrisClient-registry-overrides-section.patch

    echo -e ""$highlight_start"amd ags"$highlight_end""
    patch -Np1 < ../patches/core/08-amd_ags.patch

    echo -e ""$highlight_start"msvcrt overrides"$highlight_end""
    patch -Np1 < ../patches/core/09-msvcrt_nativebuiltin.patch

    echo -e ""$highlight_start"atiadlxx needed for cod games"$highlight_end""
    patch -Np1 < ../patches/core/10-atiadlxx.patch

    echo -e ""$highlight_start"powershell add wrapper"$highlight_end""
    patch -Np1 < ../patches/core/11-powershell-add-wrapper.patch

    echo -e ""$highlight_start"valve registry entries"$highlight_end""

    echo -e ""$highlight_start"registry 1"$highlight_end""
    patch -Np1 < ../patches/registry/01_wolfenstein2_registry.patch
    echo -e ""$highlight_start"registry 2"$highlight_end""
    patch -Np1 < ../patches/registry/02_rdr2_registry.patch
    echo -e ""$highlight_start"registry 3"$highlight_end""
    patch -Np1 < ../patches/registry/03_nier_sekiro_ds3_registry.patch
    echo -e ""$highlight_start"registry 4"$highlight_end""
    patch -Np1 < ../patches/registry/04_cod_registry.patch
    echo -e ""$highlight_start"registry 5"$highlight_end""
    patch -Np1 < ../patches/registry/05_spellforce_registry.patch
    echo -e ""$highlight_start"registry 6"$highlight_end""
    patch -Np1 < ../patches/registry/06_shadow_of_war_registry.patch
    echo -e ""$highlight_start"registry 7"$highlight_end""
    patch -Np1 < ../patches/registry/07_nfs_registry.patch
    echo -e ""$highlight_start"registry 8"$highlight_end""
    patch -Np1 < ../patches/registry/08_FH4_registry.patch
    echo -e ""$highlight_start"registry 9"$highlight_end""
    patch -Np1 < ../patches/registry/09_nvapi_registry.patch
    echo -e ""$highlight_start"registry 10"$highlight_end""
    patch -Np1 < ../patches/registry/10-Civ6Launcher_Workaround.patch
    echo -e ""$highlight_start"registry 11"$highlight_end""
    patch -Np1 < ../patches/registry/11-Dirt_5.patch
    echo -e ""$highlight_start"registry 12"$highlight_end""
    patch -Np1 < ../patches/registry/12_death_loop_registry.patch
    echo -e ""$highlight_start"registry 13"$highlight_end""
    patch -Np1 < ../patches/registry/13_disable_libglesv2_for_nw.js.patch
    echo -e ""$highlight_start"registry 14"$highlight_end""
    patch -Np1 < ../patches/registry/14_atiadlxx_builtin_for_gotg.patch
    echo -e ""$highlight_start"registry 15"$highlight_end""
    patch -Np1 < ../patches/registry/15-msedgewebview-registry.patch
    echo -e ""$highlight_start"registry 16"$highlight_end""
    patch -Np1 < ../patches/registry/16-FH5-amd_ags_registry.patch
    echo -e ""$highlight_start"registry 17"$highlight_end""
    patch -Np1 < ../patches/registry/17-Age-of-Empires-IV-registry.patch
    echo -e ""$highlight_start"registry 18"$highlight_end""
    patch -Np1 < ../patches/registry/18_sims3_mshtml.patch
    echo -e ""$highlight_start"registry 19"$highlight_end""
    patch -Np1 < ../patches/registry/19-winemenubuilder.patch

    echo -e ""$highlight_start"apply staging bcrypt patches on top of rdr2 fixes"$highlight_end""
    patch -Np1 < ../patches/hotfixes/staging/0002-bcrypt-Add-support-for-calculating-secret-ecc-keys.patch
    patch -Np1 < ../patches/hotfixes/staging/0003-bcrypt-Add-support-for-OAEP-padded-asymmetric-key-de.patch
    patch -Np1 < ../patches/hotfixes/staging/bcrypt_BGenerateKeyPair_ECDH_P384.patch

    echo -e ""$highlight_start"set prefix win10"$highlight_end""
    patch -Np1 < ../patches/core/12-win10_default.patch

    echo -e ""$highlight_start"keyboard+mouse focus fixes"$highlight_end""
    patch -Np1 < ../patches/core/16-keyboard-input-and-mouse-focus-fixes.patch

    echo -e ""$highlight_start"CPU topology overrides"$highlight_end""
    patch -Np1 < ../patches/core/17-cpu-topology-overrides.patch

    if [ $FSHACK = 1 ]; then

    echo -e ""$highlight_start"fullscreen hack"$highlight_end""
    echo -e ""$highlight_start"fshack 1"$highlight_end""
    patch -Np1 < ../patches/fshack/vulkan-1-prefer-builtin.patch
    echo -e ""$highlight_start"fshack 2"$highlight_end""
    patch -Np1 < ../patches/fshack/valve_proton_fullscreen_hack-staging.patch
    echo -e ""$highlight_start"fullscreen hack fsr patch"$highlight_end""
    patch -Np1 < ../patches/fshack/fshack_amd_fsr.patch
    echo -e ""$highlight_start"Adds envar to fake reported resolution"$highlight_end""
    patch -Np1 < ../patches/fshack/fake_current_res_patches.patch

    fi

    echo -e ""$highlight_start"QPC performance patch"$highlight_end""
    patch -Np1 < ../patches/core/21-QPC.patch

    echo -e ""$highlight_start"LFH performance patch"$highlight_end""
    patch -Np1 < ../patches/core/22-LFH.patch

    echo -e ""$highlight_start"proton battleye patches"$highlight_end""
    patch -Np1 < ../patches/core/20-battleye_patches.patch
    
    echo -e ""$highlight_start"tabtip uiautomationcore patches"$highlight_end""
    patch -Np1 < ../patches/core/23-tabtip-uiautomationcore.patch

    echo -e ""$highlight_start"proton eac patches"$highlight_end""
    patch -Np1 < ../patches/core/24-eac_support.patch

    echo -e ""$highlight_start"Apply white theme"$highlight_end""
    patch -Np1 < ../patches/core/25-josh-flat-theme.patch

    echo -e ""$highlight_start"Disable nvapi"$highlight_end""
    patch -Np1 < ../patches/core/26-nvidia-hate.patch

    echo -e ""$highlight_start"Mono envars"$highlight_end""
    patch -Np1 < ../patches/core/27-monogecko_runtime.patch

    echo -e ""$highlight_start"Wine name change"$highlight_end""
    patch -Np1 < ../patches/core/30-wine-name.patch

fi

### END CORE PATCH SECTION ###

### START MFPLAT PATCH SECTION ###

if [ $MFPLAT_PATCH = 1 ]; then

    echo -e ""$highlight_start"mfplat 1"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0001-Revert-winegstreamer-Get-rid-of-the-WMReader-typedef.patch
    echo -e ""$highlight_start"mfplat 2"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0002-Revert-wmvcore-Move-the-async-reader-implementation-.patch
    echo -e ""$highlight_start"mfplat 3"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0003-Revert-winegstreamer-Get-rid-of-the-WMSyncReader-typ.patch
    echo -e ""$highlight_start"mfplat 4"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0004-Revert-wmvcore-Move-the-sync-reader-implementation-t.patch
    echo -e ""$highlight_start"mfplat 5"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0005-Revert-winegstreamer-Translate-GST_AUDIO_CHANNEL_POS.patch
    echo -e ""$highlight_start"mfplat 6"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0006-Revert-winegstreamer-Trace-the-unfiltered-caps-in-si.patch
    echo -e ""$highlight_start"mfplat 7"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0007-Revert-winegstreamer-Avoid-seeking-past-the-end-of-a.patch
    echo -e ""$highlight_start"mfplat 8"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0008-Revert-winegstreamer-Avoid-passing-a-NULL-buffer-to-.patch
    echo -e ""$highlight_start"mfplat 9"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0009-Revert-winegstreamer-Use-array_reserve-to-reallocate.patch
    echo -e ""$highlight_start"mfplat 10"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0010-Revert-winegstreamer-Handle-zero-length-reads-in-src.patch
    echo -e ""$highlight_start"mfplat 11"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0011-Revert-winegstreamer-Convert-the-Unix-library-to-the.patch
    echo -e ""$highlight_start"mfplat 12"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0012-Revert-winegstreamer-Return-void-from-wg_parser_stre.patch
    echo -e ""$highlight_start"mfplat 13"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0013-Revert-winegstreamer-Move-Unix-library-definitions-i.patch
    echo -e ""$highlight_start"mfplat 14"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0014-Revert-winegstreamer-Remove-the-no-longer-used-start.patch
    echo -e ""$highlight_start"mfplat 15"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0015-Revert-winegstreamer-Set-unlimited-buffering-using-a.patch
    echo -e ""$highlight_start"mfplat 16"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0016-Revert-winegstreamer-Initialize-GStreamer-in-wg_pars.patch
    echo -e ""$highlight_start"mfplat 17"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0017-Revert-winegstreamer-Use-a-single-wg_parser_create-e.patch
    echo -e ""$highlight_start"mfplat 18"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0018-Revert-winegstreamer-Fix-return-code-in-init_gst-fai.patch
    echo -e ""$highlight_start"mfplat 19"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0019-Revert-winegstreamer-Allocate-source-media-buffers-i.patch
    echo -e ""$highlight_start"mfplat 20"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0020-Revert-winegstreamer-Duplicate-source-shutdown-path-.patch
    echo -e ""$highlight_start"mfplat 21"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0021-Revert-winegstreamer-Properly-clean-up-from-failure-.patch
    echo -e ""$highlight_start"mfplat 22"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-reverts/0022-Revert-winegstreamer-Factor-out-more-of-the-init_gst.patch
    echo -e ""$highlight_start"mfplat 23"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0001-winegstreamer-Activate-source-pad-in-push-mode-if-it.patch
    echo -e ""$highlight_start"mfplat 24"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0002-winegstreamer-Push-stream-start-and-segment-events-i.patch
    echo -e ""$highlight_start"mfplat 25"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0003-winegstreamer-Introduce-H.264-decoder-transform.patch
    echo -e ""$highlight_start"mfplat 26"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0004-winegstreamer-Implement-GetInputAvailableType-for-de.patch
    echo -e ""$highlight_start"mfplat 27"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0005-winegstreamer-Implement-GetOutputAvailableType-for-d.patch
    echo -e ""$highlight_start"mfplat 28"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0006-winegstreamer-Implement-SetInputType-for-decode-tran.patch
    echo -e ""$highlight_start"mfplat 29"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0007-winegstreamer-Implement-SetOutputType-for-decode-tra.patch
    echo -e ""$highlight_start"mfplat 30"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0008-winegstreamer-Implement-Get-Input-Output-StreamInfo-.patch
    echo -e ""$highlight_start"mfplat 31"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0009-winegstreamer-Add-push-mode-path-for-wg_parser.patch
    echo -e ""$highlight_start"mfplat 32"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0010-winegstreamer-Implement-Process-Input-Output-for-dec.patch
    echo -e ""$highlight_start"mfplat 33"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0011-winestreamer-Implement-ProcessMessage-for-decoder-tr.patch
    echo -e ""$highlight_start"mfplat 34"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0012-winegstreamer-Semi-stub-GetAttributes-for-decoder-tr.patch
    echo -e ""$highlight_start"mfplat 35"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0013-winegstreamer-Register-the-H.264-decoder-transform.patch
    echo -e ""$highlight_start"mfplat 36"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0014-winegstreamer-Introduce-AAC-decoder-transform.patch
    echo -e ""$highlight_start"mfplat 37"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0015-winegstreamer-Register-the-AAC-decoder-transform.patch
    echo -e ""$highlight_start"mfplat 38"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0016-winegstreamer-Rename-GStreamer-objects-to-be-more-ge.patch
    echo -e ""$highlight_start"mfplat 39"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0017-winegstreamer-Report-streams-backwards-in-media-sour.patch
    echo -e ""$highlight_start"mfplat 40"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0018-winegstreamer-Implement-Process-Input-Output-for-aud.patch
    echo -e ""$highlight_start"mfplat 41"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0019-winegstreamer-Implement-Get-Input-Output-StreamInfo-.patch
    echo -e ""$highlight_start"mfplat 42"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0020-winegstreamer-Semi-stub-Get-Attributes-functions-for.patch
    echo -e ""$highlight_start"mfplat 43"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0021-winegstreamer-Introduce-color-conversion-transform.patch
    echo -e ""$highlight_start"mfplat 44"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0022-winegstreamer-Register-the-color-conversion-transfor.patch
    echo -e ""$highlight_start"mfplat 45"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0023-winegstreamer-Implement-GetInputAvailableType-for-co.patch
    echo -e ""$highlight_start"mfplat 46"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0024-winegstreamer-Implement-SetInputType-for-color-conve.patch
    echo -e ""$highlight_start"mfplat 47"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0025-winegstreamer-Implement-GetOutputAvailableType-for-c.patch
    echo -e ""$highlight_start"mfplat 48"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0026-winegstreamer-Implement-SetOutputType-for-color-conv.patch
    echo -e ""$highlight_start"mfplat 49"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0027-winegstreamer-Implement-Process-Input-Output-for-col.patch
    echo -e ""$highlight_start"mfplat 50"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0028-winegstreamer-Implement-ProcessMessage-for-color-con.patch
    echo -e ""$highlight_start"mfplat 51"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0029-winegstreamer-Implement-Get-Input-Output-StreamInfo-.patch
    echo -e ""$highlight_start"mfplat 52"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0030-mf-topology-Forward-failure-from-SetOutputType-when-.patch
    echo -e ""$highlight_start"mfplat 53"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0031-winegstreamer-Handle-flush-command-in-audio-converst.patch
    echo -e ""$highlight_start"mfplat 54"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0032-winegstreamer-In-the-default-configuration-select-on.patch
    echo -e ""$highlight_start"mfplat 55"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0033-winegstreamer-Implement-MF_SD_LANGUAGE.patch
    echo -e ""$highlight_start"mfplat 56"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0034-winegstreamer-Only-require-videobox-element-for-pars.patch
    echo -e ""$highlight_start"mfplat 57"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0035-winegstreamer-Don-t-rely-on-max_size-in-unseekable-p.patch
    echo -e ""$highlight_start"mfplat 58"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0036-winegstreamer-Implement-MFT_MESSAGE_COMMAND_FLUSH-fo.patch
    echo -e ""$highlight_start"mfplat 59"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0037-winegstreamer-Default-Frame-size-if-one-isn-t-availa.patch
    echo -e ""$highlight_start"mfplat 60"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0038-mfplat-Stub-out-MFCreateDXGIDeviceManager-to-avoid-t.patch
    echo -e ""$highlight_start"mfplat 61"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-streaming-support/0039-aperture-hotfix.patch

    echo -e ""$highlight_start"proton mfplat dll register patch"$highlight_end""
    patch -Np1 < ../patches/core/13-mediafoundation_dllreg.patch
    patch -Np1 < ../patches/core/14-mfplat-hacks.patch

    # Needed for Nier Replicant
    echo -e ""$highlight_start"proton mfplat nier replicant patch"$highlight_end""
    patch -Np1 < ../patches/hotfixes/staging/mfplat_dxgi_stub.patch

    # Needed for mfplat video format conversion, notably resident evil 8
    echo -e ""$highlight_start"proton mfplat video conversion patches"$highlight_end""
    patch -Np1 < ../patches/core/15-winegstreamer_updates.patch

    # Needed for godfall intro
    echo -e ""$highlight_start"mfplat godfall fix"$highlight_end""
    patch -Np1 < ../patches/hotfixes/mfplat/mfplat-godfall-hotfix.patch

    # missing http: scheme workaround see: https://github.com/ValveSoftware/Proton/issues/5195
    echo -e ""$highlight_start"The Good Life (1452500) workaround"$highlight_end""
    patch -Np1 < ../patches/app-patches/thegoodlife-mfplat-http-scheme-workaround.patch

    echo -e ""$highlight_start"FFXIV Video playback mfplat includes"$highlight_end""
    patch -Np1 < ../patches/app-patches/ffxiv-mfplat-additions.patch

fi

### END MFPLAT PATCH SECTION ###

### PERFORMANCE SECTION ###

if [ $PERFORMANCE_PATCH = 1 ]; then

    echo -e ""$highlight_start"Applying performance patches"

    echo -e ""$highlight_start"performance 1"$highlight_end""
    patch -Np1 < ../patches/performance/optimize-server-read-big-buffer.patch

    echo -e ""$highlight_start"performance 2"$highlight_end""
    patch -Np1 < ../patches/performance/ps0001-wininet-Improve-InternetGetConnectedStateExW-to-ha.patch

    echo -e ""$highlight_start"performance 3"$highlight_end""
    patch -Np1 < ../patches/performance/ps0010-netprofm-set-ret-NULL-if-no-more-connections.patch

    echo -e ""$highlight_start"performance 4"$highlight_end""
    patch -Np1 < ../patches/performance/ps0033-p0001-server-Don-t-reallocate-a-buffer-for-every-r.patch

    echo -e ""$highlight_start"performance 5"$highlight_end""
    patch -Np1 < ../patches/performance/ps0033-p0002-server-Don-t-reallocate-reply-when-size-chan.patch

    echo -e ""$highlight_start"performance 6"$highlight_end""
    patch -Np1 < ../patches/performance/ps0033-p0003-server-Always-send-replies-with-writev.patch

    echo -e ""$highlight_start"performance 7"$highlight_end""
    patch -Np1 < ../patches/performance/ps0033-p0004-server-Use-a-pool-for-small-most-thread_wait.patch

    echo -e ""$highlight_start"performance 8"$highlight_end""
    patch -Np1 < ../patches/performance/ps0084-wineboot-Generate-ProductId-from-host-s-machine-id.patch

    echo -e ""$highlight_start"performance 9"$highlight_end""
    patch -Np1 < ../patches/performance/ps0091-kernelbase-Cache-last-used-locale-sortguid-mapping.patch

    echo -e ""$highlight_start"performance 10"$highlight_end""
    patch -Np1 < ../patches/performance/ps0248-ntdll-server-Write-system-handle-info-directly-to-.patch

    echo -e ""$highlight_start"performance 11"$highlight_end""
    patch -Np1 < ../patches/performance/ps0264-p0002-server-Enable-link-time-optimization.patch

    echo -e ""$highlight_start"performance 12"$highlight_end""
    patch -Np1 < ../patches/performance/ps0299-p0001-fixup-server-Create-esync-file-descriptors-f.patch

    echo -e ""$highlight_start"performance 13"$highlight_end""
    patch -Np1 < ../patches/performance/ps0299-p0002-fixup-server-Create-eventfd-file-descriptors.patch

    echo -e ""$highlight_start"performance 14"$highlight_end""
    patch -Np1 < ../patches/performance/ps0299-p0003-fixup-server-Create-eventfd-descriptors-for-.patch

fi

### END PERFORMANCE SECTION ###

### WINEX11 SECTION ###

if [ $WINEX11_PATCH = 1 ]; then

    echo -e ""$highlight_start"Applying winex11 patches"

    echo -e ""$highlight_start"winex11 1"$highlight_end""
    patch -Np1 < ../patches/winex11/ps0019-winex11.drv-Add-a-taskbar-button-for-a-minimized-o.patch

    echo -e ""$highlight_start"winex11 2"$highlight_end""
    patch -Np1 < ../patches/winex11/unity-alt-tab-fix.patch

    echo -e ""$highlight_start"winex11 3"$highlight_end""
    patch -Np1 < ../patches/winex11/winex11_limit_resources-nmode.patch

    if [ $FSHACK = 1 ]; then
    
    echo -e ""$highlight_start"winex11 4"$highlight_end""
    patch -Np1 < ../patches/winex11/winex11.drv_fix_focus_delay.patch

    echo -e ""$highlight_start"winex11 5"$highlight_end""
    patch -Np1 < ../patches/winex11/winex11-fs-no_above_state.patch

    else

    echo -e ""$highlight_start"winex11 4"$highlight_end""
    patch -Np1 < ../patches/winex11/winex11-fs-no_above_state-nofshack.patch

    fi

fi

### END WINEX11 SECTION ###

### WINE HOTFIX SECTION ###

if [ $HOTFIX_PATCH = 1 ]; then

    echo -e ""$highlight_start"Applying performance patches"

    # keep this in place, proton and wine tend to bounce back and forth and proton uses a different URL.
    # We can always update the patch to match the version and sha256sum even if they are the same version
    echo -e ""$highlight_start"hotfix to update mono version"$highlight_end""
    patch -Np1 < ../patches/hotfixes/pending/hotfix-update_mono_version.patch

    echo -e ""$highlight_start"add halo infinite patches"$highlight_end""
    patch -Np1 < ../patches/hotfixes/pending/halo-infinite-twinapi.appcore.dll.patch

    # https://github.com/Frogging-Family/wine-tkg-git/commit/ca0daac62037be72ae5dd7bf87c705c989eba2cb
    echo -e ""$highlight_start"unity crash hotfix"$highlight_end""
    patch -Np1 < ../patches/hotfixes/pending/unity_crash_hotfix.patch

fi

### END WINE HOTFIX SECTION ###

    ./dlls/winevulkan/make_vulkan
    ./tools/make_requests
    autoreconf -f
