import std/unittest
import std/[sequtils]
import nimcrypto/rijndael
import nimcrypto/bcmode

import ../src/nimclaw/crypto_gcm

suite "nMobile AES-GCM":
  test "decrypts nonce+ciphertext+tag blob":
    let key = @[byte 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F]
    let nonce = @[byte 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B]
    let plain = "hello nimclaw gcm"

    var ctx: GCM[aes128]
    ctx.init(key, nonce, @[])
    var ct = newSeq[byte](plain.len)
    ctx.encrypt(toBytes(plain), ct)
    let tag = ctx.getTag().toSeq
    ctx.clear()

    var blob = newSeq[byte](0)
    blob.add nonce
    blob.add ct
    blob.add tag

    let dec = aes128GcmDecryptNmobile(blob, key, 12)
    check toString(dec) == plain
