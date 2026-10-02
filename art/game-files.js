'use strict';
// Reads files straight from a World of Warcraft install (CASC storage), for
// art\worldmap.js. Node built-ins only. Follows how wow.export reads them
// (https://github.com/Kruithne/wow.export, MIT).
//
//   new GameFiles(install, product)  open an install (product as in .build.info)
//     .read(fileDataID)              a file's bytes
//     .idOf(name)                    a file's ID from its path, if the game keeps names
//   readTable(buffer, definition)    a database table (DB2, WDC5) as rows
//   decodeBLP(buffer)                a texture as { width, height, data: RGBA }
//   encodePNG(image)                 RGBA pixels as a PNG file
//
// How CASC finds a file: .build.info names the build; its build config names
// the encoding and root files; the root maps FileDataIDs (and name hashes) to
// content keys; the encoding maps content keys to encoded keys; the
// Data\data\*.idx indexes say where each encoded key sits in the data.###
// archives; and each file there is BLTE: chunks stored raw or zlib-packed.

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

function hex(buf, start, end) { return buf.toString('hex', start, end); }

function blte(buf) {
  if (buf.toString('latin1', 0, 4) !== 'BLTE') throw new Error('not BLTE data');
  const headerSize = buf.readUInt32BE(4), chunks = [];
  if (headerSize === 0) {
    chunks.push([8, buf.length - 8]);
  } else {
    let at = headerSize;
    for (let i = 0, n = buf.readUIntBE(9, 3); i < n; i++) {
      const size = buf.readUInt32BE(12 + i * 24);
      chunks.push([at, size]);
      at += size;
    }
  }
  return Buffer.concat(chunks.map(([start, size]) => {
    const mode = String.fromCharCode(buf[start]), body = buf.subarray(start + 1, start + size);
    if (mode === 'N') return body;
    if (mode === 'Z') return zlib.inflateSync(body);
    if (mode === 'F') return blte(body);
    throw new Error(`BLTE chunk "${mode}" isn't supported (an encrypted file?)`);
  }));
}

class GameFiles {
  constructor(install, product) {
    this.install = install;
    const info = fs.readFileSync(path.join(install, '.build.info'), 'utf8').trim().split(/\r?\n/);
    const head = info[0].split('|').map((h) => h.split('!')[0]);
    const builds = info.slice(1).map((line) => Object.fromEntries(line.split('|').map((v, i) => [head[i], v])));
    this.build = builds.find((b) => b.Product === product);
    if (!this.build) throw new Error(`No ${product} build in ${install} (it has ${builds.map((b) => b.Product).join(', ')}).`);
    const key = this.build['Build Key'];
    const config = fs.readFileSync(path.join(install, 'Data', 'config', key.slice(0, 2), key.slice(2, 4), key), 'utf8');
    this.config = {};
    for (const line of config.split(/\r?\n/)) {
      const m = line.match(/^([\w-]+)\s*=\s*(.*)$/);
      if (m) this.config[m[1]] = m[2];
    }
    this.loadIndexes();
    this.loadEncoding();
    this.loadRoot();
  }

  // The newest index file of each bucket: 9-byte encoded key -> archive, offset, size.
  loadIndexes() {
    const dir = path.join(this.install, 'Data', 'data'), newest = {};
    for (const name of fs.readdirSync(dir)) {
      const m = name.match(/^([0-9a-f]{2})([0-9a-f]{8})\.idx$/i);
      if (m && (!newest[m[1]] || newest[m[1]].version < parseInt(m[2], 16))) newest[m[1]] = { name, version: parseInt(m[2], 16) };
    }
    this.index = new Map();
    for (const { name } of Object.values(newest)) {
      const buf = fs.readFileSync(path.join(dir, name));
      const at = (8 + buf.readUInt32LE(0) + 0x0f) & ~0x0f, end = at + 8 + buf.readUInt32LE(at);
      for (let p = at + 8; p + 18 <= end; p += 18) {
        const ekey = hex(buf, p, p + 9);
        if (this.index.has(ekey)) continue;
        const high = buf[p + 9], low = buf.readUInt32BE(p + 10);
        this.index.set(ekey, { archive: (high << 2) | (low >>> 30), offset: low & 0x3fffffff, size: buf.readUInt32LE(p + 14) });
      }
    }
  }

