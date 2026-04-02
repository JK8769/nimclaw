const fs = require("fs");
const crypto = require("crypto");

function getArg(name, def = null) {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return def;
  if (idx + 1 >= process.argv.length) return def;
  return process.argv[idx + 1];
}

const inPath = getArg("--in");
const keyHex = getArg("--keyHex");
const outPath = getArg("--out", inPath ? `${inPath}.dec` : null);
const nonceSize = parseInt(getArg("--nonceSize", "12"), 10);

if (!inPath || !keyHex) {
  process.stderr.write("usage: node tools/ipfs_decrypt.js --in <file> --keyHex <hex> [--out <file>] [--nonceSize 12]\n");
  process.exit(2);
}

const buf = fs.readFileSync(inPath);
if (buf.length < nonceSize + 16) {
  throw new Error("ciphertext too short");
}

const nonce = buf.subarray(0, nonceSize);
const ctTag = buf.subarray(nonceSize);
const tag = ctTag.subarray(ctTag.length - 16);
const ct = ctTag.subarray(0, ctTag.length - 16);

const key = Buffer.from(keyHex, "hex");
if (key.length !== 16) {
  throw new Error("AES-128-GCM requires 16-byte key");
}

const decipher = crypto.createDecipheriv("aes-128-gcm", key, nonce);
decipher.setAuthTag(tag);
const plain = Buffer.concat([decipher.update(ct), decipher.final()]);
fs.writeFileSync(outPath, plain);
process.stdout.write(outPath + "\n");
