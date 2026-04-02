import std/[strutils]
import cligen

when defined(macosx):
  {.passL: "-lcrypto".}
elif defined(windows):
  {.passL: "libcrypto".}
else:
  {.passL: "-lcrypto".}

type CInt = cint

proc EVP_CIPHER_CTX_new(): pointer {.cdecl, importc.}
proc EVP_CIPHER_CTX_free(ctx: pointer) {.cdecl, importc.}
proc EVP_aes_128_gcm(): pointer {.cdecl, importc.}
proc EVP_DecryptInit_ex(ctx: pointer, cipher: pointer, impl: pointer, key: ptr uint8, iv: ptr uint8): CInt {.cdecl, importc.}
proc EVP_DecryptUpdate(ctx: pointer, outp: ptr uint8, outl: ptr CInt, inp: ptr uint8, inl: CInt): CInt {.cdecl, importc.}
proc EVP_DecryptFinal_ex(ctx: pointer, outp: ptr uint8, outl: ptr CInt): CInt {.cdecl, importc.}
proc EVP_CIPHER_CTX_ctrl(ctx: pointer, typ: CInt, arg: CInt, p: pointer): CInt {.cdecl, importc.}

const
  EVP_CTRL_GCM_SET_IVLEN = 0x9
  EVP_CTRL_GCM_SET_TAG = 0x11

proc fromHexByte(a, b: char): uint8 =
  proc nib(ch: char): int =
    if ch in {'0'..'9'}: return ord(ch) - ord('0')
    let c = ch.toLowerAscii()
    if c in {'a'..'f'}: return 10 + ord(c) - ord('a')
    raise newException(ValueError, "invalid hex")
  uint8((nib(a) shl 4) or nib(b))

proc decodeHex(s: string): seq[uint8] =
  let t = s.strip()
  if t.len == 0: return @[]
  if (t.len mod 2) != 0:
    raise newException(ValueError, "hex length must be even")
  result = newSeq[uint8](t.len div 2)
  var j = 0
  var i = 0
  while i < t.len:
    result[j] = fromHexByte(t[i], t[i + 1])
    inc j
    inc i, 2

proc decryptAes128Gcm(ciphertextWithNonce: string, key: seq[uint8], nonceSize: int): string =
  if nonceSize <= 0:
    raise newException(ValueError, "nonceSize must be > 0")
  if ciphertextWithNonce.len < nonceSize + 16:
    raise newException(ValueError, "ciphertext too short")
  if key.len != 16:
    raise newException(ValueError, "AES-128-GCM requires 16-byte key")

  let nonce = ciphertextWithNonce[0..<nonceSize]
  let ctTag = ciphertextWithNonce[nonceSize..^1]
  let tag = ctTag[(ctTag.len - 16)..^1]
  let ct = ctTag[0..<(ctTag.len - 16)]

  let ctx = EVP_CIPHER_CTX_new()
  if ctx.isNil:
    raise newException(OSError, "EVP_CIPHER_CTX_new failed")
  defer: EVP_CIPHER_CTX_free(ctx)

  if EVP_DecryptInit_ex(ctx, EVP_aes_128_gcm(), nil, nil, nil) != 1:
    raise newException(OSError, "EVP_DecryptInit_ex(cipher) failed")
  if EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, CInt(nonceSize), nil) != 1:
    raise newException(OSError, "EVP_CIPHER_CTX_ctrl(IVLEN) failed")

  var keyBuf = key
  if EVP_DecryptInit_ex(ctx, nil, nil, cast[ptr uint8](addr keyBuf[0]), cast[ptr uint8](unsafeAddr nonce[0])) != 1:
    raise newException(OSError, "EVP_DecryptInit_ex(key/iv) failed")

  result = newString(ct.len)
  var outl: CInt = 0
  if ct.len > 0:
    if EVP_DecryptUpdate(ctx, cast[ptr uint8](addr result[0]), addr outl, cast[ptr uint8](unsafeAddr ct[0]), CInt(ct.len)) != 1:
      raise newException(OSError, "EVP_DecryptUpdate failed")
  var total = int(outl)

  if EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, cast[pointer](unsafeAddr tag[0])) != 1:
    raise newException(OSError, "EVP_CIPHER_CTX_ctrl(SET_TAG) failed")

  var outl2: CInt = 0
  let fin = if total < result.len: cast[ptr uint8](addr result[total]) else: nil
  let ok = EVP_DecryptFinal_ex(ctx, fin, addr outl2)
  if ok != 1:
    raise newException(OSError, "GCM auth failed")
  total += int(outl2)
  if total != result.len:
    result.setLen(total)

proc ipfsDecrypt(inPath: string, keyHex: string, outPath = "", nonceSize = 12) =
  let key = decodeHex(keyHex)
  let data = readFile(inPath)
  let plain = decryptAes128Gcm(data, key, nonceSize)
  let outFile = if outPath.len > 0: outPath else: inPath & ".dec"
  writeFile(outFile, plain)
  echo outFile

dispatch(ipfsDecrypt)
