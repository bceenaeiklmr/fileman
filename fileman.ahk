; Script     fileman.ahk
; License:    MIT License
; Author:     Bence Markiel (bceenaeiklmr)
; Github:     https://github.com/bceenaeiklmr/fileman
; Date        08.08.2026
; Version     0.4.0

#Warn All
#SingleInstance Force


; Global rules
ignoredRules := [
    "System Volume Information", "$RECYCLE.BIN"
    , "E:\utility\Cinebench\", "F:\Steam\steamapps\", "F:\Games\", "F:\iso\"
    , ".gitignore"
]


/**
 * Manages file scanning, directory indexing, duplicate detection, and quarantine operations.
 */
class fileMan {

    /**
     * Initializes a new instance of the fileMan class.
     * @param {Array|String} paths Target paths or drive letters to scan.
     * @param {Boolean} skipRemovable Whether to exclude removable drives from auto-detection.
     * @param {Func|String} statusCallback Callback function triggered during status updates.
     * @param {Array|String} ignoredRules List of patterns, directories, or extensions to skip.
     * @param {Integer} workers Number of worker threads for hashing (0 auto-detects physical cores).
     */
    __New(paths := "", skipRemovable := true, statusCallback := "", ignoredRules := [], workers := 0) {
        this.skipRemovable := skipRemovable
        this.statusCallback := statusCallback
        this.progressInterval := 1000
        
        this.ignoredPaths := this.NormalizePaths(ignoredRules)
        this.ParseIgnoredRules(ignoredRules)

        this.availableDrives := this.GetAvailableDrives(skipRemovable)
        this.targetPaths := this.ResolveTargetPaths(paths)

        this.paths := []
        this.folderIndex := Map()
        this.fileIndex := Map()
        this.fileDuplicates := []
        this.verifiedFileDuplicates := []
        this.filesScanned := 0
        this.foldersScanned := 0
        this.totalBytesScanned := 0
        this.workers := workers
    }

