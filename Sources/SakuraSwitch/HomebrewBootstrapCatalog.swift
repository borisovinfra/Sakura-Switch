import Foundation

enum HomebrewBootstrapCatalog {
    private static let entries: [String: HomebrewRelease] = [
        "nagaa95/sphaira|exact:sphaira.zip": HomebrewRelease(
            version: "1.0.6",
            size: 1962579,
            downloadURL: URL(string: "https://github.com/NaGaa95/sphaira/releases/download/1.0.6/sphaira.zip")!,
            assetName: "sphaira.zip"
        ),
        "itotaljustice/ftpsrv|exact:switch_application.zip": HomebrewRelease(
            version: "1.2.2",
            size: 447541,
            downloadURL: URL(string: "https://github.com/ITotalJustice/ftpsrv/releases/download/1.2.2/switch_application.zip")!,
            assetName: "switch_application.zip"
        ),
        "mtheall/ftpd|exact:ftpd.nro": HomebrewRelease(
            version: "v3.2.1",
            size: 1533963,
            downloadURL: URL(string: "https://github.com/mtheall/ftpd/releases/download/v3.2.1/ftpd.nro")!,
            assetName: "ftpd.nro"
        ),
        "xortroll/emuiibo|exact:emuiibo.zip": HomebrewRelease(
            version: "1.1.3",
            size: 629696,
            downloadURL: URL(string: "https://github.com/XorTroll/emuiibo/releases/download/1.1.3/emuiibo.zip")!,
            assetName: "emuiibo.zip"
        ),
        "ppkantorski/nx-ovlloader|exact:nx-ovlloader.zip": HomebrewRelease(
            version: "v2.0.2",
            size: 86442,
            downloadURL: URL(string: "https://github.com/ppkantorski/nx-ovlloader/releases/download/v2.0.2/nx-ovlloader.zip")!,
            assetName: "nx-ovlloader.zip"
        ),
        "proferabg/edizon-overlay|exact:edizon-overlay.zip": HomebrewRelease(
            version: "v1.0.15",
            size: 379944,
            downloadURL: URL(string: "https://github.com/proferabg/EdiZon-Overlay/releases/download/v1.0.15/EdiZon-Overlay.zip")!,
            assetName: "EdiZon-Overlay.zip"
        ),
        "meganukebmp/switch_90dns_tester|exact:switch_90dns_tester.nro": HomebrewRelease(
            version: "v1.1.0",
            size: 255950,
            downloadURL: URL(string: "https://github.com/meganukebmp/Switch_90DNS_tester/releases/download/v1.1.0/Switch_90DNS_tester.nro")!,
            assetName: "Switch_90DNS_tester.nro"
        ),
        "suchmememanyskill/themezer-nx|exact:themezer-nx.nro": HomebrewRelease(
            version: "3.2.1",
            size: 9717532,
            downloadURL: URL(string: "https://github.com/suchmememanyskill/themezer-nx/releases/download/3.2.1/themezer-nx.nro")!,
            assetName: "themezer-nx.nro"
        ),
        "polonx/simplemoddownloader|exact:simplemoddownloader.nro": HomebrewRelease(
            version: "2.3.0",
            size: 10486141,
            downloadURL: URL(string: "https://github.com/PoloNX/SimpleModDownloader/releases/download/2.3.0/SimpleModDownloader.nro")!,
            assetName: "SimpleModDownloader.nro"
        ),
        "xfangfang/wiliwili|exact:wiliwili-nintendoswitch.zip": HomebrewRelease(
            version: "v1.6.0",
            size: 18815897,
            downloadURL: URL(string: "https://github.com/xfangfang/wiliwili/releases/download/v1.6.0/wiliwili-NintendoSwitch.zip")!,
            assetName: "wiliwili-NintendoSwitch.zip"
        )
        ,
        "averne/fizeau|contains:fizeau-": HomebrewRelease(
            version: "v2.8.3",
            size: 1536484,
            downloadURL: URL(string: "https://github.com/averne/Fizeau/releases/download/v2.8.3/Fizeau-2.8.3-5bf3f0d.zip")!,
            assetName: "Fizeau-2.8.3-5bf3f0d.zip"
        ),
        "bernardogiordano/checkpoint|exact:checkpoint.nro": HomebrewRelease(
            version: "v5.2.0",
            size: 5041265,
            downloadURL: URL(string: "https://github.com/BernardoGiordano/Checkpoint/releases/download/v5.2.0/Checkpoint.nro")!,
            assetName: "Checkpoint.nro"
        ),
        "o0zz/sys-con|contains:sys-con-": HomebrewRelease(
            version: "1.7.0",
            size: 504574,
            downloadURL: URL(string: "https://github.com/o0Zz/sys-con/releases/download/1.7.0/sys-con-1.7.0.zip")!,
            assetName: "sys-con-1.7.0.zip"
        ),
        "exelix11/switchthemeinjector|exact:nxthemesinstaller.nro": HomebrewRelease(
            version: "nxt-3.0.1",
            size: 10394050,
            downloadURL: URL(string: "https://github.com/exelix11/SwitchThemeInjector/releases/download/nxt-3.0.1/NXThemesInstaller.nro")!,
            assetName: "NXThemesInstaller.nro"
        ),
        "exelix11/sysdvr|exact:sysdvr.zip": HomebrewRelease(
            version: "v6.3",
            size: 3196237,
            downloadURL: URL(string: "https://github.com/exelix11/SysDVR/releases/download/v6.3/SysDVR.zip")!,
            assetName: "SysDVR.zip"
        ),
        "fortheusers/hb-appstore|exact:appstore.nro": HomebrewRelease(
            version: "v2.3.2",
            size: 11104808,
            downloadURL: URL(string: "https://github.com/fortheusers/hb-appstore/releases/download/v2.3.2/appstore.nro")!,
            assetName: "appstore.nro"
        ),
        "hamletdufromage/aio-switch-updater|exact:aio-switch-updater.zip": HomebrewRelease(
            version: "2.23.3",
            size: 3538231,
            downloadURL: URL(string: "https://github.com/HamletDuFromage/aio-switch-updater/releases/download/2.23.3/aio-switch-updater.zip")!,
            assetName: "aio-switch-updater.zip"
        ),
        "j-d-k/jksv|suffix:.nro": HomebrewRelease(
            version: "12/02/2025",
            size: 10590617,
            downloadURL: URL(string: "https://github.com/J-D-K/JKSV/releases/download/12%2F02%2F2025/JKSV.nro")!,
            assetName: "JKSV.nro"
        ),
        "joel16/nx-shell|exact:nx-shell.nro": HomebrewRelease(
            version: "4.01",
            size: 8575621,
            downloadURL: URL(string: "https://github.com/joel16/NX-Shell/releases/download/4.01/NX-Shell.nro")!,
            assetName: "NX-Shell.nro"
        ),
        "joel16/switchident|exact:switchident.nro": HomebrewRelease(
            version: "0.5",
            size: 8963995,
            downloadURL: URL(string: "https://github.com/joel16/SwitchIdent/releases/download/0.5/SwitchIdent.nro")!,
            assetName: "SwitchIdent.nro"
        ),
        "masagrator/fpslocker|exact:fpslocker.ovl": HomebrewRelease(
            version: "3.3.2",
            size: 1380408,
            downloadURL: URL(string: "https://github.com/masagrator/FPSLocker/releases/download/3.3.2/FPSLocker.ovl")!,
            assetName: "FPSLocker.ovl"
        ),
        "masagrator/reversenx-rt|exact:reversenx-rt-ovl.ovl": HomebrewRelease(
            version: "2.2.1",
            size: 315448,
            downloadURL: URL(string: "https://github.com/masagrator/ReverseNX-RT/releases/download/2.2.1/ReverseNX-RT-ovl.ovl")!,
            assetName: "ReverseNX-RT-ovl.ovl"
        ),
        "masagrator/saltynx|exact:saltynx.zip": HomebrewRelease(
            version: "1.9.2",
            size: 221477,
            downloadURL: URL(string: "https://github.com/masagrator/SaltyNX/releases/download/1.9.2/SaltyNX.zip")!,
            assetName: "SaltyNX.zip"
        ),
        "masagrator/status-monitor-deux|exact:status-monitor-deux.zip": HomebrewRelease(
            version: "0.2.1",
            size: 343633,
            downloadURL: URL(string: "https://github.com/masagrator/Status-Monitor-Deux/releases/download/0.2.1/Status-Monitor-Deux.zip")!,
            assetName: "Status-Monitor-Deux.zip"
        ),
        "mgba-emu/mgba|suffix:-switch.7z": HomebrewRelease(
            version: "0.10.5",
            size: 2211306,
            downloadURL: URL(string: "https://github.com/mgba-emu/mgba/releases/download/0.10.5/mGBA-0.10.5-switch.7z")!,
            assetName: "mGBA-0.10.5-switch.7z"
        ),
        "mirusu400/switch-newpipe|exact:switch_newpipe.nro": HomebrewRelease(
            version: "v0.0.5",
            size: 34288435,
            downloadURL: URL(string: "https://github.com/mirusu400/switch-newpipe/releases/download/v0.0.5/switch_newpipe.nro")!,
            assetName: "switch_newpipe.nro"
        ),
        "nadrino/simplemodmanager|exact:simplemodmanager.nro": HomebrewRelease(
            version: "2.1.4",
            size: 8771712,
            downloadURL: URL(string: "https://github.com/nadrino/SimpleModManager/releases/download/2.1.4/SimpleModManager.nro")!,
            assetName: "SimpleModManager.nro"
        ),
        "ndeadly/missioncontrol|contains:missioncontrol-": HomebrewRelease(
            version: "v0.15.2",
            size: 195069,
            downloadURL: URL(string: "https://github.com/ndeadly/MissionControl/releases/download/v0.15.2/MissionControl-0.15.2-master-d3941d43.zip")!,
            assetName: "MissionControl-0.15.2-master-d3941d43.zip"
        ),
        "nedex/quickntp|exact:sdout.zip": HomebrewRelease(
            version: "1.6.0",
            size: 153413,
            downloadURL: URL(string: "https://github.com/nedex/QuickNTP/releases/download/1.6.0/sdout.zip")!,
            assetName: "sdout.zip"
        ),
        "ppkantorski/ovl-sysmodules|exact:ovlsysmodules.ovl": HomebrewRelease(
            version: "v1.5.3",
            size: 639036,
            downloadURL: URL(string: "https://github.com/ppkantorski/ovl-sysmodules/releases/download/v1.5.3/ovlSysmodules.ovl")!,
            assetName: "ovlSysmodules.ovl"
        ),
        "ppkantorski/ultrahand-overlay|exact:sdout.zip": HomebrewRelease(
            version: "v2.5.3",
            size: 939343,
            downloadURL: URL(string: "https://github.com/ppkantorski/Ultrahand-Overlay/releases/download/v2.5.3/sdout.zip")!,
            assetName: "sdout.zip"
        ),
        "proconsule/nxmp|contains:nxmp-": HomebrewRelease(
            version: "v0.9.3",
            size: 45558017,
            downloadURL: URL(string: "https://github.com/proconsule/nxmp/releases/download/v0.9.3/nxmp-0.9.3.zip")!,
            assetName: "nxmp-0.9.3.zip"
        ),
        "rashevskyv/dbipatcher|exact:dbi.nro": HomebrewRelease(
            version: "898",
            size: 12268339,
            downloadURL: URL(string: "https://github.com/rashevskyv/DBIPatcher/releases/download/898/DBI.nro")!,
            assetName: "DBI.nro"
        ),
        "retronx-team/sys-clk|contains:sys-clk-": HomebrewRelease(
            version: "2.0.1",
            size: 3325359,
            downloadURL: URL(string: "https://github.com/retronx-team/sys-clk/releases/download/2.0.1/sys-clk-2.0.1-21fix.zip")!,
            assetName: "sys-clk-2.0.1-21fix.zip"
        ),
        "spacemeowx2/ldn_mitm|contains:ldn_mitm_": HomebrewRelease(
            version: "v1.25.1",
            size: 343088,
            downloadURL: URL(string: "https://github.com/spacemeowx2/ldn_mitm/releases/download/v1.25.1/ldn_mitm_v1.25.1.zip")!,
            assetName: "ldn_mitm_v1.25.1.zip"
        ),
        "suchmememanyskill/tegraexplorer|exact:tegraexplorer.bin": HomebrewRelease(
            version: "4.2.0",
            size: 124954,
            downloadURL: URL(string: "https://github.com/suchmememanyskill/TegraExplorer/releases/download/4.2.0/TegraExplorer.bin")!,
            assetName: "TegraExplorer.bin"
        ),
        "werwolv/hekate-toolbox|exact:hekatetoolbox.nro": HomebrewRelease(
            version: "v4.0.4",
            size: 2737984,
            downloadURL: URL(string: "https://github.com/WerWolv/Hekate-Toolbox/releases/download/v4.0.4/HekateToolbox.nro")!,
            assetName: "HekateToolbox.nro"
        ),
        "werwolv/tesla-menu|exact:ovlmenu.zip": HomebrewRelease(
            version: "v1.2.3",
            size: 156762,
            downloadURL: URL(string: "https://github.com/WerWolv/Tesla-Menu/releases/download/v1.2.3/ovlmenu.zip")!,
            assetName: "ovlmenu.zip"
        ),
        "xitrix/moonlight-switch|exact:moonlight-switch.nro": HomebrewRelease(
            version: "v1.5.0",
            size: 17677907,
            downloadURL: URL(string: "https://github.com/XITRIX/Moonlight-Switch/releases/download/v1.5.0/Moonlight-Switch.nro")!,
            assetName: "Moonlight-Switch.nro"
        ),
        "xortroll/goldleaf|exact:goldleaf.nro": HomebrewRelease(
            version: "1.2.0",
            size: 11865198,
            downloadURL: URL(string: "https://github.com/XorTroll/Goldleaf/releases/download/1.2.0/Goldleaf.nro")!,
            assetName: "Goldleaf.nro"
        ),
        "tomvita/breeze-beta|exact:breeze.zip": HomebrewRelease(
            version: "beta108.4c",
            size: 9631043,
            downloadURL: URL(string: "https://github.com/tomvita/Breeze-Beta/releases/download/beta108.4c/Breeze.zip")!,
            assetName: "Breeze.zip"
        ),
        "luketanti/cyberfoil|exact:cyberfoil.zip": HomebrewRelease(
            version: "1.4.6",
            size: 6741801,
            downloadURL: URL(string: "https://github.com/luketanti/CyberFoil/releases/download/1.4.6/cyberfoil.zip")!,
            assetName: "cyberfoil.zip"
        ),
        "impeeza/linkalho|contains:linkalho-": HomebrewRelease(
            version: "v2.0.2",
            size: 3156396,
            downloadURL: URL(string: "https://github.com/impeeza/linkalho/releases/download/v2.0.2/linkalho-v2.0.2.zip")!,
            assetName: "linkalho-v2.0.2.zip"
        ),
        "eradicatinglove/quick-reboot|exact:quick-reboot.nro": HomebrewRelease(
            version: "V2.2.0",
            size: 214886,
            downloadURL: URL(string: "https://github.com/eradicatinglove/Quick-Reboot/releases/download/V2.2.0/Quick-Reboot.nro")!,
            assetName: "Quick-Reboot.nro"
        ),
        "ppkantorski/status-monitor-overlay|exact:status-monitor-overlay.ovl": HomebrewRelease(
            version: "v1.4.1+r4",
            size: 1228860,
            downloadURL: URL(string: "https://github.com/ppkantorski/Status-Monitor-Overlay/releases/download/v1.4.1%2Br4/Status-Monitor-Overlay.ovl")!,
            assetName: "Status-Monitor-Overlay.ovl"
        ),
        "switchbrew/nssu-updater|contains:nssu-updater_": HomebrewRelease(
            version: "v1.0.0",
            size: 164858,
            downloadURL: URL(string: "https://github.com/switchbrew/nssu-updater/releases/download/v1.0.0/nssu-updater_v1.0.0.zip")!,
            assetName: "nssu-updater_v1.0.0.zip"
        ),
        "errlogic/nada|contains:sys-nada-": HomebrewRelease(
            version: "v0.1.0",
            size: 582083,
            downloadURL: URL(string: "https://github.com/ErrLogic/nada/releases/download/v0.1.0/sys-nada-v0.1.0.zip")!,
            assetName: "sys-nada-v0.1.0.zip"
        ),
        "ppkantorski/tetris-overlay|exact:tetris.ovl": HomebrewRelease(
            version: "v0.5.2",
            size: 1077308,
            downloadURL: URL(string: "https://github.com/ppkantorski/Tetris-Overlay/releases/download/v0.5.2/tetris.ovl")!,
            assetName: "tetris.ovl"
        ),
        "ppkantorski/nx-fancontrol|exact:nx-fancontrol.ovl": HomebrewRelease(
            version: "1.0.3+r4",
            size: 704572,
            downloadURL: URL(string: "https://github.com/ppkantorski/NX-FanControl/releases/download/1.0.3%2Br4/NX-FanControl.ovl")!,
            assetName: "NX-FanControl.ovl"
        ),
        "ppkantorski/ultragb-overlay|exact:sdout.zip": HomebrewRelease(
            version: "v1.0.2",
            size: 421924,
            downloadURL: URL(string: "https://github.com/ppkantorski/UltraGB-Overlay/releases/download/v1.0.2/sdout.zip")!,
            assetName: "sdout.zip"
        )
    ]

    static func release(forKey key: String) -> HomebrewRelease? {
        entries[key]
    }
}
