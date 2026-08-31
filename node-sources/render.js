// USAGE
// node render.js [<hostname>]

// EXAMPLE
// node render.js localhost

import { randomInt } from "node:crypto";
import { canvas, ctx, canvasToRGBFrame, virtualScreenH, virtualScreenW } from './virtual-screen.js'
import { rgbFrame, send, demoServer, addListener } from './server.js'

let windowCenters = Array(10).fill(0).map((v,i) => 4 + (18 + 8) * i)

let currentWindow = 4
let center = windowCenters[currentWindow]

async function gen(tick) {
    const x = tick % virtualScreenW
    const y = tick % virtualScreenH
    ctx.save()

    const x0 = randomInt(center-1, center+1)
    const y0 = randomInt(virtualScreenH/2-1,virtualScreenH/2+1)
    const x1 = randomInt(0,virtualScreenW)
    const y1 = randomInt(0,virtualScreenH)

    ctx.beginPath()

    let sweep = ctx.createLinearGradient(x0, y0, x1, y1)
    sweep.addColorStop(0, "red")
    sweep.addColorStop(0.25, "orange")
    sweep.addColorStop(0.5, "yellow")
    sweep.addColorStop(0.75, "green")
    sweep.addColorStop(1, "blue")
    ctx.strokeStyle = sweep
    ctx.lineWidth = 0.5
    ctx.lineCap = "square"
    // console.log(x0, y0, x1, y1)
    ctx.moveTo(x0, y0)
    ctx.lineTo(x1, y1)
    ctx.closePath()
    ctx.stroke()
    ctx.restore()
    return await canvasToRGBFrame(canvas)
}

// function mutateRandomPixel (d) {
//     const i = randomInt(0, 640)
//     d[i] = randomInt(0, 8)
// }

function printUsage () {
    console.log("USAGE")
    console.log("node render.js [<hostname>]")
    console.log("EXAMPLE")
    console.log("node render.js localhost")
}

// console.log(process.argv.length)
if (process.argv.length < 3 || process.argv.length > 3) {
    printUsage()
    process.exit(1)
}

const server = process.argv[2] ? process.argv[2] : demoServer
console.log("sending data to", server)
console.log("stop server with ctrl+c")
await new Promise(res => setTimeout(async _ => res(true), 500)) // ~60 frames per second

let t = 0

process.on('beforeExit', e => console.log("bye bye"))
addListener(msg => {
    const type = msg.input_event.type
    // console.log(msg.input_event)
    switch(type) {
        case 'BUTTON_2':
            currentWindow = Math.min(currentWindow+1, 9);
            break;
        case 'BUTTON_3': break;
        case 'BUTTON_4': break;
        case 'BUTTON_5': break;
        case 'BUTTON_6': break;
        case 'BUTTON_7': break;
        case 'BUTTON_8': break;
        case 'BUTTON_9': break;
        case 'BUTTON_10':
            ctx.clearRect(0, 0, virtualScreenW, virtualScreenH)
            break;
        default: 
            currentWindow = Math.max(currentWindow-1, 0);
            break;
    }

    center = windowCenters[currentWindow]
})

while (true) {
    t++;
    // console.log(t)
    await send(server, rgbFrame(await gen(t)))
    await new Promise(res => setTimeout(async _ => res(true), 600)) // ~60 frames per second
}