    /**
     * Resolves raw path inputs into fully normalized drive or directory target lists.
     * @param {Array|String} paths Input paths provided by the caller.
     * @returns {Array} Array of normalized absolute target paths.
     */
    ResolveTargetPaths(paths) {
        if (paths == "" || (Type(paths) == "Array" && paths.Length == 0)) {
            local targetPaths := []
            for drive in this.availableDrives {
                targetPaths.Push(drive . ":\")
            }
            return targetPaths
        }
        return this.NormalizePaths(paths)
    }

    /**
     * Enumerates currently mounted logical drives on the system.
     * @param {Boolean} skipRemovable Excludes removable media if true.
     * @returns {Array} List of available drive letter identifiers (e.g., ["C", "D"]).
     */
    GetAvailableDrives(skipRemovable := true) {
        local drives := []
        for drive in StrSplit(DriveGetList()) {
            if (skipRemovable && (DriveGetType(drive ":\") == "Removable"))
                continue
            drives.Push(drive)
        }
        return drives
    }

    /**
     * Maps drive letters to their root directory representations.
     * @param {Array|String} drivesInput Drives to normalize into the map.
     * @returns {Map} Key-value pairs mapping drive letters to root paths.
     */
    BuildDriveMap(drivesInput := "") {
        local drives := Map()
        for drive in this.NormalizeDrives(drivesInput)
            drives[drive] := drive . ":\"
        return drives
    }

    /**
     * Normalizes drive inputs into clean, uppercase drive letters.
     * @param {Array|String} drivesInput Raw input containing drive indicators.
     * @returns {Array} Array of cleaned uppercase drive letters.
     */
    NormalizeDrives(drivesInput := "") {
        local result := []
        if (Type(drivesInput) == "Array") {
            for item in drivesInput
                this.TryAddDrive(result, item)
        }
        else if (Type(drivesInput) == "String" && drivesInput != "") {
            delim := get_delimiter(drivesInput)
            driveList := (delim) ? StrSplit(drivesInput, delim) : [drivesInput]

            for item in driveList
                this.TryAddDrive(result, item)
        }
        else {
            for drive in this.availableDrives
                result.Push(drive)
        }
        return result
    }

    /**
     * Validates and appends a drive letter to an existing array if not already present.
     * @param {Array} arr Target array.
     * @param {String} rawDrive Uncleaned drive string.
     */
    TryAddDrive(arr, rawDrive) {
        local drive := StrUpper(Trim(rawDrive, " `t`r`n:\\/"))
        if (drive == "")
            return
        if (!this.DriveExistsInArray(arr, drive))
            arr.Push(drive)
    }

    /**
     * Checks if a drive letter already exists in an array.
     * @param {Array} arr Target array.
     * @param {String} drive Drive letter to match.
     * @returns {Boolean} True if present, false otherwise.
     */
    DriveExistsInArray(arr, drive) {
        for item in arr {
            if (item == drive)
                return true
        }
        return false
    }

    ; --- Ignore rules & filtering ---

    /**
     * Parses ignore criteria into internal lookup maps for fast filtering during scans.
     * @param {Array|String} rawRules Single rule or array of ignore patterns.
     */
    ParseIgnoredRules(rawRules) {
        this.ignoredExts      := Map()
        this.ignoredNames     := Map()
        this.ignoredFullPaths := Map()
        this.ignoredDirs      := Map()

        rules := !(rawRules is Array) ? [rawRules] : rawRules

        for item in rules {
            clean := StrLower(Trim(item))
            if (clean == "")
                continue

            if RegExMatch(clean, "^[a-z]:\\?$") {
                clean := SubStr(clean, 1, 2) . "\"
            } else if InStr(clean, "\") {
                clean := RTrim(clean, "\")
            }

            if RegExMatch(clean, "^[a-z]:")
                this.ignoredFullPaths[clean] := true
            else if (SubStr(clean, 1, 1) == "." && !InStr(clean, "\"))
                this.ignoredExts[clean] := true
            else if InStr(clean, "\")
                this.ignoredDirs[Trim(clean, "\")] := true
            else
                this.ignoredNames[clean] := true
        }
    }

    /**
     * Evaluates whether a specific file or path matches any exclusion criteria.
     * @param {String} filePath Full path of the file.
     * @param {String} fileName File name including extension.
     * @param {String} fileExt File extension string.
     * @returns {Boolean} True if file matches an ignore rule, false otherwise.
     */
    IsIgnored(filePath, fileName, fileExt) {
        if (fileExt != "" && this.ignoredExts.Has("." . fileExt))
            return true

        if (this.ignoredNames.Has(fileName))
            return true

        if (this.ignoredFullPaths.Has(filePath))
            return true

        if (this.ignoredDirs.Count > 0) {
            p := 1
            while (p := InStr(filePath, "\", 0, p)) {
                pNext := InStr(filePath, "\", 0, p + 1)
                len := pNext ? (pNext - p - 1) : 0
                if (len > 0) {
                    segment := SubStr(filePath, p + 1, len)
                    if (this.ignoredDirs.Has(segment))
                        return true
                }
                if (!pNext)
                    break
                p := pNext
            }
        }
        return false
    }

    /**
     * Evaluates whether a full directory path falls within an ignored path tree.
     * @param {String} path Path string to evaluate.
     * @returns {Boolean} True if ignored, false otherwise.
     */
    IsIgnoredPath(path) {
        local normalized := StrLower(path)
        
        for ignored in this.ignoredPaths {
            local target := StrLower(Trim(ignored))
            if (target == "")
                continue
            if (normalized == target || InStr(normalized, target . "\") == 1)
                return true

            local cleanTarget := LTrim(target, "\")

            if InStr(normalized, "\" . cleanTarget) {
                if (SubStr(normalized, -StrLen(cleanTarget)) == cleanTarget || InStr(normalized, "\" . cleanTarget . "\"))
                    return true
            }
        }
        return false
    }

    /**
     * Cleans and normalizes array of paths into standardized path strings.
     * @param {Array|String} paths Input path(s).
     * @returns {Array} Normalized path array.
     */
    NormalizePaths(paths) {
        if (Type(paths) != "Array")
            paths := [paths]

        normalized := []
        for path in paths {
            cleanPath := StrLower(Trim(path))
            if (cleanPath == "")
                continue
                
            if RegExMatch(cleanPath, "^[a-z]:\\?$") {
                cleanPath := SubStr(cleanPath, 1, 2) . "\"
            } else {
                cleanPath := RTrim(cleanPath, "\")
            }
                
            normalized.Push(cleanPath)
        }
        return normalized
    }

    ; --- File Scanning & Directory Traversal ---

    /**
     * Executes the scanning process across configured target paths.
     * @param {Boolean} verify If true, runs multi-threaded SHA-256 validation on size/name matches.
     */
    Scan(verify := false) {
        this.paths := []
        this.folderIndex := Map()
        this.fileIndex := Map()
        this.fileDuplicates := []
        this.verifiedFileDuplicates := []
        this.filesScanned := 0
        this.foldersScanned := 0
        this.totalBytesScanned := 0
        startedAt := A_TickCount

        this.EmitStatus("Starting scan.")

        for path in this.targetPaths {
            if (FileExist(path)) {
                this.EmitStatus("Scanning " . path)
                this.MapPath(path)
            }
        }

        this.EmitStatus("Finding file duplicates.")
        this.fileDuplicates := this.BuildDuplicates(this.fileIndex)
        
        elapsed := Round((A_TickCount - startedAt) / 1000, 1)
        this.EmitStatus("Finished in " . elapsed . " seconds. " . this.filesScanned . " files and " . this.foldersScanned . " folders scanned.")

        if (verify && this.fileDuplicates.Length > 0) {
            this.host := Host()
            this.host.AddWorker(this.workers, "Worker.ahk")
            this.EmitStatus("Starting SHA-256 verification of " . this.fileDuplicates.Length . " duplicate groups.")
            this.VerifyFileDuplicates()
            this.host.Close()
        }
    }

    StartScan(guiApp, params) {
        guiApp.ClearResults()
        guiApp.UpdateProgress(5, "Scanning files...")

        ; Convert minSizeMB and maxSizeMB to bytes for filtering
        minBytes := params.minSizeMB * 1048576
        maxBytes := params.maxSizeMB * 1048576

        ; Extension filtering: build a map of valid extensions for quick lookup
        validExts := Map()
        if (params.HasOwnProp("extensions") && params.extensions != "") {
            for ext in StrSplit(params.extensions, [";", ","], " ") {
                cleanExt := Trim(LTrim(ext, "*."))
                if (cleanExt != "")
                    validExts[StrLower(cleanExt)] := true
            }
        }

        ; Collect files from the specified directories
        matchedFiles := []
        
        ; Supports both params.targetPaths array and single params.targetPath
        targetPaths := params.HasOwnProp("targetPaths") ? params.targetPaths : [params.targetPath]

        for targetDir in targetPaths {
            if (targetDir == "" || !DirExist(targetDir))
                continue

            Loop Files, RTrim(targetDir, "\") "\*.*", "R" {
                
                ; Minimum and Maximum file size
                if (minBytes > 0 && A_LoopFileSize < minBytes)
                    continue
                if (maxBytes > 0 && A_LoopFileSize > maxBytes)
                    continue

                ; Extension check
                if (validExts.Count > 0) {
                    if (!validExts.Has(StrLower(A_LoopFileExt)))
                        continue
                }

                ; Filename pattern (Substring)
                if (params.filenamePattern != "*" && params.filenamePattern != "") {
                    cleanPattern := StrReplace(params.filenamePattern, "*", "")
                    if (cleanPattern != "" && !InStr(A_LoopFileName, cleanPattern))
                        continue
                }

                matchedFiles.Push(A_LoopFilePath)
            }
        }

        if (matchedFiles.Length == 0) {
            guiApp.UpdateProgress(100, "No files matched the specified criteria.")
            return
        }

        guiApp.UpdateProgress(20, "Found " . matchedFiles.Length . " files. Dispatching to workers...")

        ; Pass the filtered list to the workers
        this.DispatchToWorkers(guiApp, matchedFiles)
    }

    /**
     * Dispatches a list of files to worker threads for hashing and duplicate verification.
     * @param {Object} guiApp GUI application instance for progress updates.
     * @param {Array} fileList List of file paths to process.
     */
    DispatchToWorkers(guiApp, fileList) {
        if (!this.HasOwnProp("host") || !this.host) {
            this.host := Host()
            this.host.AddWorker(this.workers, "Worker.ahk")
        }

        for filePath in fileList {
            this.host.Queue(filePath)
        }

        startTime := A_TickCount
        
        ; Progress callback updating the GUI during hashing
        onProgress(current, total, bytesRead := 0) {
            percent := (total > 0) ? Round((current / total) * 60) : 0
            guiApp.UpdateProgress(
                20 + percent,
                Format("Hashing: {} / {} ({})", current, total, FormatBytes(bytesRead))
            )
        }

        hashIndex := this.host.Start(200, onProgress)

        this.hashDuration := (A_TickCount - startTime) / 1000
        this.verifiedFileDuplicates := this.BuildDuplicates(hashIndex)
        this.host.Close()
    }

    /**
     * Traverses a folder hierarchy non-recursively using a stack-based loop.
     * @param {String} path Root folder path to traverse.
     */
    MapPath(path) {
        if (!FileExist(path))
            return

        foldersToScan := [path]
        while (foldersToScan.Length) {
            currentPath := foldersToScan.Pop()
            pattern := currentPath . (SubStr(currentPath, -1) == "\" ? "*" : "\*")

            loop Files, pattern, "DF" {
                if (this.IsIgnored(StrLower(A_LoopFileFullPath), A_LoopFileName, A_LoopFileExt))
                    continue

                if (InStr(A_LoopFileAttrib, "D")) {
                    this.foldersScanned += 1
                    foldersToScan.Push(A_LoopFileFullPath)
                }
                else {
                    this.filesScanned += 1
                    this.AddFile(A_LoopFileName, A_LoopFileSize, A_LoopFileFullPath)
                }
                this.ReportProgress()
            }
        }
    }

    /**
     * Indexes a scanned file using a preliminary key composed of name and size.
     * @param {String} name File name.
     * @param {Integer} size File size in bytes.
     * @param {String} path Absolute file path.
     */
    AddFile(name, size, path) {
        local key := StrLower(name) . "|" . size
        if (!this.fileIndex.Has(key))
            this.fileIndex[key] := []
        this.fileIndex[key].Push(path)

        this.totalBytesScanned += size
    }

    ; Duplicate identification & verification

    /**
     * Filters indexed maps to isolate keys containing more than one matching file.
     * @param {Map} indexObj Object mapping identifiers to arrays of paths.
     * @returns {Array} Array of duplicate group objects ({key, paths}).
     */
    BuildDuplicates(indexObj) {
        local duplicates := []
        for key, locations in indexObj {
            if (locations.Length > 1)
                duplicates.Push({key: key, paths: locations})
        }
        return duplicates
    }

    /**
     * Queues candidate duplicate files and dispatches them across worker threads for SHA-256 verification.
     * @returns {Array} Confirmed cryptographic duplicate groups.
     */
    VerifyFileDuplicates() {
        local files := [], path, file

        for group in this.fileDuplicates {
            for path in group.paths
                files.Push(path)
        }

        this.EmitStatus("Starting SHA-256 workers for " . files.Length . " files.")

        for file in files {
            this.host.Queue(file)
        }

        startTime := A_TickCount
        local hashIndex := this.host.Start(1000, onHashProgress)
        this.hashDuration := (A_TickCount - startTime) / 1000

        this.verifiedFileDuplicates := this.BuildDuplicates(hashIndex)
        this.EmitStatus("SHA-256 verification complete: " . this.verifiedFileDuplicates.Length . " confirmed duplicate groups.")

        return this.verifiedFileDuplicates

        /**
         * Nested callback to receive hashing progress reports from the Host instance.
         */
        onHashProgress(current, total, bytesRead := 0) {
            local percent := (total > 0) ? Round((current / total) * 100, 1) : 0
            this.EmitStatus("Hashing progress: " . current . " / " . total . " (" . percent . "%) | Read: " . FormatBytes(bytesRead))
        }
    }

    ; --- Quarantine & File Actions ---

    /**
     * Calculates candidate file counts and total byte space recoverable by purging duplicates.
     * @returns {Object} Object structured as {fileCount: Integer, bytes: Integer}.
     */
    GetReclaimableSpaceSummary() {
        local summary := {fileCount: 0, bytes: 0}
        
        for group in this.verifiedFileDuplicates {
            for path in group.paths {
                if (A_Index == 1)
                    continue
                if (FileExist(path)) {
                    summary.fileCount += 1
                    summary.bytes += FileGetSize(path)
                }
            }
        }
        return summary
    }

    /**
     * Relocates verified duplicate files into a quarantine directory structure.
     * @param {String} quarantineRoot Destination root folder for isolated files.
     * @param {Boolean} dryRun If true, previews file operations without executing disk changes.
     * @returns {Object} Execution metrics detailing moved, skipped, and action items.
     */
    MoveVerifiedDuplicates(quarantineRoot, dryRun := true) {
        local result := {moved: 0, skipped: 0, bytes: 0, actions: []}
        quarantineRoot := RTrim(quarantineRoot, "\\")

        for groupNumber, group in this.verifiedFileDuplicates {
            for srcPath in group.paths {
                if (A_Index == 1)
                    continue
                if (!FileExist(srcPath)) {
                    result.skipped += 1
                    continue
                }

                dstFolder := quarantineRoot . "\\group_" . groupNumber
                SplitPath(srcPath, &fileName)
                dstPath := dstFolder . "\\" . A_Index . "_" . fileName
                result.actions.Push({source: srcPath, destination: dstPath})
                result.bytes += FileGetSize(srcPath)

                if (!dryRun) {
                    DirCreate(dstFolder)
                    try {
                        FileMove(srcPath, dstPath)
                        result.moved += 1
                    }
                    catch {
                        result.skipped += 1
                    }
                }
            }
        }
        return result
    }

    ; --- Reporting & Status Output ---

    /**
     * Generates a plain-text summary report of current scan data and stats.
     * @returns {String} Formatted summary output string.
     */
    Report() {
        local spaceSummary := this.GetReclaimableSpaceSummary()
        local bytesRead := this.HasOwnProp("host") ? this.host.bytesRead : 0

        return "Available drives: "          . this.Join(this.availableDrives, ", ")       . "`n"
            .  "Target paths: "              . this.Join(this.targetPaths, ", ")           . "`n"
            .  "Total files scanned: "       . this.filesScanned                           . "`n"
            .  "Total folders scanned: "     . this.foldersScanned                         . "`n"
            .  "Total scanned size: "        . FormatBytes(this.totalBytesScanned)         . "`n"
            .  "File duplicates: "           . this.fileDuplicates.Length                  . "`n"
            .  "Verified duplicate groups: " . this.verifiedFileDuplicates.Length          . "`n"
            .  "Total read: "                . FormatBytes(bytesRead)                      . "`n"
            .  "Read speed: "                . this.ReadSpeed()                            . "`n"
            .  "Files to move: "             . spaceSummary.fileCount                      . "`n"
            .  "Recoverable space: "         . FormatBytes(spaceSummary.bytes)             . "`n"
            .  "`n"                          . this.GetFileDuplicateReport()
    }

    /**
     * Writes generated text report to a timestamped file on disk.
     * @param {String} dirName Target directory to output the report file.
     * @returns {String} Full file path of written report, or empty string on failure.
     */
    SaveReport(dirName := "reports") {
        if (!DirExist(dirName)) {
            DirCreate(dirName)
        }

        timestamp := FormatTime(A_Now, "MM_dd_yyyy_HH_mm_ss")
        filePath := dirName . "\report_" . timestamp . ".txt"
        str := this.Report()
        
        try {
            FileAppend(str, filePath, "UTF-8")
            this.EmitStatus("Report saved to: " . filePath)
            return filePath
        } catch Error as e {
            this.EmitStatus("Error saving report: " . e.Message)
            return ""
        }
    }

    /**
     * Formats detailed list of all identified duplicate file groups.
     * @returns {String} Multi-line breakdown of duplicate files.
     */
    GetFileDuplicateReport() {
        report := ""
        for group in this.fileDuplicates {
            report .= "Duplicate group: " . group.key . "`n"
            for path in group.paths
                report .= "  " . path . "`n"
            report .= "`n"
        }
        return report
    }

    /**
     * Emits periodic scanning progress messages based on progressInterval threshold.
     */
    ReportProgress() {
        scanned := this.filesScanned + this.foldersScanned
        if (Mod(scanned, this.progressInterval) == 0)
            this.EmitStatus("Scanned " . this.filesScanned . " files and " . this.foldersScanned . " folders.")
    }

    /**
     * Dispatches status message to caller statusCallback or debug console.
     * @param {String} msg Message payload.
     */
    EmitStatus(msg) {
        (IsObject(this.statusCallback))
            ? this.statusCallback.Call(msg, this)
            : OutputDebug(msg)
    }

    ; --- Helper Utilities ---

    /**
     * Calculates throughput hashing speed based on byte processing time.
     * @returns {String} Formatted speed metric string (e.g., "120.50 MB/s").
     */
    ReadSpeed() {
        local bytesRead := this.HasOwnProp("host") ? this.host.bytesRead : 0
        local speed := (this.HasOwnProp("hashDuration") && this.hashDuration > 0) 
            ? (bytesRead / this.hashDuration) : 0
        return FormatBytes(speed) . "/s"
    }

    /**
     * Joins array elements into a delimited string.
     * @param {Array} arr Input array.
     * @param {String} delim Separator character(s).
     * @returns {String} Concatenated string.
     */
    Join(arr, delim := ", ") {
        out := ""
        for index, value in arr {
            if (index > 1)
                out .= delim
            out .= value
        }
        return out
    }
}


/**
 * Host controller managing IPC inter-process communication, worker processes, and job dispatching.
 */
class Host {

    bytesRead := 0

    /**
     * Instantiates the Host framework and registers active COM object interfaces.
     */
    __New() {
        this.workers := []
        this.shared := {}
        this.GUID := CreateGUID()

        this.shared.worker := {}
        ObjRegisterActive(this.shared.worker, this.GUID)

        this.chunkSize := 2 ** 9
        this.hashIndex := Map()
        this.jobs := []
        Persistent()
    }

    /**
     * Adds an item to the processing job queue.
     * @param {Any} data Job file target payload.
     */
    Queue(data) {
        this.jobs.Push(data)
    }

    /**
     * Spawns worker process instances to process queued jobs.
     * @param {Integer} workers Total worker threads to spawn.
     * @param {String} scriptPath File path to worker script.
     */
    AddWorker(workers := 0, scriptPath := "Worker.ahk") {
        if (workers <= 0)
            workers := GetPhysicalCoreCount()
        
        loop workers {
            w := Worker(scriptPath, this.GUID, this.chunkSize)

            this.shared.worker.%w.id% := {
                state: "idle",
                job: [],
                result: [],
                bytesRead: 0
            }

            this.workers.Push(w)
        }
    }

    /**
     * Terminates child worker processes.
     */
    Close() {
        for w in this.workers {
            (w.pid) ? ProcessClose(w.pid) : ""
        }
    }

    /**
     * Dispatches queued jobs across active worker instances until work is complete.
     * @param {Integer} interval Progress update polling frequency in milliseconds.
     * @param {Func} progressCallback Callback function to receive execution metrics.
     * @returns {Map} Mapped dictionary of output SHA-256 hashes to file path arrays.
     */
    Start(interval := 200, progressCallback := "") {
        local worker
        for worker in this.workers {
            worker.Run()
        }

        Sleep(500)

        total := this.jobs.Length
        processedCount := 0
        lastReportTime := A_TickCount
        this.bytesRead := 0

        Loop {
            for workerObj in this.workers {
                id := workerObj.id
                shared := this.shared.worker.%id%

                if (shared.state == "finished") {
                    if (shared.HasProp("bytesRead")) {
                        this.bytesRead += shared.bytesRead
                        shared.bytesRead := 0
                    }

                    jobPaths := []
                    jobPaths.Capacity := shared.job.Length
                    for p in shared.job
                        jobPaths.Push(p)

                    resultHashes := []
                    resultHashes.Capacity := shared.result.Length
                    for h in shared.result
                        resultHashes.Push(h)

                    loop jobPaths.Length {
                        path := jobPaths[A_Index]
                        hash := (A_Index <= resultHashes.Length) ? resultHashes[A_Index] : ""

                        if (hash != "") {
                            if (!this.hashIndex.Has(hash)) {
                                this.hashIndex[hash] := []
                            }
                            this.hashIndex[hash].Push(path)
                        }
                    }

                    processedCount += jobPaths.Length
                    shared.job := []
                    shared.result := []
                    shared.state := "idle"
                }

                if (shared.state == "idle" && this.jobs.Length > 0) {
                    count := Min(this.chunkSize, this.jobs.Length)
                    chunk := []
                    chunk.Capacity := count
                    
                    loop count {
                        chunk.Push(this.jobs.Pop())
                    }

                    shared.result := []
                    shared.job := chunk
                    shared.state := "working"
                }
            }

            if (progressCallback && (A_TickCount - lastReportTime > interval || processedCount == total)) {
                if (progressCallback.MaxParams >= 3)
                    progressCallback.Call(processedCount, total, this.bytesRead)
                else
                    progressCallback.Call(processedCount, total)
                    
                lastReportTime := A_TickCount
            }

            if (this.jobs.Length == 0 && !this.HasActiveWorkers())
                break

            Sleep(10)
        }

        return this.hashIndex
    }

    /**
     * Checks if any workers are actively processing job chunks.
     * @returns {Boolean} True if active jobs remain in worker memory, false if idle.
     */
    HasActiveWorkers() {
        for workerObj in this.workers {
            if (this.shared.worker.%workerObj.id%.state !== "idle")
                return true
        }
        return false
    }
}

/**
 * Handles initialization and process creation parameters for individual child worker instances.
 */
class worker {

    static id := 0

    /**
     * Initializes single worker instance payload details.
     * @param {String} script Path to the worker script.
     * @param {String} GUID Shared active COM registration GUID.
     * @param {Integer} chunkSize Maximum processing job size allowed per batch.
     */
    __New(script, GUID, chunkSize) {
        this.id := %this.__Class%.id += 1
        this.pid := 0
        this.script := script
        this.GUID := GUID
        this.chunkSize := chunkSize
    }

    /**
     * Spawns worker process using command-line arguments.
     */
    Run() {
        cmd := Format('"{}" "{}" {} {} {} {}', 
            A_AhkPath, A_ScriptDir "\" this.script, 
            this.GUID, this.id, A_ScriptHwnd, this.chunkSize
        )
        Run(cmd, "", "", &pid)
        this.pid := pid
    }
}


; Standalone Functions

/**
 * Credits: lexikos https://www.autohotkey.com/boards/viewtopic.php?t=6148
 * Registers an object in the Running Object Table (ROT) via oleaut32 API calls.
 * @param {Object} obj Active object to register.
 * @param {String} CLSID Unique GUID string representation.
 * @param {Integer} Flags Registration flags.
 */
ObjRegisterActive(obj, CLSID, Flags := 0) {
    static cookieJar := Map()
    if (!CLSID) {
        if (cookie := cookieJar.Remove(obj)) != ""
            DllCall("oleaut32\RevokeActiveObject", "uint", cookie, "ptr", 0)
        return
    }
    if cookieJar.Has(obj)
        throw Error("Object is already registered", -1)
    _clsid := Buffer(16, 0)
    if (hr := DllCall("ole32\CLSIDFromString", "wstr", CLSID, "ptr", _clsid)) < 0
        throw Error("Invalid CLSID", -1, CLSID)
    hr := DllCall("oleaut32\RegisterActiveObject", "ptr", ObjPtr(obj), "ptr", _clsid, "uint", Flags, "uint*", &cookie := 0, "uint")
    if hr < 0
        throw Error(format("Error 0x{:x}", hr), -1)
    cookieJar[obj] := cookie
}

/**
 * Generates a globally unique identifier (GUID) string via system Windows API.
 * @returns {String} Standard string-formatted GUID ({XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}).
 */
CreateGUID() {
    if !DllCall("ole32.dll\CoCreateGuid", "ptr", pguid := Buffer(16, 0)) {
        if (DllCall("ole32.dll\StringFromGUID2", "ptr", pguid, "ptr", sguid := Buffer(78, 0), "int", 78))
            return StrGet(sguid)
    }
    return ""
}

/**
 * Extracts the first matching string delimiter found in an input string.
 * @param {String} str Target string to inspect.
 * @returns {String} Discovered delimiter character.
 */
get_delimiter(str) {
    local delimiter := ",;:`t"
    loop parse, str {
        if (InStr(delimiter, A_LoopField)) {
            return A_LoopField
        }
    }
}

/**
 * Renders the scan and processing progress status (to GUI StatusBar or ToolTip).
 * @param {String} msg Current status message.
 * @param {Integer} [current=0] Number of items processed so far.
 * @param {Integer} [total=0] Total number of items to process.
 */
DisplayScanStatus(msg, current := 0, total := 0) {
    global app

    formattedMsg := msg
    if (total > 0)
        formattedMsg .= " (" . current . "/" . total . ")"

    ; Javítva: app.HasOwnProp("sb") (ponttal)
    if (IsSet(app) && app.HasOwnProp("sb")) {
        app.UpdateStatus(formattedMsg)
    } else {
        ToolTip(formattedMsg)
        if (msg == "")
            ToolTip()
    }
}

/**
 * Converts raw bytes into human-readable data format units.
 * @param {Integer|Float} bytes Number of bytes to convert.
 * @returns {String} Formatted string with size and unit label (e.g., "1.42 GB").
 */
formatBytes(bytes) {
    static units := ["B", "KB", "MB", "GB", "TB"]
    local i := 1
    local val := Float(bytes)
    
    while (val >= 1024 && i < units.Length) {
        val /= 1024.0
        i++
    }
    return Format("{:.2f} {}", val, units[i])
}

/**
 * Queries kernel system information to count available physical processor cores.
 * @returns {Integer} Total physical core count.
 */
GetPhysicalCoreCount() {
    local len, buf, structSize, count, physicalCores

    DllCall("Kernel32\GetLogicalProcessorInformation", "Ptr", 0, "UInt*", &len:=0)
    buf := Buffer(len)
    if (!DllCall("Kernel32\GetLogicalProcessorInformation", "Ptr", buf, "UInt*", &len))
        return 0
    
    structSize := (A_PtrSize == 8) ? 32 : 24
    count := len // structSize
    physicalCores := 0
    
    Loop count {
        offset := (A_Index - 1) * structSize
        relationship := NumGet(buf, offset + A_PtrSize, "UInt")
        if (relationship == 0)
            physicalCores += 1
    }
    return physicalCores
}