  readEncoded(ekey) {
    const entry = this.index.get(ekey.slice(0, 18));
    if (!entry) throw new Error(`Not in the local game files: ${ekey}`);
    const fd = fs.openSync(path.join(this.install, 'Data', 'data', 'data.' + String(entry.archive).padStart(3, '0')), 'r');
    try {
      const buf = Buffer.alloc(entry.size - 30);   // after the 30-byte entry header
      fs.readSync(fd, buf, 0, buf.length, entry.offset + 30);
      return blte(buf);
    } finally {
      fs.closeSync(fd);
    }
  }

  loadEncoding() {
    const enc = this.readEncoded(this.config.encoding.split(' ')[1]);
    if (enc.toString('latin1', 0, 2) !== 'EN') throw new Error('Unexpected encoding file.');
    const ckeySize = enc[3], ekeySize = enc[4], pageSize = enc.readUInt16BE(5) * 1024, pageCount = enc.readUInt32BE(9);
    const pages = 22 + enc.readUInt32BE(18) + pageCount * (ckeySize + 16);
    this.encoding = new Map();
    for (let i = 0; i < pageCount; i++) {
      for (let p = pages + i * pageSize, end = p + pageSize; p < end && enc[p];) {
        const ckey = hex(enc, p + 6, p + 6 + ckeySize);
        this.encoding.set(ckey, hex(enc, p + 6 + ckeySize, p + 6 + ckeySize + ekeySize));
        p += 6 + ckeySize + enc[p] * ekeySize;
      }
    }
  }

  // FileDataID -> content key, and name hash -> FileDataID, for files in
  // English or every language (not the low-violence versions).
  loadRoot() {
    const root = this.readEncoded(this.encoding.get(this.config.root.split(' ')[0]));
    if (root.toString('latin1', 0, 4) !== 'TSFM') throw new Error('Unexpected root file (an old client?).');
    let headerSize = root.readUInt32LE(4), version = root.readUInt32LE(8), total, named;
    if (headerSize !== 0x18) { total = headerSize; named = version; version = 0; headerSize = 12; }
    else { total = root.readUInt32LE(12); named = root.readUInt32LE(16); }
    const allowNameless = total !== named;
    this.files = new Map();
    this.names = new Map();
    for (let p = headerSize; p < root.length;) {
      const count = root.readUInt32LE(p);
      let content, locale;
      if (version < 2) { content = root.readUInt32LE(p + 4); locale = root.readUInt32LE(p + 8); p += 12; }
      else { locale = root.readUInt32LE(p + 4); content = root.readUInt32LE(p + 8) | root.readUInt32LE(p + 12) | (root[p + 16] << 17); p += 17; }
      const ids = new Array(count);
      for (let i = 0, id = 0; i < count; i++, p += 4) { id += root.readInt32LE(p); ids[i] = id++; }
      const keysAt = p;
      p += 16 * count;
      const hasNames = !(allowNameless && (content & 0x10000000));
      const namesAt = p;
      if (hasNames) p += 8 * count;
      if (!(locale & 0x2) || (content & 0x80)) continue;   // enUS (or every locale), not low violence
      for (let i = 0; i < count; i++) {
        if (!this.files.has(ids[i])) this.files.set(ids[i], hex(root, keysAt + 16 * i, keysAt + 16 * (i + 1)));
        if (hasNames) this.names.set(root.readBigUInt64LE(namesAt + 8 * i), ids[i]);
      }
    }
  }

  read(fileDataID) {
    const ckey = this.files.get(fileDataID);
    if (!ckey) throw new Error(`No file ${fileDataID} in this build.`);
    const ekey = this.encoding.get(ckey);
    if (!ekey) throw new Error(`File ${fileDataID} isn't in the encoding table.`);
    return this.readEncoded(ekey);
  }

  idOf(name) { return this.names.get(jenkins96(name)); }
}

