// USAGE
// node scan-image.js <path/to/image> [<hostname>]

// EXAMPLE
// node scan-image.js test-pixels.png localhost

import { resolve } from "node:path";
import { loadImage } from 'canvas'
import { ratio, virtualScreenW, virtualScreenH, canvas, ctx, canvasToRGBFrame } from './virtual-screen.js'
import { rgbFrame, close, send, demoServer } from './server.js'

async function scan (tick) {
    const offset = tick % imageH
    ctx.drawImage(image, 0, offset, imageW, imageW/ratio, 0, 0, virtualScreenW, virtualScreenH)
    return await canvasToRGBFrame(canvas)
}

function printUsage () {
    console.log("USAGE")
    console.log("node scan-image.js <path/to/image> [<hostname>]")
    console.log("EXAMPLE")
    console.log("node scan-image.js test-pixels.png localhost")
}

// console.log(process.argv.length)
if (process.argv.length < 3 || process.argv.length > 4) {
    printUsage()
    process.exit(1)
}

const path = resolve(process.argv[2])
const image = await loadImage(path)
const imageW = image.width
const imageH = image.height

const server = process.argv[3] ? process.argv[3] : demoServer
console.log("sending data to", server)
console.log(imageH)

await send(server, rgbFrame(await scan(0)))

for (let t = 1; t < imageH - virtualScreenH; t++) {
    console.log(t)
    await send(server, rgbFrame(await scan(t)))
    await new Promise(res => setTimeout(async _ => res(true), 16)) // ~60 frames per second
}

console.log("bye bye")
close()
