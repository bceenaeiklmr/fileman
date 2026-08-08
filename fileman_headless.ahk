
; Script      fileman_headless.ahk
; License:    MIT License
; Author:     Bence Markiel (bceenaeiklmr)
; Github:     https://github.com/bceenaeiklmr/fileman
; Date        08.08.2026
; Version     0.4.0

#include fileman.ahk

; Set up quarantine directory
quarantineDir := "E:\temporary\fileman-quarantine"
if (!DirExist(quarantineDir))
    DirCreate(quarantineDir)

; Instantiate the FileMan class
fm := FileMan(["D:\", "E:\"], true, DisplayScanStatus, ignoredRules)

; Start the scanning process
fm.Scan(true)

; Save the report
fm.SaveReport()

; Move verified duplicates to quarantine directory (dry run)
preview := fm.MoveVerifiedDuplicates(quarantineDir, dryRun := true)

ExitApp()