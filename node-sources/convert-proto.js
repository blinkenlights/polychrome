#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { argv } from 'node:process';
import { parseSchema } from 'pbjs';

// convert .proto to es6 module

console.log(argv)
const p = resolve(argv[2])
console.log(p)

if (!p.endsWith('.proto')) {
    process.exit(1)
}

const raw = readFileSync(p)
console.log(raw.toString())
const replaced = raw.toString().replace(/( \[[^\]]+\])/g, '')
console.log(replaced)

const f = parseSchema(Buffer.from(replaced))
try {
    writeFileSync('packet.js', f.toJavaScript({es6:true}))
} catch (e) {
    console.error(e)
}
