; Script      guimodule.ahk
; License:    MIT License
; Author:     Bence Markiel (bceenaeiklmr)
; Github:     https://github.com/bceenaeiklmr/fileman
; Date        08.08.2026
; Version     0.4.0


; Enables multiple instances of this script to run simultaneously
#SingleInstance Off       

; Caller script passes the following arguments:
GUID := A_Args[1]
id := Integer(A_Args[2])
hHost := Integer(A_Args[3])

; The worker script connects to the shared COM object using the provided GUID and id via ObjRegisterActive
try {
    shared := ComObjActive(GUID).%id%
} catch {
    ExitApp()
}

; The worker script enter the loop, waiting for the shared state to be set to "working" by the caller script.
; When it detects that state, it processes the job and updates the shared result and state accordingly.
loop {
    if (shared.state == "working") {

        ; Create a local copy of the job list to avoid issues with COM object access
        fileList := []
        fileList.Capacity := shared.job.Length
        for p in shared.job
            fileList.Push(p)

        ; Process the job locally
        hashes := []
        hashes.Capacity := fileList.Length
        chunkBytes := 0

        for path in fileList {
            try {
                hashes.Push(GetFileHash(path, &fileBytes))
                chunkBytes += fileBytes
            } catch {
                hashes.Push("")
            }
        }

        ; Update bytes read, result and state in the shared object
        shared.bytesRead := chunkBytes
        shared.result := hashes
        shared.state := "finished"

        ; Notify the host that the job is finished (WM_USER + 0x100)
        PostMessage(0x0500, id, 0, , hHost)
    }

    ; Avoid busy-waiting
    Sleep(10)
}


; Computes the SHA-256 hash of the specified file and outputs total bytes read via VarRef
GetFileHash(path, &bytesProcessed := 0) {

    ; Initialize the SHA-256 hashing context only once and reuse it for all files
    static ctx := InitSHA256()
    
    ; Initialize a static hex table for converting byte values to hexadecimal strings
    static hexTable := getHexTable()

    bytesProcessed := 0

    ; Create a new hash object for this file
    ThrowOnBcryptError(
        DllCall("bcrypt.dll\BCryptCreateHash"
            , "Ptr", ctx.algorithm                       ; Algorithm handle
            , "Ptr*", &hash:=0                           ; Pointer to receive the hash object handle
            , "Ptr", ctx.hashObj.Ptr                     ; Pointer to the hash object
            , "UInt", ctx.hashObj.Size                   ; Size of the hash object
            , "Ptr", 0                                   ; Secret (not used for SHA-256)
            , "UInt", 0                                  ; Flags (not used for SHA-256)
            , "UInt", 0                                  ; Reserved (not used for SHA-256)
            , "Int")                                     ; Return value (0 for success, non-zero for error)
    )

    ; Process the file
    try {
        file := FileOpen(path, "r")
        try {
            ; Process the file in chunks
            while (bytesRead := file.RawRead(ctx.chunk, ctx.chunk.Size)) {
                bytesProcessed += bytesRead
                ; Update the hash with the chunk data
                ThrowOnBcryptError(
                    DllCall("bcrypt.dll\BCryptHashData"
                        , "Ptr", hash                    ; Hash object handle
                        , "Ptr", ctx.chunk.Ptr           ; Pointer to the chunk data
                        , "UInt", bytesRead              ; Size of the chunk data
                        , "UInt", 0                      ; Flags (not used for SHA-256)
                        , "Int")                         ; Return value (0 for success, non-zero for error)
                )
            }

        }
        ; Ensure the file is closed
        finally {
            file.Close()
        }

        ; Finalize the hash and retrieve the result
        ThrowOnBcryptError(
            DllCall("bcrypt.dll\BCryptFinishHash"
                , "Ptr", hash                            ; Hash object handle
                , "Ptr", ctx.hashBuf.Ptr                 ; Pointer to the buffer to receive the hash
                , "UInt", ctx.hashBuf.Size               ; Size of the hash buffer
                , "UInt", 0                              ; Flags (not used for SHA-256)
                , "Int")                                 ; Return value (0 for success, non-zero for error)
        )

        ; Convert the hash bytes to a hexadecimal string representation
        hashText := ""
        Loop ctx.hashBuf.Size {
            hashText .= hexTable[NumGet(ctx.hashBuf, A_Index - 1, "UChar")]
        }
        return hashText
    }
    ; Free up the hash object
    finally {
        DllCall("bcrypt.dll\BCryptDestroyHash", "Ptr", hash)
    }
}

; Initializes the SHA-256 hashing context
InitSHA256() {

    ; Open the SHA-256 algorithm provider
    ThrowOnBcryptError(
        DllCall("bcrypt.dll\BCryptOpenAlgorithmProvider"
            , "Ptr*", &algorithm:=0                      ; Pointer to receive the algorithm handle
            , "WStr", "SHA256"                           ; Algorithm name
            , "Ptr" , 0                                  ; Implementation (0 for default)
            , "UInt", 0                                  ; Flags
            , "Int")                                     ; Return value
    )

    objLength := Buffer(4, 0)

    ThrowOnBcryptError(
        DllCall("bcrypt.dll\BCryptGetProperty"          
            , "Ptr"  , algorithm                         ; Algorithm handle
            , "WStr" , "ObjectLength"                    ; Property name
            , "Ptr"  , objLength.Ptr                     ; Pointer to receive the property value
            , "UInt" , objLength.Size                    ; Size of the property value buffer
            , "UInt*", &bytes:=0                         ; Pointer to receive the number of bytes copied
            , "UInt" , 0                                 ; Flags
            , "Int")                                     ; Return value
    )

    return {
        algorithm: algorithm,
        hashObj: Buffer(NumGet(objLength, 0, "UInt"), 0),
        hashBuf: Buffer(32, 0),
        chunk: Buffer(1024 * 1024, 0)
    }
}

; Returns a map of byte values to their hexadecimal string representations
getHexTable() {
    local h, value
    h := Map()
    h.Capacity := 256
    Loop 256 {
        value := A_Index - 1
        h[value] := SubStr("0123456789ABCDEF", (value >> 4) + 1, 1)
                  . SubStr("0123456789ABCDEF", (value & 15) + 1, 1)
    }
    return h
}

; Throws an error if the status code from a Windows SHA-256 operation is non-zero, indicating failure
ThrowOnBcryptError(status) {
    if (status != 0)
        throw Error("Windows SHA-256 operation failed. Status: " status)
}