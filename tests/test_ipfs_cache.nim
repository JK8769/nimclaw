import std/[unittest, asyncdispatch, os, posix, json]
import ../src/nimclaw/channels/nmobile

proc rmTree(p: string) =
  if dirExists(p):
    for kind, sub in walkDir(p):
      case kind
      of pcDir:
        rmTree(sub)
      of pcFile:
        try: removeFile(sub)
        except: discard
      else:
        discard
    try: removeDir(p)
    except: discard
  elif fileExists(p):
    try: removeFile(p)
    except: discard

suite "IPFS cache":
  setup:
    let tempDir = getTempDir() / "nimclaw_test_ipfs_cache_" & $getpid()
    createDir(tempDir)
    let origBase = getEnv("NIMCLAW_DIR")
    putEnv("NIMCLAW_DIR", tempDir)

  teardown:
    rmTree(tempDir)

    if origBase.len > 0: putEnv("NIMCLAW_DIR", origBase) else: delEnv("NIMCLAW_DIR")

  test "downloads an IPFS CID to per-guest cache dir":
    let src = "guest_test_addr"
    let cid = "QmbXaxBj5LKb13UCiWpBj9qXHjYvEeUN7dfzwpjgqRu7na"
    let opts = %*{
      "ipfsIp": "64.225.88.71",
      "fileSize": 238823,
      "ipfsEncrypt": 1,
      "ipfsEncryptNonceSize": 12,
      "ipfsEncryptKeyBytes": [40,189,223,22,241,112,253,244,144,149,238,96,177,122,165,140]
    }
    let c = NMobileChannel(decryptIpfsCache: true)
    let dl = waitFor tryDownloadIpfsToCache(c, src, cid, "test.jpg", opts)
    check dl[0] == true
    check dl[1].len > 0
    check fileExists(dl[1])
    check dl[2] > 0
    check getFileSize(dl[1]).int64 == dl[2]
    check dl[2] == 238823
    let head = readFile(dl[1])
    check head.len >= 3
    check ord(head[0]) == 0xFF and ord(head[1]) == 0xD8 and ord(head[2]) == 0xFF
