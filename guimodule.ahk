; Script      guimodule.ahk
; License:    MIT License
; Author:     Bence Markiel (bceenaeiklmr)
; Github:     https://github.com/bceenaeiklmr/fileman
; Date        08.08.2026
; Version     0.4.0


#include guimodule.ahk


/**
 * AppGui class encapsulates the GUI logic for the File Manager & Duplicate Finder application.
 */
class AppGui {
    
    ; GUI control handles
    gui := 0
    driveDDL := 0
    includeSysCB := 0
    dirEdit := 0
    nameEdit := 0
    extEdit := 0
    minSizeEdit := 0
    maxSizeEdit := 0
    progressBar := 0
    statusLabel := 0
    pathSummaryLabel := 0
    resultsLV := 0
    startBtn := 0
    selectAllBtn := 0
    moveBtn := 0
    seenHashes := Map()

    ; Path to the settings INI file
    iniFile := A_ScriptDir "\settings.ini"

    ; Callback function for handling the start button click event
    onStartCallback := 0
    onMoveCallback := 0

    ; Constructor for the AppGui class. Initializes the GUI and its controls.
    __New(title := "File Manager & Duplicate Finder") {
        
        local drives, driveList, browseBtn, sizeGrp

        ; Initialize the GUI window, add main events
        this.gui := Gui("+Resize", title)
        this.gui.OnEvent("Close", (*) => (this.SaveSettings(), ExitApp()))
        this.gui.OnEvent("Size", (guiObj, minMax, width, height) => this.OnResize(width, height))

        ; --- Target Location Group Box ---
        this.gui.AddGroupBox("x10 y10 w560 h90", "Target Location")

        ; Drive Selection and Folder Input
        this.gui.AddText("x20 y32 w40", "Drive:")
        drives := DriveGetList()
        driveList := ["All Drives"]
        Loop Parse, drives {
            driveList.Push(A_LoopField ":\")
        }

        ; Add the drive dropdown list and bind its change event to update the path summary
        this.driveDDL := this.gui.AddDropDownList("x65 y28 w90 Choose1", driveList)
        this.driveDDL.OnEvent("Change", (*) => this.OnDriveChange())

        ; Add the "Include System" checkbox and bind its click event to update the path summary
        this.includeSysCB := this.gui.AddCheckbox("x165 y30 w130", "Include System (C:\)")
        this.includeSysCB.OnEvent("Click", (*) => this.UpdatePathSummary())

        ; Add the folder input field and its associated buttons for adding/removing folders
        this.gui.AddText("x290 y32 w50", "Folders:")
        this.dirEdit := this.gui.AddEdit("x340 y28 w120", "")
        this.dirEdit.OnEvent("Change", (*) => this.UpdatePathSummary())

        browseBtn := this.gui.AddButton("x465 y27 w48 h24", "Add")
        browseBtn.OnEvent("Click", (*) => this.SelectFolder())

        removeBtn := this.gui.AddButton("x516 y27 w48 h24", "Remove")
        removeBtn.OnEvent("Click", (*) => this.RemoveFolder())

        ; Add the path summary label to display the currently active paths
        this.pathSummaryLabel := this.gui.AddText("x20 y65 w540 cGray", "Active Paths: All Drives")

        ; --- Filter options ---
        this.gui.AddGroupBox("x10 y105 w560 h150", "Filter Options")

        ; Left side: Filename and Extension filters
        this.gui.AddText("x20 y128 w80", "Filename:")
        this.nameEdit := this.gui.AddEdit("x100 y125 w200", "*")
        this.gui.AddText("x100 y150 w200 cGray", "(e.g. *test* or file?.txt)")

        this.gui.AddText("x20 y178 w80", "Extensions:")
        this.extEdit := this.gui.AddEdit("x100 y175 w200", "*.exe; *.dll; *.iso")
        this.gui.AddText("x100 y200 w200 cGray", "(Semicolon separated)")

        ; Right side: File size range filters
        this.gui.AddGroupBox("x315 y120 w240 h125", "File Size Range")
        this.gui.AddText("x325 y143 w80", "Min Size:")
        this.minSizeEdit := this.gui.AddEdit("x410 y140 w130", "0 MB")
        
        this.gui.AddText("x325 y178 w80", "Max Size:")
        this.maxSizeEdit := this.gui.AddEdit("x410 y175 w130", "0 MB")
        this.gui.AddText("x325 y210 w220 cGray", "Units: B, KB, MB, GB (Default: MB)")

        ; --- Action Button ---
        this.startBtn := this.gui.AddButton("x10 y265 w560 h28 Default", "Start Scan")
        this.startBtn.OnEvent("Click", (*) => this.HandleStart())

        ; --- Progress & Status ---
        this.progressBar := this.gui.AddProgress("x10 y300 w560 h12 Range0-100", 0)
        this.statusLabel := this.gui.AddText("x10 y317 w560 h18", "Ready")

        ; --- ListView Controls ---
        this.selectAllBtn := this.gui.AddButton("x10 y340 w90 h24", "Select All")
        this.selectAllBtn.OnEvent("Click", (*) => this.ToggleSelectAll())

        this.moveBtn := this.gui.AddButton("x105 y340 w110 h24 Disabled", "Move Selected")
        this.moveBtn.OnEvent("Click", (*) => this.HandleMove())

        ; --- Results Table ---
        this.resultsLV := this.gui.AddListView("x10 y370 w560 h220 Checked", ["File Name", "Size", "Path", "Hash", "Bytes"])
        this.resultsLV.OnEvent("ItemCheck", (*) => this.UpdateMoveButtonState())
        this.resultsLV.ModifyCol(1, 140)
        this.resultsLV.ModifyCol(2, 80)
        this.resultsLV.ModifyCol(3, 230)
        this.resultsLV.ModifyCol(4, 90)
        this.resultsLV.ModifyCol(5, 0) ; hidden column for raw byte size
        this.resultsLV.OnEvent("ColClick", (lv, col) => this.OnColClick(lv, col))

        ; --- Status Bar ---
        this.sb := this.gui.AddStatusBar()
        this.sb.SetText(" Ready")

        ; Load settings and show the GUI
        this.LoadSettings()
        this.UpdatePathSummary()
        this.gui.Show("w580 h600")
    }


    /**
     * Updates the status bar text with the provided message.
     * @param {string} msg - The message to display in the status bar.
     */
    UpdateStatus(msg) {
        this.sb.SetText(" " . msg)
    }

    /**
     * Handles the GUI resize event, adjusting the size and position of controls accordingly.
     * @param {int} width - The new width of the GUI window.
     * @param {int} height - The new height of the GUI window.
     */
    OnResize(width, height) {
        if (width < 300 || height < 400)
            return
        this.progressBar.Move(,, width - 20)
        this.statusLabel.Move(,, width - 20)
        this.pathSummaryLabel.Move(,, width - 40)
        this.startBtn.Move(,, width - 20)
        this.resultsLV.Move(,, width - 20, height - 380)
    }

    /**
     * Event handler for when the drive selection changes. Updates the path summary accordingly.
     */
    OnDriveChange() {
        this.UpdatePathSummary()
    }

    /**
     * Opens a folder selection dialog and adds the selected folder to the directory edit field.
     * Updates the path summary after adding the folder.
     */
    SelectFolder() {
        local selectedDir
        if (selectedDir := DirSelect("", 3, "Select Target Folder")) {
            if (Trim(this.dirEdit.Value) == "") {
                this.dirEdit.Value := selectedDir
            } else {
                this.dirEdit.Value := this.dirEdit.Value "; " selectedDir
            }
            this.UpdatePathSummary()
        }
    }

    /**
     * Removes the last folder from the directory edit field and updates the path summary.
     */
    RemoveFolder() {
        local rawText := Trim(this.dirEdit.Value)
        if (rawText == "")
            return

        local paths := StrSplit(rawText, ";")
        local cleanPaths := []
        
        for p in paths {
            if (Trim(p) != "")
                cleanPaths.Push(Trim(p))
        }

        ; Remove the last element (pop)
        if (cleanPaths.Length > 0) {
            cleanPaths.Pop()
            
            local newText := ""
            for index, p in cleanPaths {
                newText .= (index > 1 ? "; " : "") . p
            }
            this.dirEdit.Value := newText
            this.UpdatePathSummary()
        }
    }

    /**
     * Retrieves the target paths based on the current GUI settings.
     * If a folder is specified in the directory edit field, it takes precedence.
     * Otherwise, it uses the selected drive and system inclusion settings.
     * @return {Array} An array of target paths.
     */
    GetTargetPaths() {
        local pathArray := []
        local rawText := Trim(this.dirEdit.Value)

        ; If the folder field is not empty, parse it and return the paths
        if (rawText != "") {
            Loop Parse, rawText, ";" {
                cleanPath := Trim(A_LoopField)
                if (cleanPath != "") {
                    alreadyExists := false
                    for existing in pathArray {
                        if (StrLower(RTrim(existing, "\")) == StrLower(RTrim(cleanPath, "\"))) {
                            alreadyExists := true
                            break
                        }
                    }
                    if (!alreadyExists)
                        pathArray.Push(cleanPath)
                }
            }
            return pathArray
        }

        ; If the folder field is empty, use the drive selection
        if (this.driveDDL.Text == "All Drives") {
            for drive in StrSplit(DriveGetList()) {
                if (!this.includeSysCB.Value && StrUpper(drive) == "C")
                    continue
                pathArray.Push(drive . ":\")
            }
        } else {
            pathArray.Push(this.driveDDL.Text)
        }

        return pathArray
    }

    /**
     * Updates the path summary label based on the current target paths.
     * Displays "Active Paths: None" if no paths are selected, or lists the active paths otherwise.
     */
    UpdatePathSummary() {
        local paths := this.GetTargetPaths()
        if (paths.Length == 0) {
            this.pathSummaryLabel.Value := "Active Paths: None"
        } else {
            local summaryStr := ""
            for index, p in paths {
                summaryStr .= (index > 1 ? " | " : "") . p
            }
            this.pathSummaryLabel.Value := "Active Paths (" . paths.Length . "): " . summaryStr
        }
    }
    
    /**
     * Parses a size string (e.g., "10 MB", "500 KB") and converts it to bytes.
     * @param {string} sizeStr - The size string to parse.
     * @return {int} The size in bytes.
     */
    ParseSizeToBytes(sizeStr) {
        local num, unit
        sizeStr := Trim(StrLower(sizeStr))
        if (sizeStr == "" || sizeStr == "0")
            return 0

        if RegExMatch(sizeStr, "^([\d\.]+)\s*([a-z]*)$", &match) {
            num := Float(match[1])
            unit := match[2]
            switch unit {
                case "b":  return num
                case "kb": return num * 1024
                case "gb": return num * 1073741824
                default:   return num * 1048576 ; Default: MB
            }
        }
        return 0
    }

    /**
     * Handles the start button click event. Saves settings and invokes the onStartCallback with the current parameters.
     */
    HandleStart() {
        local params
        this.SaveSettings()

        params := {
            targetPaths: this.GetTargetPaths(),
            drive: this.driveDDL.Text,
            includeSystem: (this.includeSysCB.Value == 1),
            filenamePattern: this.nameEdit.Value,
            extensions: this.extEdit.Value,
            minSizeBytes: this.ParseSizeToBytes(this.minSizeEdit.Value),
            maxSizeBytes: this.ParseSizeToBytes(this.maxSizeEdit.Value)
        }

        if (this.onStartCallback)
            this.onStartCallback(params)
    }

    /**
     * Toggles selection state of duplicate items in the ListView.
     * Always skips and unchecks the first (original) file of each hash group.
     */
    ToggleSelectAll() {
        local hasUnchecked := false

        Loop this.resultsLV.GetCount() {
            if (this.resultsLV.GetNext(A_Index - 1, "Checked") != A_Index) {
                hasUnchecked := true
                break
            }
        }

        if (hasUnchecked)
            this.resultsLV.Modify(0, "Check")
        else
            this.resultsLV.Modify(0, "-Check")

        this.UpdateMoveButtonState()
    }

    /**
     * Updates the enabled state of the "Move Selected" button based on whether any items are checked in the results ListView.
     */
    UpdateMoveButtonState() {
        local hasChecked := 0
        local rowNumber := 0

        while (rowNumber := this.resultsLV.GetNext(rowNumber, "Checked")) {
            hasChecked := 1
            
            ; Note: You can retrieve the file path of the checked item if needed using:
            filePath := this.resultsLV.GetText(rowNumber, 3)
        }
        this.moveBtn.Enabled := hasChecked
    }

    /**
     * Collects selected items for moving.
     * Automatically filters out the first (original) instance of each hash group.
     */
    HandleMove() {
            local selectedItems := []
            local Row := 0

            Loop {
                Row := this.resultsLV.GetNext(Row, "Checked")
                if !Row
                    break

                selectedItems.Push({
                    row: Row,
                    filename: this.resultsLV.GetText(Row, 1),
                    sizeMB: this.resultsLV.GetText(Row, 2),
                    path: this.resultsLV.GetText(Row, 3),
                    hash: this.resultsLV.GetText(Row, 4)
                })
            }

            if (selectedItems.Length == 0) {
                MsgBox("No duplicate files selected for move operation.", "Move Files", "48")
                return
            }

            if (this.onMoveCallback)
                this.onMoveCallback(selectedItems)
        }

    /**
     * Updates the progress bar and status label with the provided percentage and status text.
     * @param {int} percent - The progress percentage (0-100).
     * @param {string} statusText - The status message to display.
     */
    UpdateProgress(percent, statusText) {
        this.progressBar.Value := percent
        this.statusLabel.Value := statusText
    }

    /**
     * Handles the column click event in the results ListView. Sorts the ListView based on the clicked column.
     * If the "Size" column (2nd column) is clicked, it sorts based on the hidden "Bytes" column (5th column).
     * @param {Object} lv - The ListView object.
     * @param {int} col - The index of the clicked column.
     */
    OnColClick(lv, col) {
        static sortDesc := false
        ; If the "Size" column (2nd column) is clicked, sort by the hidden "Bytes" column (5th column)
        if (col == 2) {
            sortDesc := !sortDesc
            lv.ModifyCol(5, sortDesc ? "SortDesc" : "Sort")
        }
    }

    /**
     * Adds a new row to the results ListView with the provided file information.
     * @param {string} filename - The name of the file.
     * @param {string} size - The formatted size of the file (e.g., "10 MB").
     * @param {string} path - The full path to the file.
     * @param {string} hash - The hash value of the file (optional).
     * @param {int} rawBytes - The raw size of the file in bytes (optional).
     */
    AddResultRow(filename, size, path, hash := "", rawBytes := 0) {
        ; Check if it has already been seen. If so, skip adding this row to avoid duplicates.
        if (hash != "") {
            if (!this.seenHashes.Has(hash)) {
                this.seenHashes[hash] := true
                return
            }
        }

        if (filename == "" && path != "")
            SplitPath(path, &filename)

        local formattedSize := IsNumber(size) ? FormatBytes(size) : size
        
        if (rawBytes == 0 && IsNumber(size))
            rawBytes := size

        local paddedBytes := Format("{:020d}", rawBytes)

        this.resultsLV.Add("", filename, formattedSize, path, hash, paddedBytes)
    }

    /**
     * Clears all rows from the results ListView and resets the seen hashes map.
     */
    ClearResults() {
        this.seenHashes := Map() ; Hash mappa ürítése új keresésnél
        this.resultsLV.Delete()
        this.UpdateMoveButtonState()
    }

    /**
     * Saves the current settings to the INI file.
     */
    SaveSettings() {
        try {
            IniWrite(this.driveDDL.Text, this.iniFile, "Target", "Drive")
            IniWrite(this.includeSysCB.Value, this.iniFile, "Target", "IncludeSystem")
            IniWrite(this.dirEdit.Value, this.iniFile, "Target", "Folders")
            IniWrite(this.nameEdit.Value, this.iniFile, "Filter", "Filename")
            IniWrite(this.extEdit.Value, this.iniFile, "Filter", "Extensions")
            IniWrite(this.minSizeEdit.Value, this.iniFile, "Filter", "MinSize")
            IniWrite(this.maxSizeEdit.Value, this.iniFile, "Filter", "MaxSize")
        }
    }

    /**
     * Loads settings from the INI file and applies them to the GUI controls.
     */
    LoadSettings() {
        if !FileExist(this.iniFile)
            return

        try {
            this.driveDDL.Text := IniRead(this.iniFile, "Target", "Drive", "All Drives")
            this.includeSysCB.Value := Integer(IniRead(this.iniFile, "Target", "IncludeSystem", "0"))
            this.dirEdit.Value := IniRead(this.iniFile, "Target", "Folders", "")
            this.nameEdit.Value := IniRead(this.iniFile, "Filter", "Filename", "*")
            this.extEdit.Value := IniRead(this.iniFile, "Filter", "Extensions", "*.exe; *.dll; *.iso")
            this.minSizeEdit.Value := IniRead(this.iniFile, "Filter", "MinSize", "0 MB")
            this.maxSizeEdit.Value := IniRead(this.iniFile, "Filter", "MaxSize", "0 MB")
        }
    }
}