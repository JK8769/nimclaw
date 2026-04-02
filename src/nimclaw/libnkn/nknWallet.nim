################################
# Libs
################################

# Import C standard library
proc c_free(p: pointer) {.importc: "free", header: "<stdlib.h>".}

import std/os
const nknLibDir = currentSourcePath().splitPath().head

when defined(macosx):
  {.passL: "-L" & nknLibDir & " -lnkn -Wl,-rpath," & nknLibDir & " -Wl,-rpath,@executable_path".}
elif defined(linux):
  {.passL: "-L" & nknLibDir & " -lnkn -Wl,-rpath," & nknLibDir & " -Wl,-rpath,$ORIGIN".}
else:
  {.passL: "-L" & nknLibDir & " -lnkn".}
proc GenerateWalletJSON(password: cstring): cstring {.importc.}
proc GenerateWalletWithSeedJSON(seed_hex, password: cstring): cstring {.importc.}
proc VerifyWalletFromJSON(walletJSON, password: cstring): cstring {.importc.}
proc GetWalletBalance(walletJSON, password: cstring): cstring {.importc.}
proc GetWalletSeed(walletJSON, password: cstring): cstring {.importc.}
proc CreateNKNClient(walletJSON, password, identifier: cstring, numSubClients, originalClient: cint): cstring {.importc.}
proc GetNKNAddress(walletJSON, password, identifier: cstring): cstring {.importc.}
proc PopNKNMessage(clientAddr: cstring): cstring {.importc.}
proc SendNKNMessage(clientAddr, destAddr, message: cstring, maxHoldingSeconds, noReply: cint): cstring {.importc.}
proc CloseNKNClient(clientAddr: cstring): cstring {.importc.}
proc FreeNKNString(p: cstring) {.importc.}

################################
# Imports
################################



################################
# Types and Defines
################################



import std/json

type
  FFIResultObj = object
    result: string
    data: string
    error: string
    src: string

proc safeGetStr(j: JsonNode, key: string): string =
  if j.isNil or not j.hasKey(key): return ""
  let node = j[key]
  if node.isNil: return ""
  return node.getStr()

proc handleFFI(cs: cstring): FFIResultObj =
  if cs.isNil: return FFIResultObj()
  let s = $cs # This is safe because of isNil check
  try:
    let js = parseJson(s)
    result.result = js.safeGetStr("result")
    result.data = js.safeGetStr("data")
    result.error = js.safeGetStr("error")
    result.src = js.safeGetStr("src")
  except Exception as e:
    result.error = "FFI Error: " & e.msg & " JSON: " & s
  finally:
    if not cs.isNil:
      FreeNKNString(cs)

proc getWallet*(password: string): (string, string) =
  let res = handleFFI(GenerateWalletJSON(password.cstring))
  (res.result, res.error)

proc generateWalletWithSeed*(seed_hex, password: string): (string, string) =
  let res = handleFFI(GenerateWalletWithSeedJSON(seed_hex.cstring, password.cstring))
  (res.result, res.error)

proc createNKNClient*(walletJson, password, identifier: string, numSubClients: int = 4, originalClient: bool = false): (string, string) =
  let res = handleFFI(CreateNKNClient(walletJson.cstring, password.cstring, identifier.cstring, numSubClients.cint, originalClient.cint))
  (res.result, res.error)

proc getNKNAddress*(walletJson, password, identifier: string): (string, string) =
  let res = handleFFI(GetNKNAddress(walletJson.cstring, password.cstring, identifier.cstring))
  (res.result, res.error)

proc popNKNMessage*(clientAddr: string): (string, string, string) =
  let res = handleFFI(PopNKNMessage(clientAddr.cstring))
  (res.src, res.data, res.error)

proc sendNKNMessage*(clientAddr, destAddr, message: string, maxHoldingSeconds: int = 0, noReply: bool = false): (string, string) =
  let res = handleFFI(SendNKNMessage(clientAddr.cstring, destAddr.cstring, message.cstring, maxHoldingSeconds.cint, noReply.cint))
  (res.result, res.error)

proc closeNKNClient*(clientAddr: string): (string, string) =
  let res = handleFFI(CloseNKNClient(clientAddr.cstring))
  (res.result, res.error)

################################
# Objects and Procedures
################################




################################
# Tests
################################

# export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/gao/nkn-sdk-go/examples/wallet
# nim c -r nknWallet.nim

when isMainModule:
  import json
  # import print


  # new wallet
  block:
    let (walletJson, errorMsg) = getWallet("QWEZXC")
    
    if errorMsg.len > 0:
        echo "错误: ", errorMsg
    else:
        echo parseJson(walletJson).pretty()

  block:
    let (walletJson, errorMsg) = getWallet("QWEZXCagi")
    
    if errorMsg.len > 0:
        echo "错误: ", errorMsg
    else:
        echo parseJson(walletJson).pretty()

    # # new wallet
    # var p: cstring = "QWEZXC"
    # var w: cstring
    # var rst, err: cstring
    #
    # (w, err) = GenerateWalletJSON(p)
    # if err.len == 0:
    #     # let wallet = parseJson($rst).pretty()
    #     # print parseJson($rst)
    #     echo parseJson($w).pretty()
    # else:
    #     print $err

    # # get seed
    # (rst, err) = GetWalletSeed(w, p)
    # if err.len == 0:
    #     print $rst
    # else:
    #     print $err

    # # new wallet with seed
    # (w, err) = GenerateWalletWithSeedJSON(rst, p)
    # if err.len == 0:
    #     echo parseJson($w).pretty()
    # else:
    #     print $err

    # # verify wallet
    # (rst, err) = VerifyWalletFromJSON(w, p)
    # if err.len == 0:
    #     print $rst
    # else:
    #     print $err

    # echo "-----------------------"
    # echo "wallet with balance"
    # echo "-----------------------"
    #
    # # wallet with balance
    # w = """{"Version":2,"IV":"ef3214f5a2de5d3e0410519142e3efc4","MasterKey":"e4e81f36cec69e6d7a44a1e6f30492e2da7042f2d4167159f62fdf57e0655bc3","SeedEncrypted":"8eba7ad9ace2960e84ed68fc4aa62748a7881f127ed0862ce749d59715cda4bf","Address":"NKNN93QcWr9f91yKWhnBuWQiH5YWYh7uW4JJ","Scrypt":{"Salt":"51a3b114ac897b0a","N":32768,"R":8,"P":1}}""" 
    # echo "wallet password:"
    # p = stdin.readLine().cstring 
    #
    # # get balance
    # (rst, err) = GetWalletBalance(w, p)
    # if err.len == 0:
    #     print $rst
    # else:
    #     print $err
    #
    # # get seed
    # (rst, err) = GetWalletSeed(w, p)
    # if err.len == 0:
    #     print $rst
    # else:
    #     print $err
