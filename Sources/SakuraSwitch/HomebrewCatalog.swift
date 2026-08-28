import Foundation

enum HomebrewCategory: String, CaseIterable, Identifiable {
    case all
    case system
    case files
    case saves
    case mods
    case overlays
    case network
    case media
    case emulation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.proCategoryAll
        case .system: return L10n.proCategorySystem
        case .files: return L10n.proCategoryFiles
        case .saves: return L10n.proCategorySaves
        case .mods: return L10n.proCategoryMods
        case .overlays: return L10n.proCategoryOverlays
        case .network: return L10n.proCategoryNetwork
        case .media: return L10n.proCategoryMedia
        case .emulation: return L10n.proCategoryEmulation
        }
    }
}

enum HomebrewType {
    case application
    case sysmodule
    case overlay
    case bundle
    case payload
}

enum HomebrewAssetRule {
    case exact(String)
    case suffix(String)
    case contains(String)

    var cacheIdentifier: String {
        switch self {
        case .exact(let value):
            return "exact:\(value.lowercased())"
        case .suffix(let value):
            return "suffix:\(value.lowercased())"
        case .contains(let value):
            return "contains:\(value.lowercased())"
        }
    }

    func matches(_ name: String) -> Bool {
        switch self {
        case .exact(let value):
            return name.caseInsensitiveCompare(value) == .orderedSame

        case .suffix(let value):
            return name.lowercased().hasSuffix(value.lowercased())

        case .contains(let value):
            return name.lowercased().contains(value.lowercased())
        }
    }
}

struct HomebrewApp: Identifiable {
    let id: String
    let name: String
    let author: String
    let description: String
    let category: HomebrewCategory
    let type: HomebrewType
    let repository: String
    let assetRule: HomebrewAssetRule
}