// The root's name hash: Bob Jenkins' hashlittle2 of the upper-cased path
// with backslashes, as (c << 32) | b.
function jenkins96(name) {
  const k = Buffer.from(name.toUpperCase().replace(/\//g, '\\'), 'latin1');
  const rot = (x, n) => ((x << n) | (x >>> (32 - n))) >>> 0;
  const word = (b, o) => (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
  let a, b, c, i = 0, len = k.length;
  a = b = c = (0xdeadbeef + len) >>> 0;
  if (!len) return (BigInt(c) << 32n) | BigInt(b);
  while (len > 12) {
    a = (a + word(k, i)) >>> 0; b = (b + word(k, i + 4)) >>> 0; c = (c + word(k, i + 8)) >>> 0;
    a = (a - c) >>> 0; a ^= rot(c, 4); c = (c + b) >>> 0;
    b = (b - a) >>> 0; b ^= rot(a, 6); a = (a + c) >>> 0;
    c = (c - b) >>> 0; c ^= rot(b, 8); b = (b + a) >>> 0;
    a = (a - c) >>> 0; a ^= rot(c, 16); c = (c + b) >>> 0;
    b = (b - a) >>> 0; b ^= rot(a, 19); a = (a + c) >>> 0;
    c = (c - b) >>> 0; c ^= rot(b, 4); b = (b + a) >>> 0;
    len -= 12; i += 12;
  }
  const tail = Buffer.alloc(12);
  k.copy(tail, 0, i, i + len);
  a = (a + word(tail, 0)) >>> 0; b = (b + word(tail, 4)) >>> 0; c = (c + word(tail, 8)) >>> 0;
  c ^= b; c = (c - rot(b, 14)) >>> 0;
  a ^= c; a = (a - rot(c, 11)) >>> 0;
  b ^= a; b = (b - rot(a, 25)) >>> 0;
  c ^= b; c = (c - rot(b, 16)) >>> 0;
  a ^= c; a = (a - rot(c, 4)) >>> 0;
  b ^= a; b = (b - rot(a, 14)) >>> 0;
  c ^= b; c = (c - rot(b, 24)) >>> 0;
  return (BigInt(c >>> 0) << 32n) | BigInt(b >>> 0);
}

// ---- Database tables (DB2, WDC5) ----
// `definition` is the table's layout in WoWDBDefs' notation, one field per
// line in file order, with $id$, $relation$ and $noninline$ tags, like
//   $noninline,id$ID<32>
//   RowIndex<u8>
//   $noninline,relation$UiMapArtID<32>
// plus its LAYOUT hash, checked against the file so a changed table fails
// loudly instead of reading garbage.
function readTable(buf, layout, definition) {
  if (buf.toString('latin1', 0, 4) !== 'WDC5') throw new Error('Not a WDC5 table.');
  const fields = definition.trim().split(/\s*\n\s*/).map((line) => {
    const m = line.match(/^(?:\$([\w,]+)\$)?(\w+)(?:<(u?)(\d+)>)?(?:\[(\d+)\])?(\s+float)?$/);
    if (!m) throw new Error('Bad field: ' + line);
    const tags = (m[1] || '').split(',');
    return { name: m[2], noninline: tags.includes('noninline'), id: tags.includes('id'), relation: tags.includes('relation'),
             signed: m[3] !== 'u', bits: m[4] ? Number(m[4]) : 32, count: m[5] ? Number(m[5]) : 1, float: !!m[6] };
  });
  let p = 4 + 4 + 128;
  const u32 = () => { p += 4; return buf.readUInt32LE(p - 4); };
  const recordCount = u32(), fieldCount = u32(), recordSize = u32();
  u32(); u32();
  const fileLayout = u32();
  if (fileLayout !== layout) throw new Error(`Table layout ${fileLayout.toString(16)} isn't the expected ${layout.toString(16)}; update its definition.`);
  u32(); u32(); u32();
  const flags = buf.readUInt16LE(p); p += 4;
  const totalFieldCount = u32(); u32(); u32();
  const storageSize = u32(), commonSize = u32(), palletSize = u32(), sectionCount = u32();
  if (flags & 1) throw new Error('Tables with an offset map are not handled.');
  const sections = [];
  for (let i = 0; i < sectionCount; i++) {
    p += 8;
    sections.push({ offset: u32(), records: u32(), strings: u32(), end: u32(), idList: u32(), relations: u32(), offsetIds: u32(), copies: u32() });
  }
  p += totalFieldCount * 4;
  const storage = [];
  for (let i = 0; i < storageSize / 24; i++, p += 24) {
    storage.push({ offsetBits: buf.readUInt16LE(p), sizeBits: buf.readUInt16LE(p + 2), extra: buf.readUInt32LE(p + 4),
                   type: buf.readUInt32LE(p + 8), v1: buf.readUInt32LE(p + 12), v3: buf.readUInt32LE(p + 20) });
  }
  let pallet = p, common = p + palletSize;
  for (const s of storage) {
    if (s.type === 3 || s.type === 4) { s.pallet = pallet; pallet += s.extra; }
    if (s.type === 2) {
      s.common = new Map();
      for (let q = common; q < common + s.extra; q += 8) s.common.set(buf.readUInt32LE(q), buf.readUInt32LE(q + 4));
      common += s.extra;
    }
  }
  const inline = fields.filter((f) => !f.noninline);
  if (inline.length !== fieldCount) throw new Error(`The definition has ${inline.length} stored fields; the table has ${fieldCount}.`);
  const bits = (rec, offset, size) => {
    let v = 0n;
    for (let i = ((offset + size + 7) >> 3) - 1; i >= offset >> 3; i--) v = (v << 8n) | BigInt(buf[rec + i]);
    return (v >> BigInt(offset & 7)) & ((1n << BigInt(size)) - 1n);
  };
  const asFloat = (v) => { const b = Buffer.alloc(4); b.writeUInt32LE(v >>> 0); return b.readFloatLE(0); };
  const idField = fields.find((f) => f.id), relationField = fields.find((f) => f.relation && f.noninline);
  const rows = [];
  for (const sec of sections) {
    let q = sec.offset + sec.records * recordSize + sec.strings;
    const ids = [];
    for (let i = 0; i < sec.idList / 4; i++, q += 4) ids.push(buf.readUInt32LE(q));
    const copies = [];
    for (let i = 0; i < sec.copies; i++, q += 8) copies.push([buf.readUInt32LE(q), buf.readUInt32LE(q + 4)]);
    const relation = new Map();
    if (sec.relations) {
      const n = buf.readUInt32LE(q);
      q += 12;
      for (let i = 0; i < n; i++, q += 8) relation.set(buf.readUInt32LE(q + 4), buf.readUInt32LE(q));
    }
    const sectionRows = [];
    for (let r = 0; r < sec.records; r++) {
      const rec = sec.offset + r * recordSize, row = {};
      inline.forEach((f, i) => {
        const s = storage[i];
        if (s.type === 0) {
          const at = rec + (s.offsetBits >> 3), n = f.bits >> 3;
          const one = (o) => f.float ? buf.readFloatLE(o) : n === 1 ? (f.signed ? buf.readInt8(o) : buf.readUInt8(o)) :
            n === 2 ? (f.signed ? buf.readInt16LE(o) : buf.readUInt16LE(o)) : (f.signed ? buf.readInt32LE(o) : buf.readUInt32LE(o));
          row[f.name] = f.count > 1 ? Array.from({ length: f.count }, (_, k) => one(at + k * n)) : one(at);
        } else if (s.type === 1 || s.type === 5) {
          const v = bits(rec, s.offsetBits, s.sizeBits);
          row[f.name] = Number(s.type === 5 ? BigInt.asIntN(s.sizeBits, v) : v);
          if (f.float) row[f.name] = asFloat(row[f.name]);
        } else if (s.type === 3) {
          row[f.name] = buf.readUInt32LE(s.pallet + Number(bits(rec, s.offsetBits, s.sizeBits)) * 4);
          if (f.float) row[f.name] = asFloat(row[f.name]);
        } else if (s.type === 4) {
          const index = Number(bits(rec, s.offsetBits, s.sizeBits));
          row[f.name] = Array.from({ length: s.v3 }, (_, k) => buf.readUInt32LE(s.pallet + (index * s.v3 + k) * 4));
        }
      });
      row.ID = idField && !idField.noninline ? row[idField.name] : ids[r];
      inline.forEach((f, i) => {
        const s = storage[i];
        if (s.type === 2) row[f.name] = f.float ? asFloat(s.common.has(row.ID) ? s.common.get(row.ID) : s.v1) :
          (s.common.has(row.ID) ? s.common.get(row.ID) : s.v1);
      });
      if (relationField) row[relationField.name] = relation.get(r);
      sectionRows.push(row);
    }
    for (const row of sectionRows) rows.push(row);
    for (const [newId, oldId] of copies) {
      const from = sectionRows.find((x) => x.ID === oldId);
      if (from) rows.push(Object.assign({}, from, { ID: newId }));
    }
  }
  return rows;
}

// ---- Textures (BLP2) ----
// DXT1, DXT3 and DXT5, palettized and plain BGRA, as RGBA pixels.
function decodeBLP(buf) {
  if (buf.toString('latin1', 0, 4) !== 'BLP2') throw new Error('Not a BLP2 texture.');
  const encoding = buf[8], alphaDepth = buf[9], alphaEncoding = buf[10];
  const width = buf.readUInt32LE(12), height = buf.readUInt32LE(16);
  const raw = buf.subarray(buf.readUInt32LE(20), buf.readUInt32LE(20) + buf.readUInt32LE(84));
  const out = Buffer.alloc(width * height * 4), n = width * height;
  if (encoding === 1) {
    const palette = buf.subarray(148, 148 + 1024);
    for (let i = 0; i < n; i++) {
      const c = raw[i] * 4;
      out[i * 4] = palette[c + 2]; out[i * 4 + 1] = palette[c + 1]; out[i * 4 + 2] = palette[c];
      out[i * 4 + 3] = alphaDepth === 1 ? ((raw[n + (i >> 3)] >> (i & 7)) & 1) * 255 :
        alphaDepth === 4 ? ((raw[n + (i >> 1)] >> ((i & 1) * 4)) & 0x0f) * 17 : alphaDepth === 8 ? raw[n + i] : 255;
    }
  } else if (encoding === 2) {
    const kind = alphaDepth > 1 ? (alphaEncoding === 7 ? 5 : 3) : 1, blockBytes = kind === 1 ? 8 : 16;
    const rgb = (c) => [((c >> 11) & 31) * 255 / 31, ((c >> 5) & 63) * 255 / 63, (c & 31) * 255 / 31];
    for (let by = 0, p = 0; by < height; by += 4) {
      for (let bx = 0; bx < width; bx += 4, p += blockBytes) {
        const at = kind === 1 ? p : p + 8, c0 = raw.readUInt16LE(at), c1 = raw.readUInt16LE(at + 2);
        const a = rgb(c0), b = rgb(c1), colors = [a.concat(255), b.concat(255)];
        if (kind !== 1 || c0 > c1) {
          colors.push([0, 1, 2].map((k) => (2 * a[k] + b[k]) / 3).concat(255), [0, 1, 2].map((k) => (a[k] + 2 * b[k]) / 3).concat(255));
        } else {
          colors.push([0, 1, 2].map((k) => (a[k] + b[k]) / 2).concat(255), [0, 0, 0, 0]);
        }
        let alphas = null;
        if (kind === 3) {
          alphas = [];
          for (let i = 0; i < 8; i++) alphas.push((raw[p + i] & 15) * 17, (raw[p + i] >> 4) * 17);
        } else if (kind === 5) {
          const a0 = raw[p], a1 = raw[p + 1], table = [a0, a1];
          if (a0 > a1) for (let i = 1; i < 7; i++) table.push(((7 - i) * a0 + i * a1) / 7);
          else { for (let i = 1; i < 5; i++) table.push(((5 - i) * a0 + i * a1) / 5); table.push(0, 255); }
          let packed = 0n;
          for (let i = 0; i < 6; i++) packed |= BigInt(raw[p + 2 + i]) << BigInt(8 * i);
          alphas = Array.from({ length: 16 }, (_, i) => table[Number((packed >> BigInt(3 * i)) & 7n)]);
        }
        const indexes = raw.readUInt32LE(at + 4);
        for (let i = 0; i < 16; i++) {
          const x = bx + (i & 3), y = by + (i >> 2);
          if (x >= width || y >= height) continue;
          const c = colors[(indexes >>> (2 * i)) & 3], o = (y * width + x) * 4;
          out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2]; out[o + 3] = alphas ? alphas[i] : c[3];
        }
      }
    }
  } else if (encoding === 3) {
    for (let i = 0; i < n; i++) {
      out[i * 4] = raw[i * 4 + 2]; out[i * 4 + 1] = raw[i * 4 + 1]; out[i * 4 + 2] = raw[i * 4]; out[i * 4 + 3] = raw[i * 4 + 3];
    }
  } else {
    throw new Error('Unknown BLP encoding ' + encoding);
  }
  return { width, height, data: out };
}

// ---- PNG ----
const CRC = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
function crc32(buf) { let c = -1; for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; }
function chunk(type, data) {
  const head = Buffer.alloc(4), body = Buffer.concat([Buffer.from(type, 'latin1'), data]), crc = Buffer.alloc(4);
  head.writeUInt32BE(data.length);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([head, body, crc]);
}
function encodePNG({ width, height, data }) {
  const rows = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) data.copy(rows, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;   // bits per channel
  ihdr[9] = 6;   // RGBA
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(rows, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

module.exports = { GameFiles, readTable, decodeBLP, encodePNG, jenkins96 };
