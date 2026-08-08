# fileman

A high-performance duplicate file finder built in **AutoHotkey v2**. It utilizes multi-threaded hashing via child worker processes, the native Windows Crypto API (`bcrypt.dll`), and COM-based inter-process communication to process large backup archives in minutes.

---

## Why I Built This

Over years of taking manual backups across external drives, my storage became bloated with redundant folder trees and nested duplicates. 

The first prototype of this script was single-threaded and took **almost 2 hours** to scan through my drive collection. After rewriting the core class to leverage worker processes and native Windows hashing calls, the full scan time dropped to **under 10 minutes**, reclaiming nearly **60 GB** of wasted space. 

It is not an all-in-one file manager, it focuses specifically on finding and isolating exact duplicate files safely and quickly.

---

## Processing Workflow

```text
Target Paths / Drives
|
|-- Phase 1: Size & Name Grouping
|   |-- Unique files -> Discarded
|   |-- Same-size candidates -> Queued for hashing
|
|-- Phase 2: Multi-Threaded Verification
|   |-- Host Controller (fileman.ahk)
|       |-- Worker 1 (bcrypt.dll)
|       |-- Worker 2 (bcrypt.dll)
|       |-- Worker N (bcrypt.dll)
|
|-- Phase 3: Hash Matching
|   |-- Exact SHA-256 matches confirmed
|
|-- Phase 4: Action
    |-- Output to GUI / Headless Log
    |-- Move redundant copies to Quarantine (original protected)
```

---

## Key Capabilities

* **Multi-Threaded SHA-256 Hashing:** Spawns background worker processes (`Worker.ahk`) scaled to physical CPU cores. Hashing is offloaded directly to `bcrypt.dll` via `DllCall`.
* **Two-Pass Verification:** Discards unique files by grouping file sizes first. Cryptographic hashing only runs on size-matched candidates to optimize disk I/O.
* **Original File Protection:** Retains the primary instance of a duplicate set while staging redundant copies for moving or cleanup.
* **Dry-Run & Quarantine:** Safely isolates flagged duplicates into a quarantine directory without immediate deletion.
* **Dual Interface:** Runs as an interactive GUI application (`fileman_gui.ahk`) or as an automated headless script (`fileman_headless.ahk`).

---

## Repository Structure

* `fileman.ahk` – Host process controller, queue scheduler, and main scanner engine (`fileMan`).
* `guimodule.ahk` – Modular GUI (`AppGui`) handling settings persistence, list controls, and action callbacks.
* `fileman_gui.ahk` – GUI launcher entry point.
* `fileman_headless.ahk` – Example script for command-line or headless automation.
* `Worker.ahk` – Background worker script computing SHA-256 hashes in memory chunks.

---

## Requirements

* **AutoHotkey v2.0+** (64-bit recommended) on Windows.

---

## Usage

### GUI Mode
Launch the application wrapper:

```cmd
AutoHotkey64.exe fileman_gui.ahk
```

1. Select drives or click **Add** to queue specific backup folders.
2. Adjust size thresholds (e.g., set `Min Size: 1 MB` to focus on larger media or archives).
3. Click **Start Scan**.
4. Review the results table and click **Move Selected** to stage redundant copies into your chosen quarantine location.

### Embedded / Scripting Mode
Include the library in custom scripts:

```autohotkey
#include fileman.ahk

; Scan specific backup locations
fm := fileMan(["D:\Backups", "E:\Old_HDD"], skipRemovable := false)

; Run indexing and multi-threaded hash verification
fm.Scan(verify := true)

; Move redundant duplicate copies to quarantine (dryRun := true outputs preview)
previewList := fm.MoveVerifiedDuplicates("E:\Quarantine", dryRun := false)
```

---

## License

Distributed under the [MIT License](LICENSE).