enum HomebrewCatalog {
    static let applications: [HomebrewApp] = [

        HomebrewApp(
            id: "dbi",
            name: "DBI",
            author: "rashevskyv",
            description: L10n.proDBIDescription,
            category: .files,
            type: .application,
            repository: "rashevskyv/DBIPatcher",
            assetRule: .exact("DBI.nro")
        ),

        HomebrewApp(
            id: "jksv",
            name: "JKSV",
            author: "J-D-K",
            description: L10n.proJKSVDescription,
            category: .saves,
            type: .application,
            repository: "J-D-K/JKSV",
            assetRule: .suffix(".nro")
        ),

        HomebrewApp(
            id: "switch-newpipe",
            name: "Switch-NewPipe",
            author: "mirusu400",
            description: L10n.proNewPipeDescription,
            category: .media,
            type: .application,
            repository: "mirusu400/switch-newpipe",
            assetRule: .exact("switch_newpipe.nro")
        ),

        HomebrewApp(
            id: "missioncontrol",
            name: "MissionControl",
            author: "ndeadly",
            description: L10n.proMissionControlDescription,
            category: .system,
            type: .bundle,
            repository: "ndeadly/MissionControl",
            assetRule: .contains("MissionControl-")
        ),

        HomebrewApp(
            id: "nx-shell",
            name: "NX-Shell",
            author: "joel16",
            description: L10n.proNXShellDescription,
            category: .files,
            type: .application,
            repository: "joel16/NX-Shell",
            assetRule: .exact("NX-Shell.nro")
        ),

        HomebrewApp(
            id: "simplemodmanager",
            name: "SimpleModManager",
            author: "nadrino",
            description: L10n.proSimpleModManagerDescription,
            category: .mods,
            type: .application,
            repository: "nadrino/SimpleModManager",
            assetRule: .exact("SimpleModManager.nro")
        ),

        HomebrewApp(
            id: "nxthemes",
            name: "NXThemes Installer",
            author: "exelix11",
            description: L10n.proNXThemesDescription,
            category: .mods,
            type: .application,
            repository: "exelix11/SwitchThemeInjector",
            assetRule: .exact("NXThemesInstaller.nro")
        ),

        HomebrewApp(
            id: "sys-clk",
            name: "sys-clk",
            author: "retronx-team",
            description: L10n.proSysClkDescription,
            category: .system,
            type: .bundle,
            repository: "retronx-team/sys-clk",
            assetRule: .contains("sys-clk-")
        ),

        HomebrewApp(
            id: "sysdvr",
            name: "SysDVR",
            author: "exelix11",
            description: L10n.proSysDVRDescription,
            category: .network,
            type: .bundle,
            repository: "exelix11/SysDVR",
            assetRule: .exact("SysDVR.zip")
        ),

        HomebrewApp(
            id: "moonlight",
            name: "Moonlight-Switch",
            author: "XITRIX",
            description: L10n.proMoonlightDescription,
            category: .network,
            type: .application,
            repository: "XITRIX/Moonlight-Switch",
            assetRule: .exact("Moonlight-Switch.nro")
        ),

        HomebrewApp(
            id: "ultrahand",
            name: "Ultrahand Overlay",
            author: "ppkantorski",
            description: L10n.proUltrahandDescription,
            category: .overlays,
            type: .overlay,
            repository: "ppkantorski/Ultrahand-Overlay",
            assetRule: .exact("sdout.zip")
        ),

        HomebrewApp(
            id: "fpslocker",
            name: "FPSLocker",
            author: "masagrator",
            description: L10n.proFPSLockerDescription,
            category: .overlays,
            type: .overlay,
            repository: "masagrator/FPSLocker",
            assetRule: .exact("FPSLocker.ovl")
        ),

        HomebrewApp(
            id: "status-monitor-deux",
            name: "Status Monitor Deux",
            author: "masagrator",
            description: L10n.proStatusMonitorDescription,
            category: .overlays,
            type: .bundle,
            repository: "masagrator/Status-Monitor-Deux",
            assetRule: .exact("Status-Monitor-Deux.zip")
        ),

        HomebrewApp(
            id: "aio-switch-updater",
            name: "AIO Switch Updater",
            author: "HamletDuFromage",
            description: L10n.proAIOUpdaterDescription,
            category: .system,
            type: .bundle,
            repository: "HamletDuFromage/aio-switch-updater",
            assetRule: .exact("aio-switch-updater.zip")
        )
,

        HomebrewApp(
            id: "checkpoint",
            name: "Checkpoint",
            author: "BernardoGiordano",
            description: L10n.proCheckpointDescription,
            category: .saves,
            type: .application,
            repository: "BernardoGiordano/Checkpoint",
            assetRule: .exact("Checkpoint.nro")
        ),

        HomebrewApp(
            id: "goldleaf",
            name: "Goldleaf",
            author: "XorTroll",
            description: L10n.proGoldleafDescription,
            category: .files,
            type: .application,
            repository: "XorTroll/Goldleaf",
            assetRule: .exact("Goldleaf.nro")
        ),

        HomebrewApp(
            id: "tesla-menu",
            name: "Tesla Menu",
            author: "WerWolv",
            description: L10n.proTeslaDescription,
            category: .overlays,
            type: .bundle,
            repository: "WerWolv/Tesla-Menu",
            assetRule: .exact("ovlmenu.zip")
        ),

        HomebrewApp(
            id: "saltynx",
            name: "SaltyNX",
            author: "masagrator",
            description: L10n.proSaltyNXDescription,
            category: .system,
            type: .bundle,
            repository: "masagrator/SaltyNX",
            assetRule: .exact("SaltyNX.zip")
        ),

        HomebrewApp(
            id: "reversenx-rt",
            name: "ReverseNX-RT",
            author: "masagrator",
            description: L10n.proReverseNXDescription,
            category: .overlays,
            type: .overlay,
            repository: "masagrator/ReverseNX-RT",
            assetRule: .exact("ReverseNX-RT-ovl.ovl")
        ),

        HomebrewApp(
            id: "fizeau",
            name: "Fizeau",
            author: "averne",
            description: L10n.proFizeauDescription,
            category: .system,
            type: .bundle,
            repository: "averne/Fizeau",
            assetRule: .contains("Fizeau-")
        ),

        HomebrewApp(
            id: "hb-appstore",
            name: "Homebrew App Store",
            author: "fortheusers",
            description: L10n.proHBAppStoreDescription,
            category: .system,
            type: .application,
            repository: "fortheusers/hb-appstore",
            assetRule: .exact("appstore.nro")
        ),

        HomebrewApp(
            id: "ovl-sysmodules",
            name: "ovl-sysmodules",
            author: "ppkantorski",
            description: L10n.proOvlSysmodulesDescription,
            category: .overlays,
            type: .overlay,
            repository: "ppkantorski/ovl-sysmodules",
            assetRule: .exact("ovlSysmodules.ovl")
        ),

        HomebrewApp(
            id: "tegraexplorer",
            name: "TegraExplorer",
            author: "suchmememanyskill",
            description: L10n.proTegraExplorerDescription,
            category: .system,
            type: .payload,
            repository: "suchmememanyskill/TegraExplorer",
            assetRule: .exact("TegraExplorer.bin")
        ),

        HomebrewApp(
            id: "hekate-toolbox",
            name: "Hekate Toolbox",
            author: "WerWolv",
            description: L10n.proHekateToolboxDescription,
            category: .system,
            type: .application,
            repository: "WerWolv/Hekate-Toolbox",
            assetRule: .exact("HekateToolbox.nro")
        ),

        HomebrewApp(
            id: "ldn-mitm",
            name: "ldn_mitm",
            author: "spacemeowx2",
            description: L10n.proLdnMitmDescription,
            category: .network,
            type: .bundle,
            repository: "spacemeowx2/ldn_mitm",
            assetRule: .contains("ldn_mitm_")
        ),

        HomebrewApp(
            id: "sys-con",
            name: "sys-con",
            author: "o0Zz",
            description: L10n.proSysConDescription,
            category: .system,
            type: .bundle,
            repository: "o0Zz/sys-con",
            assetRule: .contains("sys-con-")
        ),

        HomebrewApp(
            id: "quickntp",
            name: "QuickNTP",
            author: "nedex",
            description: L10n.proQuickNTPDescription,
            category: .overlays,
            type: .bundle,
            repository: "nedex/QuickNTP",
            assetRule: .exact("sdout.zip")
        ),

        HomebrewApp(
            id: "nxmp",
            name: "NXMP",
            author: "proconsule",
            description: L10n.proNXMPDescription,
            category: .media,
            type: .bundle,
            repository: "proconsule/nxmp",
            assetRule: .contains("nxmp-")
        ),

        HomebrewApp(
            id: "mgba",
            name: "mGBA",
            author: "mGBA",
            description: L10n.proMGbaDescription,
            category: .emulation,
            type: .bundle,
            repository: "mgba-emu/mgba",
            assetRule: .suffix("-switch.7z")
        ),

        HomebrewApp(
            id: "switchident",
            name: "SwitchIdent",
            author: "joel16",
            description: L10n.proSwitchIdentDescription,
            category: .system,
            type: .application,
            repository: "joel16/SwitchIdent",
            assetRule: .exact("SwitchIdent.nro")
        ),
        HomebrewApp(
            id: "sphaira",
            name: "Sphaira",
            author: "NaGaa95",
            description: L10n.proSphairaDescription,
            category: .system,
            type: .bundle,
            repository: "NaGaa95/sphaira",
            assetRule: .exact("sphaira.zip")
        ),
        HomebrewApp(
            id: "ftpsrv",
            name: "ftpsrv",
            author: "ITotalJustice",
            description: L10n.proFtpsrvDescription,
            category: .network,
            type: .bundle,
            repository: "ITotalJustice/ftpsrv",
            assetRule: .exact("switch_application.zip")
        ),
        HomebrewApp(
            id: "ftpd",
            name: "ftpd",
            author: "mtheall",
            description: L10n.proFtpdDescription,
            category: .network,
            type: .application,
            repository: "mtheall/ftpd",
            assetRule: .exact("ftpd.nro")
        ),
        HomebrewApp(
            id: "emuiibo",
            name: "emuiibo",
            author: "XorTroll",
            description: L10n.proEmuiiboDescription,
            category: .system,
            type: .bundle,
            repository: "XorTroll/emuiibo",
            assetRule: .exact("emuiibo.zip")
        ),
        HomebrewApp(
            id: "nx-ovlloader",
            name: "nx-ovlloader",
            author: "ppkantorski",
            description: L10n.proNXOvlLoaderDescription,
            category: .overlays,
            type: .bundle,
            repository: "ppkantorski/nx-ovlloader",
            assetRule: .exact("nx-ovlloader.zip")
        ),
        HomebrewApp(
            id: "edizon-overlay",
            name: "EdiZon Overlay",
            author: "proferabg",
            description: L10n.proEdiZonOverlayDescription,
            category: .overlays,
            type: .bundle,
            repository: "proferabg/EdiZon-Overlay",
            assetRule: .exact("EdiZon-Overlay.zip")
        ),
        HomebrewApp(
            id: "90dns-tester",
            name: "Switch 90DNS Tester",
            author: "meganukebmp",
            description: L10n.pro90DNSTesterDescription,
            category: .network,
            type: .application,
            repository: "meganukebmp/Switch_90DNS_tester",
            assetRule: .exact("Switch_90DNS_tester.nro")
        ),
        HomebrewApp(
            id: "themezer-nx",
            name: "Themezer-NX",
            author: "suchmememanyskill",
            description: L10n.proThemezerDescription,
            category: .mods,
            type: .application,
            repository: "suchmememanyskill/themezer-nx",
            assetRule: .exact("themezer-nx.nro")
        ),
        HomebrewApp(
            id: "simplemoddownloader",
            name: "SimpleModDownloader",
            author: "PoloNX",
            description: L10n.proSimpleModDownloaderDescription,
            category: .mods,
            type: .application,
            repository: "PoloNX/SimpleModDownloader",
            assetRule: .exact("SimpleModDownloader.nro")
        ),
        HomebrewApp(
            id: "wiliwili",
            name: "wiliwili",
            author: "xfangfang",
            description: L10n.proWiliwiliDescription,
            category: .media,
            type: .bundle,
            repository: "xfangfang/wiliwili",
            assetRule: .exact("wiliwili-NintendoSwitch.zip")
        ),
        HomebrewApp(
            id: "breeze",
            name: "Breeze",
            author: "tomvita",
            description: L10n.proBreezeDescription,
            category: .mods,
            type: .bundle,
            repository: "tomvita/Breeze-Beta",
            assetRule: .exact("Breeze.zip")
        ),
        HomebrewApp(
            id: "cyberfoil",
            name: "CyberFoil",
            author: "luketanti",
            description: L10n.proCyberFoilDescription,
            category: .files,
            type: .bundle,
            repository: "luketanti/CyberFoil",
            assetRule: .exact("cyberfoil.zip")
        ),
        HomebrewApp(
            id: "linkalho",
            name: "Linkalho",
            author: "impeeza",
            description: L10n.proLinkalhoDescription,
            category: .system,
            type: .bundle,
            repository: "impeeza/linkalho",
            assetRule: .contains("linkalho-")
        ),
        HomebrewApp(
            id: "quick-reboot",
            name: "Quick-Reboot",
            author: "eradicatinglove",
            description: L10n.proQuickRebootDescription,
            category: .system,
            type: .application,
            repository: "eradicatinglove/Quick-Reboot",
            assetRule: .exact("Quick-Reboot.nro")
        ),
        HomebrewApp(
            id: "status-monitor-overlay",
            name: "Status Monitor Overlay",
            author: "ppkantorski",
            description: L10n.proStatusMonitorOverlayDescription,
            category: .overlays,
            type: .overlay,
            repository: "ppkantorski/Status-Monitor-Overlay",
            assetRule: .exact("Status-Monitor-Overlay.ovl")
        ),
        HomebrewApp(
            id: "nssu-updater",
            name: "nssu-updater",
            author: "switchbrew",
            description: L10n.proNSSUUpdaterDescription,
            category: .system,
            type: .bundle,
            repository: "switchbrew/nssu-updater",
            assetRule: .contains("nssu-updater_")
        ),
        HomebrewApp(
            id: "nada",
            name: "Nada",
            author: "ErrLogic",
            description: L10n.proNadaDescription,
            category: .media,
            type: .bundle,
            repository: "ErrLogic/nada",
            assetRule: .contains("sys-nada-")
        ),
        HomebrewApp(
            id: "tetris-overlay",
            name: "Tetris Overlay",
            author: "ppkantorski",
            description: L10n.proTetrisOverlayDescription,
            category: .overlays,
            type: .overlay,
            repository: "ppkantorski/Tetris-Overlay",
            assetRule: .exact("tetris.ovl")
        ),
        HomebrewApp(
            id: "nx-fancontrol",
            name: "NX-FanControl",
            author: "ppkantorski",
            description: L10n.proNXFanControlDescription,
            category: .overlays,
            type: .overlay,
            repository: "ppkantorski/NX-FanControl",
            assetRule: .exact("NX-FanControl.ovl")
        ),
        HomebrewApp(
            id: "ultragb-overlay",
            name: "UltraGB Overlay",
            author: "ppkantorski",
            description: L10n.proUltraGBDescription,
            category: .emulation,
            type: .bundle,
            repository: "ppkantorski/UltraGB-Overlay",
            assetRule: .exact("sdout.zip")
        )
    ]
}
