; Script      fileman_gui.ahk
; License:    MIT License
; Author:     Bence Markiel (bceenaeiklmr)
; Github:     https://github.com/bceenaeiklmr/fileman
; Date        08.08.2026
; Version     0.4.0

#include fileman.ahk
#include guimodule.ahk

quarantineDir := "E:\temporary\fileman-quarantine"
if (!DirExist(quarantineDir))
    DirCreate(quarantineDir)

; Instantiate the GUI
app := AppGui("File Manager & Duplicate Finder")

; Bind the GUI start button to our handler function
app.onStartCallback := HandleGuiStart
app.onMoveCallback := HandleGuiMove


HandleGuiStart(guiApp, params) {
    guiApp.ClearResults()
    guiApp.UpdateProgress(5, "Initializing scanner...")

    scanPaths := params.targetPaths
    fm := fileMan(scanPaths, !params.includeSystem, DisplayScanStatus, ignoredRules)

    guiApp.UpdateProgress(20, "Scanning files...")
    fm.Scan(true)

    guiApp.UpdateProgress(80, "Saving report and checking duplicates...")
    fm.SaveReport()

    if (fm.HasOwnProp("verifiedFileDuplicates") && fm.verifiedFileDuplicates) {
        for group in fm.verifiedFileDuplicates {
            hashVal := group.key
            for filePath in group.paths {
                if (filePath == "" || !FileExist(filePath))
                    continue

                SplitPath(filePath, &fileName)
                fileSize := FileGetSize(filePath)
                formattedSize := FormatBytes(fileSize)

                ; 5. paraméterként átadjuk a nyers fileSize-t bájtokban
                guiApp.AddResultRow(fileName, formattedSize, filePath, hashVal, fileSize)
            }
        }
    }

    preview := fm.MoveVerifiedDuplicates(quarantineDir)

    guiApp.UpdateProgress(100, "Scan finished!")
    MsgBox("Files to move: " . preview.actions.Length, "Scan Complete", "Iconi")
}

HandleGuiMove(guiApp, selectedItems) {
    if (selectedItems.Length == 0) {
        MsgBox("No items selected for moving.", "Move Files", "Icon!")
        return
    }

    movedCount := 0
    failCount := 0

    ; Loop through selected items in reverse order to avoid index shifting issues
    i := selectedItems.Length
    while (i > 0) {
        item := selectedItems[i]
        
        if (FileExist(item.path)) {
            try {
                SplitPath(item.path, &fileName)
                FileMove(item.path, quarantineDir "\" fileName, 1) ; 1 = overwrite
                guiApp.resultsLV.Delete(item.row)
                movedCount++
            } catch {
                failCount++
            }
        }
        i--
    }

    guiApp.UpdateMoveButtonState()
    MsgBox("Moved: " . movedCount . " file(s).`nFailed: " . failCount, "Move Complete", "Iconi")
}