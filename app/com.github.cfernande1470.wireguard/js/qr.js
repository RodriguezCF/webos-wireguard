/*
 * Minimal QR code encoder for the upload URL (ES5, no dependencies).
 *
 * Byte mode, error correction level M, versions 1 to 6 (up to 106 bytes),
 * all eight masks scored with the standard penalty rules. Written for this
 * project from ISO/IEC 18004 and released under the repository MIT licence.
 *
 * QR.encode(text) returns { size: n, modules: [[true|false, ...], ...] }
 * QR.draw(canvas, text, pixelSize) renders it with a 4 module quiet zone.
 */
var QR = (function() {
  // Level M: error correction codewords per block and number of blocks.
  var ECC_PER_BLOCK = [0, 10, 16, 26, 18, 24, 16];
  var NUM_BLOCKS = [0, 1, 1, 1, 2, 2, 4];
  var MAX_VERSION = 6;
  var FORMAT_BITS_M = 0;

  function gfMul(x, y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >>> 7) * 0x11d);
      z ^= ((y >>> i) & 1) * x;
    }
    return z & 0xff;
  }

  function rsDivisor(degree) {
    var result = [];
    for (var i = 0; i < degree - 1; i++) result.push(0);
    result.push(1);
    var root = 1;
    for (i = 0; i < degree; i++) {
      for (var j = 0; j < result.length; j++) {
        result[j] = gfMul(result[j], root);
        if (j + 1 < result.length) result[j] ^= result[j + 1];
      }
      root = gfMul(root, 0x02);
    }
    return result;
  }

  function rsRemainder(data, divisor) {
    var result = [];
    for (var i = 0; i < divisor.length; i++) result.push(0);
    for (i = 0; i < data.length; i++) {
      var factor = data[i] ^ result.shift();
      result.push(0);
      for (var j = 0; j < divisor.length; j++) {
        result[j] ^= gfMul(divisor[j], factor);
      }
    }
    return result;
  }

  function rawDataModules(ver) {
    var result = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
      var numAlign = Math.floor(ver / 7) + 2;
      result -= (25 * numAlign - 10) * numAlign - 55;
    }
    return result;
  }

  function dataCodewords(ver) {
    return Math.floor(rawDataModules(ver) / 8) - ECC_PER_BLOCK[ver] * NUM_BLOCKS[ver];
  }

  function utf8Bytes(text) {
    var bytes = [];
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i);
      if (c < 0x80) {
        bytes.push(c);
      } else if (c < 0x800) {
        bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
      } else {
        bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      }
    }
    return bytes;
  }

  function encode(text) {
    var bytes = utf8Bytes(text);
    var ver = 1;
    while (ver <= MAX_VERSION && 4 + 8 + bytes.length * 8 > dataCodewords(ver) * 8) ver++;
    if (ver > MAX_VERSION) return null;

    // Bit stream: byte mode, 8 bit length, data, terminator, padding.
    var bits = [];
    function put(value, len) {
      for (var i = len - 1; i >= 0; i--) bits.push((value >>> i) & 1);
    }
    put(4, 4);
    put(bytes.length, 8);
    for (var i = 0; i < bytes.length; i++) put(bytes[i], 8);
    var capacity = dataCodewords(ver) * 8;
    put(0, Math.min(4, capacity - bits.length));
    put(0, (8 - (bits.length % 8)) % 8);
    for (var pad = 0xec; bits.length < capacity; pad ^= 0xec ^ 0x11) put(pad, 8);

    var data = [];
    for (i = 0; i < bits.length; i += 8) {
      var b = 0;
      for (var k = 0; k < 8; k++) b = (b << 1) | bits[i + k];
      data.push(b);
    }

    // Error correction and interleaving.
    var numBlocks = NUM_BLOCKS[ver];
    var eccLen = ECC_PER_BLOCK[ver];
    var rawCodewords = Math.floor(rawDataModules(ver) / 8);
    var numShort = numBlocks - (rawCodewords % numBlocks);
    var shortLen = Math.floor(rawCodewords / numBlocks);
    var divisor = rsDivisor(eccLen);
    var blocks = [];
    var pos = 0;
    for (i = 0; i < numBlocks; i++) {
      var datLen = shortLen - eccLen + (i < numShort ? 0 : 1);
      var dat = data.slice(pos, pos + datLen);
      pos += datLen;
      var ecc = rsRemainder(dat, divisor);
      if (i < numShort) dat.push(0);
      blocks.push(dat.concat(ecc));
    }
    var codewords = [];
    for (i = 0; i < blocks[0].length; i++) {
      for (var j = 0; j < blocks.length; j++) {
        if (i !== shortLen - eccLen || j >= numShort) codewords.push(blocks[j][i]);
      }
    }

    // Matrix with function patterns.
    var size = ver * 4 + 17;
    var modules = [];
    var isFunction = [];
    for (i = 0; i < size; i++) {
      modules.push([]);
      isFunction.push([]);
      for (j = 0; j < size; j++) {
        modules[i].push(false);
        isFunction[i].push(false);
      }
    }
    function setFn(x, y, dark) {
      modules[y][x] = dark;
      isFunction[y][x] = true;
    }
    for (i = 0; i < size; i++) {
      setFn(6, i, i % 2 === 0);
      setFn(i, 6, i % 2 === 0);
    }
    function finder(cx, cy) {
      for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
          var dist = Math.max(Math.abs(dx), Math.abs(dy));
          var x = cx + dx;
          var y = cy + dy;
          if (x >= 0 && x < size && y >= 0 && y < size) setFn(x, y, dist !== 2 && dist !== 4);
        }
      }
    }
    finder(3, 3);
    finder(size - 4, 3);
    finder(3, size - 4);
    if (ver >= 2) {
      var c = size - 7;
      for (var ay = -2; ay <= 2; ay++) {
        for (var ax = -2; ax <= 2; ax++) {
          setFn(c + ax, c + ay, Math.max(Math.abs(ax), Math.abs(ay)) !== 1);
        }
      }
    }

    function drawFormat(mask) {
      var d = (FORMAT_BITS_M << 3) | mask;
      var rem = d;
      for (var n = 0; n < 10; n++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
      var f = ((d << 10) | rem) ^ 0x5412;
      function bit(n) {
        return ((f >>> n) & 1) !== 0;
      }
      for (n = 0; n <= 5; n++) setFn(8, n, bit(n));
      setFn(8, 7, bit(6));
      setFn(8, 8, bit(7));
      setFn(7, 8, bit(8));
      for (n = 9; n < 15; n++) setFn(14 - n, 8, bit(n));
      for (n = 0; n < 8; n++) setFn(size - 1 - n, 8, bit(n));
      for (n = 8; n < 15; n++) setFn(8, size - 15 + n, bit(n));
      setFn(8, size - 8, true);
    }
    drawFormat(0);

    // Codewords in the zigzag order.
    var bitIndex = 0;
    var total = codewords.length * 8;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        for (k = 0; k < 2; k++) {
          var x = right - k;
          var upward = ((right + 1) & 2) === 0;
          var y = upward ? size - 1 - vert : vert;
          if (!isFunction[y][x] && bitIndex < total) {
            modules[y][x] = ((codewords[bitIndex >>> 3] >>> (7 - (bitIndex & 7))) & 1) !== 0;
            bitIndex++;
          }
        }
      }
    }

    function maskBit(mask, x, y) {
      switch (mask) {
        case 0: return (x + y) % 2 === 0;
        case 1: return y % 2 === 0;
        case 2: return x % 3 === 0;
        case 3: return (x + y) % 3 === 0;
        case 4: return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
        case 5: return (x * y) % 2 + (x * y) % 3 === 0;
        case 6: return ((x * y) % 2 + (x * y) % 3) % 2 === 0;
        default: return ((x + y) % 2 + (x * y) % 3) % 2 === 0;
      }
    }
    function applyMask(mask) {
      for (var yy = 0; yy < size; yy++) {
        for (var xx = 0; xx < size; xx++) {
          if (!isFunction[yy][xx] && maskBit(mask, xx, yy)) modules[yy][xx] = !modules[yy][xx];
        }
      }
    }

    var best = 0;
    var bestPenalty = Infinity;
    for (var m = 0; m < 8; m++) {
      applyMask(m);
      drawFormat(m);
      var p = penalty(modules, size);
      if (p < bestPenalty) {
        bestPenalty = p;
        best = m;
      }
      applyMask(m);
    }
    applyMask(best);
    drawFormat(best);

    return { size: size, modules: modules };
  }

  // Standard penalty: runs, 2x2 blocks, finder-like patterns, dark balance.
  function penalty(modules, size) {
    var result = 0;
    var x;
    var y;
    var run;
    var dark = 0;
    for (y = 0; y < size; y++) {
      run = 1;
      for (x = 1; x <= size; x++) {
        if (x < size && modules[y][x] === modules[y][x - 1]) {
          run++;
        } else {
          if (run >= 5) result += run - 2;
          run = 1;
        }
      }
    }
    for (x = 0; x < size; x++) {
      run = 1;
      for (y = 1; y <= size; y++) {
        if (y < size && modules[y][x] === modules[y - 1][x]) {
          run++;
        } else {
          if (run >= 5) result += run - 2;
          run = 1;
        }
      }
    }
    for (y = 0; y < size - 1; y++) {
      for (x = 0; x < size - 1; x++) {
        var v = modules[y][x];
        if (v === modules[y][x + 1] && v === modules[y + 1][x] && v === modules[y + 1][x + 1]) result += 3;
      }
    }
    var patternA = [true, false, true, true, true, false, true, false, false, false, false];
    var patternB = [false, false, false, false, true, false, true, true, true, false, true];
    function matches(getter, start) {
      var a = true;
      var b = true;
      for (var i = 0; i < 11; i++) {
        var cell = getter(start + i);
        if (cell !== patternA[i]) a = false;
        if (cell !== patternB[i]) b = false;
        if (!a && !b) return false;
      }
      return true;
    }
    for (y = 0; y < size; y++) {
      for (x = 0; x + 11 <= size; x++) {
        if (matches(function(i) { return modules[y][i]; }, x)) result += 40;
      }
    }
    for (x = 0; x < size; x++) {
      for (y = 0; y + 11 <= size; y++) {
        if (matches(function(i) { return modules[i][x]; }, y)) result += 40;
      }
    }
    for (y = 0; y < size; y++) {
      for (x = 0; x < size; x++) {
        if (modules[y][x]) dark++;
      }
    }
    var totalModules = size * size;
    var k = Math.ceil(Math.abs(dark * 20 - totalModules * 10) / totalModules) - 1;
    if (k > 0) result += k * 10;
    return result;
  }

  function draw(canvas, text, pixelSize) {
    var qr = encode(text);
    if (!canvas || !canvas.getContext || !qr) return false;
    var quiet = 4;
    var scale = pixelSize || 8;
    var dim = (qr.size + quiet * 2) * scale;
    canvas.width = dim;
    canvas.height = dim;
    var ctx = canvas.getContext("2d");
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, dim, dim);
    ctx.fillStyle = "#000000";
    for (var y = 0; y < qr.size; y++) {
      for (var x = 0; x < qr.size; x++) {
        if (qr.modules[y][x]) ctx.fillRect((x + quiet) * scale, (y + quiet) * scale, scale, scale);
      }
    }
    return true;
  }

  return { encode: encode, draw: draw };
})();

if (typeof module !== "undefined" && module.exports) {
  module.exports = QR;
}
