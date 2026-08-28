import Foundation

enum L10n {
    private static func text(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main)
    }

    // MARK: - Compatibility

    static var navInstallation: String { sidebarInstallation }
    static var navSDCard: String { sidebarSDCard }
    static var navSaves: String { sidebarSaves }
    static var navGallery: String { sidebarGallery }
    static var navGamesAndMods: String { sidebarGamesAndMods }
    static var navDBIBackend: String { "DBI Backend" }
    static var navFTP: String { "FTP" }
    static var navAbout: String { sidebarAbout }

    static var aboutVersionFormat: String {
        text("about.version_format")
    }

    // MARK: - Sidebar

    static var sidebarInstallation: String { text("sidebar.installation") }
    static var sidebarSDCard: String { text("sidebar.sd_card") }
    static var sidebarSaves: String { text("sidebar.saves") }
    static var sidebarGallery: String { text("sidebar.gallery") }
    static var sidebarGamesAndMods: String { text("sidebar.games_mods") }
    static var sidebarAbout: String { text("sidebar.about") }

    // MARK: - Sakura Switch PRO

    static var sidebarApplications: String { text("sidebar.applications") }

    static var proTitle: String { text("pro.title") }
    static var proSubtitle: String { text("pro.subtitle") }
    static var proSearch: String { text("pro.search") }
    static var proCategory: String { text("pro.category") }

    static var proCategoryAll: String { text("pro.category.all") }
    static var proCategorySystem: String { text("pro.category.system") }
    static var proCategoryFiles: String { text("pro.category.files") }
    static var proCategorySaves: String { text("pro.category.saves") }
    static var proCategoryMods: String { text("pro.category.mods") }
    static var proCategoryOverlays: String { text("pro.category.overlays") }
    static var proCategoryNetwork: String { text("pro.category.network") }
    static var proCategoryMedia: String { text("pro.category.media") }
    static var proCategoryEmulation: String { text("pro.category.emulation") }

    static var proLatest: String { text("pro.latest") }
    static var proInstall: String { text("pro.install") }
    static var proInstallTo: String { text("pro.install_to") }
    static var proCount3: String { text("pro.count.3") }
    static var proEventLog: String { text("pro.event_log") }
    static var proReady: String { text("pro.ready") }

    static var proDBIDescription: String { text("pro.app.dbi.description") }
    static var proJKSVDescription: String { text("pro.app.jksv.description") }
    static var proNewPipeDescription: String { text("pro.app.newpipe.description") }


    static var proUnavailable: String { text("pro.unavailable") }

    static var proLogLoading: String { text("pro.log.loading") }
    static var proLogChecking: String { text("pro.log.checking") }
    static var proLogRateCheckFailed: String { text("pro.log.rate_check_failed") }

    static func proLogCatalogLoaded(_ count: Int) -> String {
        String(format: text("pro.log.catalog_loaded"), count)
    }

    static func proLogCatalogLoadedPartial(_ loaded: Int, _ total: Int) -> String {
        String(format: text("pro.log.catalog_loaded_partial"), loaded, total)
    }

    static func proLogCatalogUpdated(_ count: Int) -> String {
        String(format: text("pro.log.catalog_updated"), count)
    }

    static func proLogCatalogUpdatedPartial(_ loaded: Int, _ total: Int) -> String {
        String(format: text("pro.log.catalog_updated_partial"), loaded, total)
    }

    static func proLogDeferred(_ time: String, _ remaining: Int, _ required: Int) -> String {
        String(
            format: text("pro.log.deferred"),
            time,
            remaining,
            required
        )
    }

    static func proCount(_ count: Int) -> String {
        String(format: text("pro.count"), count)
    }

    static var proMissionControlDescription: String { text("pro.app.missioncontrol.description") }
    static var proNXShellDescription: String { text("pro.app.nxshell.description") }
    static var proSimpleModManagerDescription: String { text("pro.app.simplemodmanager.description") }
    static var proNXThemesDescription: String { text("pro.app.nxthemes.description") }
    static var proSysClkDescription: String { text("pro.app.sysclk.description") }
    static var proSysDVRDescription: String { text("pro.app.sysdvr.description") }
    static var proMoonlightDescription: String { text("pro.app.moonlight.description") }
    static var proUltrahandDescription: String { text("pro.app.ultrahand.description") }
    static var proFPSLockerDescription: String { text("pro.app.fpslocker.description") }
    static var proStatusMonitorDescription: String { text("pro.app.statusmonitor.description") }
    static var proAIOUpdaterDescription: String { text("pro.app.aio.description") }
    static var proCheckpointDescription: String { text("pro.app.checkpoint.description") }
    static var proGoldleafDescription: String { text("pro.app.goldleaf.description") }
    static var proTeslaDescription: String { text("pro.app.tesla.description") }
    static var proSaltyNXDescription: String { text("pro.app.saltynx.description") }
    static var proReverseNXDescription: String { text("pro.app.reversenx.description") }
    static var proFizeauDescription: String { text("pro.app.fizeau.description") }
    static var proHBAppStoreDescription: String { text("pro.app.hbappstore.description") }
    static var proOvlSysmodulesDescription: String { text("pro.app.ovlsysmodules.description") }
    static var proTegraExplorerDescription: String { text("pro.app.tegraexplorer.description") }
    static var proHekateToolboxDescription: String { text("pro.app.hekate.description") }
    static var proLdnMitmDescription: String { text("pro.app.ldnmitm.description") }
    static var proSysConDescription: String { text("pro.app.syscon.description") }
    static var proQuickNTPDescription: String { text("pro.app.quickntp.description") }
    static var proNXMPDescription: String { text("pro.app.nxmp.description") }
    static var proMGbaDescription: String { text("pro.app.mgba.description") }
    static var proSwitchIdentDescription: String { text("pro.app.switchident.description") }
    static var proSphairaDescription: String { text("pro.app.sphaira.description") }
    static var proFtpsrvDescription: String { text("pro.app.ftpsrv.description") }
    static var proFtpdDescription: String { text("pro.app.ftpd.description") }
    static var proEmuiiboDescription: String { text("pro.app.emuiibo.description") }
    static var proNXOvlLoaderDescription: String { text("pro.app.nxovlloader.description") }
    static var proEdiZonOverlayDescription: String { text("pro.app.edizonoverlay.description") }
    static var pro90DNSTesterDescription: String { text("pro.app.90dnstester.description") }
    static var proThemezerDescription: String { text("pro.app.themezer.description") }
    static var proSimpleModDownloaderDescription: String { text("pro.app.simplemoddownloader.description") }
    static var proWiliwiliDescription: String { text("pro.app.wiliwili.description") }
    static var proBreezeDescription: String { text("pro.app.breeze.description") }
    static var proCyberFoilDescription: String { text("pro.app.cyberfoil.description") }
    static var proLinkalhoDescription: String { text("pro.app.linkalho.description") }
    static var proQuickRebootDescription: String { text("pro.app.quickreboot.description") }
    static var proStatusMonitorOverlayDescription: String { text("pro.app.statusmonitoroverlay.description") }
    static var proNSSUUpdaterDescription: String { text("pro.app.nssuupdater.description") }
    static var proNadaDescription: String { text("pro.app.nada.description") }
    static var proTetrisOverlayDescription: String { text("pro.app.tetrisoverlay.description") }
    static var proNXFanControlDescription: String { text("pro.app.nxfancontrol.description") }
    static var proUltraGBDescription: String { text("pro.app.ultragb.description") }

    // MARK: - About

    static var aboutToolkit: String { text("about.toolkit") }
    static var aboutVersion: String { text("about.version") }
    static var aboutFeatures: String { text("about.features") }
    static var aboutAtmosphere: String { text("about.atmosphere") }
    static var aboutMods: String { text("about.mods") }
    static var aboutSDCard: String { text("about.sd_card") }
    static var aboutSaves: String { text("about.saves") }
    static var aboutGallery: String { text("about.gallery") }
    static var aboutSpecialThanks: String { text("about.special_thanks") }
    static var aboutFirstBlossom: String { text("about.first_blossom") }
    static var aboutSupporter: String { text("about.supporter") }

    // Compatibility aliases used by AboutView.
    static var aboutAtmosphereContents: String { aboutAtmosphere }
    static var aboutModInstallation: String { aboutMods }
    static var aboutFirstSupporter: String { aboutSupporter }

    // MARK: - Connection / Log

    static func switchConnected(_ mode: String) -> String {
        String(format: text("connection.connected"), mode)
    }

    static var switchWaiting: String {
        text("connection.waiting")
    }

    static var logAll: String { text("log.all") }
    static var logInfo: String { text("log.info") }
    static var logWarnings: String { text("log.warnings") }
    static var logErrors: String { text("log.errors") }

    // MARK: - Sakura Saves

    static var savesTitle: String { text("saves.title") }
    static var savesRefresh: String { text("saves.refresh") }
    static var savesLoading: String { text("saves.loading") }
    static var savesLoadFailed: String { text("saves.load_failed") }
    static var savesNotFound: String { text("saves.not_found") }
    static var savesConnectHint: String { text("saves.connect_hint") }
    static var savesLoadButton: String { text("saves.load_button") }
    static var savesGameLoading: String { text("saves.game_loading") }
    static var savesOpenFailed: String { text("saves.open_failed") }
    static var savesSelectGame: String { text("saves.select_game") }
    static var savesSelectGameHint: String { text("saves.select_game_hint") }
    static var savesCopying: String { text("saves.copying") }
    static var savesCreateBackup: String { text("saves.create_backup") }
    static var savesRestoring: String { text("saves.restoring") }
    static var savesRestore: String { text("saves.restore") }
    static var savesFilesLoading: String { text("saves.files_loading") }
    static var savesSaveOpenFailed: String { text("saves.save_open_failed") }
    static var savesFilesNotFound: String { text("saves.files_not_found") }
    static var savesSelectSave: String { text("saves.select_save") }
    static var savesSelectSaveHint: String { text("saves.select_save_hint") }
    static var savesChooseBackup: String { text("saves.choose_backup") }
    static var savesChooseBackupButton: String { text("saves.choose_backup_button") }
    static var savesRestoreQuestion: String { text("saves.restore_question") }
    static var savesRetry: String { text("saves.retry") }


    // MARK: - Sakura Saves Backup / Restore

    static var savesRestoreGame: String { text("saves.restore.game") }
    static var savesRestoreSave: String { text("saves.restore.save") }
    static var savesRestoreFiles: String { text("saves.restore.files") }
    static var savesRestoreEmergencyWarning: String { text("saves.restore.emergency_warning") }
    static var savesRestoreConfirm: String { text("saves.restore.confirm") }

    static var savesBackupFolderTitle: String { text("saves.backup.folder_title") }
    static var savesBackupFolderPrompt: String { text("saves.backup.folder_prompt") }

    static func savesEmergencyBackupCreated(_ path: String) -> String {
        String(format: text("saves.restore.emergency_created"), path)
    }

    static func savesRestoreCompleted(_ path: String) -> String {
        String(format: text("saves.restore.completed"), path)
    }

    static func savesBackupCreated(_ path: String) -> String {
        String(format: text("saves.backup.created"), path)
    }

    static func savesBackupFailed(_ reason: String) -> String {
        String(format: text("saves.backup.failed"), reason)
    }

    static func savesInvalidBackupFolder() -> String {
        text("saves.error.invalid_backup")
    }

    static func savesEmptyBackup() -> String {
        text("saves.error.empty_backup")
    }

    static func savesNestedDirectoriesUnsupported() -> String {
        text("saves.error.nested_directories")
    }

    static func savesEmergencyVerificationFailed(_ file: String) -> String {
        String(format: text("saves.error.emergency_verification"), file)
    }

    static func savesVerificationMissingFile(_ file: String) -> String {
        String(format: text("saves.error.missing_file"), file)
    }

    static func savesVerificationSizeMismatch(_ file: String) -> String {
        String(format: text("saves.error.size_mismatch"), file)
    }

    static func savesRestoreRolledBack(_ reason: String) -> String {
        String(format: text("saves.error.rolled_back"), reason)
    }

    static func savesRollbackFailed(_ reason: String) -> String {
        String(format: text("saves.error.rollback_failed"), reason)
    }


    // MARK: - Sakura Saves Logs

    static func savesLogEmergencyCreated(_ path: String) -> String {
        String(format: text("saves.log.emergency_created"), path)
    }

    static func savesLogRestoreCompleted(
        _ game: String,
        _ save: String
    ) -> String {
        String(
            format: text("saves.log.restore_completed"),
            game,
            save
        )
    }

    static var savesLogRestoreWriteFailed: String {
        text("saves.log.restore_write_failed")
    }

    static func savesLogRestoreError(_ error: String) -> String {
        String(format: text("saves.log.restore_error"), error)
    }

    static func savesLogBackupCreated(_ path: String) -> String {
        String(format: text("saves.log.backup_created"), path)
    }

    static func savesLogBackupError(_ error: String) -> String {
        String(format: text("saves.log.backup_error"), error)
    }

    static func savesLogGamesFound(_ count: Int) -> String {
        String(format: text("saves.log.games_found"), count)
    }

    static func savesLogError(_ error: String) -> String {
        String(format: text("saves.log.error"), error)
    }

    static func savesLogEntriesFound(
        _ game: String,
        _ count: Int
    ) -> String {
        String(
            format: text("saves.log.entries_found"),
            game,
            count
        )
    }

    static func savesLogFilesFound(
        _ game: String,
        _ save: String,
        _ count: Int
    ) -> String {
        String(
            format: text("saves.log.files_found"),
            game,
            save,
            count
        )
    }


    // MARK: - Sakura Gallery

    static var galleryTitle: String { text("gallery.title") }
    static var galleryRefresh: String { text("gallery.refresh") }
    static var galleryLoading: String { text("gallery.loading") }
    static var galleryOpenFailed: String { text("gallery.open_failed") }
    static var galleryEmpty: String { text("gallery.empty") }
    static var galleryEmptyHint: String { text("gallery.empty_hint") }
    static var galleryMediaLoading: String { text("gallery.media_loading") }
    static var galleryAlbumOpenFailed: String { text("gallery.album_open_failed") }
    static var galleryNoMedia: String { text("gallery.no_media") }
    static var gallerySelectGame: String { text("gallery.select_game") }
    static var gallerySelectGameHint: String { text("gallery.select_game_hint") }
    static var galleryVideo: String { text("gallery.video") }
    static var galleryPhoto: String { text("gallery.photo") }
    static var galleryMediaLoadFailed: String { text("gallery.media_load_failed") }
    static var galleryPreviewUnavailable: String { text("gallery.preview_unavailable") }
    static var gallerySelectMedia: String { text("gallery.select_media") }
    static var gallerySelectMediaHint: String { text("gallery.select_media_hint") }
    static var galleryVideoUnavailable: String { text("gallery.video_unavailable") }
    static var gallerySaveToMac: String { text("gallery.save_to_mac") }
    static var gallerySavePanelTitle: String { text("gallery.save_panel_title") }
    static var galleryRetry: String { text("gallery.retry") }
    static var galleryAlbumStorageNotFound: String { text("gallery.error.album_not_found") }
    static var galleryImageDecodeFailed: String { text("gallery.error.image_decode_failed") }

    static func gallerySaved(_ path: String) -> String {
        String(format: text("gallery.saved"), path)
    }

    static func gallerySaveError(_ error: String) -> String {
        String(format: text("gallery.save_error"), error)
    }

    static func galleryLogAlbumsFound(_ count: Int) -> String {
        String(format: text("gallery.log.albums_found"), count)
    }

    static func galleryLogError(_ error: String) -> String {
        String(format: text("gallery.log.error"), error)
    }

    static func galleryLogMediaFound(_ game: String, _ count: Int) -> String {
        String(format: text("gallery.log.media_found"), game, count)
    }

    static func galleryLogLoaded(_ name: String) -> String {
        String(format: text("gallery.log.loaded"), name)
    }

    static func galleryLogPreviewError(_ error: String) -> String {
        String(format: text("gallery.log.preview_error"), error)
    }

    static func galleryLogExported(_ path: String) -> String {
        String(format: text("gallery.log.exported"), path)
    }

    // MARK: - Games & Mods

    static var modsTitle: String { text("mods.title") }
    static var modsRefresh: String { text("mods.refresh") }
    static var modsAdd: String { text("mods.add") }
    static var modsInstalling: String { text("mods.installing") }
    static var modsInstall: String { text("mods.install") }

    static func modsCounter(_ modded: Int, _ total: Int) -> String {
        String(format: text("mods.counter"), modded, total)
    }

    static var modsScanning: String { text("mods.scanning") }
    static var modsLoadFailed: String { text("mods.load_failed") }
    static var modsNoGames: String { text("mods.no_games") }

    static var modsBadgeEnabled: String { text("mods.badge.enabled") }
    static var modsBadgeDisabled: String { text("mods.badge.disabled") }

    static var modsEnabled: String { text("mods.enabled") }
    static var modsDisabled: String { text("mods.disabled") }
    static var modsDisable: String { text("mods.disable") }
    static var modsEnable: String { text("mods.enable") }
    static var modsNotFound: String { text("mods.not_found") }

    static var modsNoneDetected: String { text("mods.none_detected") }
    static var modsNoneHint: String { text("mods.none_hint") }

    static var modsReadingContents: String {
        text("mods.reading_contents")
    }

    static var modsOpenContentsFailed: String {
        text("mods.open_contents_failed")
    }

    static var modsFolderEmpty: String { text("mods.folder_empty") }
    static var modsSelectGame: String { text("mods.select_game") }
    static var modsSelectGameHint: String { text("mods.select_game_hint") }

    static var modsInvalidDisabledName: String {
        text("mods.error.invalid_disabled_name")
    }

    static var modsChooseFolder: String {
        text("mods.choose_folder")
    }

    static var modsInstalled: String {
        text("mods.installed")
    }

    static func modsInstallError(_ error: String) -> String {
        String(format: text("mods.install_error"), error)
    }

    static var modsFolderCheats: String { text("mods.folder.cheats") }
    static var modsFolderFlags: String { text("mods.folder.flags") }
    static var modsRetry: String { text("mods.retry") }

    // MARK: - Games & Mods Logs

    static func modsLogGames(_ games: Int, _ contents: Int) -> String {
        String(
            format: text("mods.log.games"),
            games,
            contents
        )
    }

    static func modsLogError(_ error: String) -> String {
        String(format: text("mods.log.error"), error)
    }

    static func modsLogToggle(
        _ game: String,
        _ enabled: Bool
    ) -> String {
        String(
            format: enabled
                ? text("mods.log.enabled")
                : text("mods.log.disabled"),
            game
        )
    }

    static func modsLogToggleError(_ error: String) -> String {
        String(
            format: text("mods.log.toggle_error"),
            error
        )
    }

    static func modsLogContents(
        _ game: String,
        _ count: Int
    ) -> String {
        String(
            format: text("mods.log.contents"),
            game,
            count
        )
    }

    static func modsLogDetected(_ titleID: String) -> String {
        String(
            format: text("mods.log.detected"),
            titleID
        )
    }

    // MARK: - Connection / SD Browser

    static func connectionConnected(_ mode: String) -> String {
        String(
            format: text("connection.connected"),
            mode
        )
    }

    static var sdBrowserRoot: String {
        text("sd.browser.root")
    }

    static func sdBrowserItemCount(_ count: Int) -> String {
        String(
            format: text("sd.browser.item_count"),
            count
        )
    }

    // MARK: - Installation

    static var installMode: String { text("install.mode") }
    static var installCheckSD: String { text("install.check_sd") }
    static var installCheckMTP: String { text("install.check_mtp") }
    static var installDestination: String { text("install.destination") }
    static var installQuickSetup: String { text("install.quick_setup") }
    static var close: String { text("common.close") }

    static var ftpAddress: String { text("install.ftp_address") }
    static var ftpPlaceholder: String { text("install.ftp_placeholder") }
    static var connect: String { text("install.connect") }
    static var ftpReady: String { text("install.ftp_ready") }

    static var eventLog: String { text("install.event_log") }
    static var exportLogHelp: String { text("install.export_log") }
    static var copyLogHelp: String { text("install.copy_log") }
    static var clearQueue: String { text("install.clear_queue") }

    static var dropFiles: String { text("install.drop_files") }
    static var chooseFiles: String { text("install.choose_files") }
    static var chooseFilesPanel: String { text("install.choose_files_panel") }
    static var noFiles: String { text("install.no_files") }
    static var noFilesDescription: String { text("install.no_files_description") }

    static var install: String { text("install.button") }
    static var connecting: String { text("install.connecting") }
    static var connectedWaiting: String { text("install.connected_waiting") }
    static var done: String { text("install.done") }
    static var cancel: String { text("common.cancel") }
    static var fileDone: String { text("install.file_done") }

    static func reconnecting(_ attempt: Int) -> String {
        String(format: text("install.reconnecting"), attempt)
    }

    // MARK: - Installation help

    static var helpDBIBackend: String { text("install.help.dbi_backend") }
    static var helpMTP: String { text("install.help.mtp") }
    static var helpSDCard: String { text("install.help.sd_card") }
    static var helpFTP: String { text("install.help.ftp") }


    // MARK: - Transport Modes

    static func transportModeTitle(_ rawValue: String) -> String {
        switch rawValue {
        case "DBI Backend":
            return text("transport.dbi_backend")
        case "MTP":
            return text("transport.mtp")
        case "SD-карта":
            return text("transport.sd_card")
        case "Network":
            return text("transport.network")
        default:
            return rawValue
        }
    }

    // MARK: - Diagnostics

    static var mtpStartingTest: String { text("mtp.starting_test") }
    static var mtpTestingHandshake: String { text("mtp.testing_handshake") }
    static var mtpHandshakeSuccess: String { text("mtp.handshake_success") }
    static var mtpHandshakeFailed: String { text("mtp.handshake_failed") }

    static var mtpKernelRelease: String { text("mtp.kernel_release") }
    static var mtpKernelReleased: String { text("mtp.kernel_released") }
    static var mtpKernelDetach: String { text("mtp.kernel_detach") }

    static var mtpSwitchOpened: String { text("mtp.switch_opened") }
    static var mtpCompatibility: String { text("mtp.compatibility") }
    static var mtpUsingStorage: String { text("mtp.using_storage") }
    static var mtpInstallSD: String { text("mtp.install_sd") }
    static var mtpInstallNAND: String { text("mtp.install_nand") }
    static var mtpNoDevices: String { text("mtp.no_devices") }
    static var mtpUnableOpen: String { text("mtp.unable_open") }
    static var mtpDBINotFound: String { text("mtp.dbi_not_found") }

    static func mtpFoundDevice(_ device: String) -> String {
        String(format: text("mtp.found_device"), device)
    }

    static var mtpUSBNotFound: String { text("mtp.usb_not_found") }
    static var mtpSwitchNotFound: String { text("mtp.switch_not_found") }
    static var mtpChecking: String { text("mtp.checking") }
    static var mtpSuccess: String { text("mtp.success") }

    static func mtpError(_ error: String) -> String {
        String(format: text("mtp.error"), error)
    }

    static func mtpResultError(_ device: String, _ error: String) -> String {
        String(format: text("mtp.result_error"), device, error)
    }

    // MARK: - FTP Validation

    static var ftpMissingAddress: String { text("ftp.missing_address") }
    static var ftpInvalidAddress: String { text("ftp.invalid_address") }

    // MARK: - SD Diagnostics

    static var sdChecking: String { text("sd.checking") }
    static var sdAvailable: String { text("sd.available") }

    static func sdRootSummary(_ folders: Int, _ files: Int) -> String {
        String(format: text("sd.root_summary"), folders, files)
    }

    static var sdCheckSuccess: String { text("sd.check_success") }

    static func sdAccessError(_ error: String) -> String {
        String(format: text("sd.access_error"), error)
    }

    // MARK: - Diagnostics Export

    static func diagnosticsSaved(_ file: String) -> String {
        String(format: text("diagnostics.saved"), file)
    }

    static var diagnosticsCancelled: String {
        text("diagnostics.cancelled")
    }

    static func diagnosticsError(_ error: String) -> String {
        String(format: text("diagnostics.error"), error)
    }

}
