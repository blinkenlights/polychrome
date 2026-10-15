import { createCanvas } from 'canvas'

export const pixels = 640
export const windowMargin = 18
export const virtualScreenW = 10 * 8 + 9 * windowMargin;
export const virtualScreenH = 8;
export const ratio = virtualScreenW / virtualScreenH

// const attributes = { pixelFormat: 'RGB32' }
export const canvas = createCanvas(virtualScreenW, virtualScreenH)
export const ctx = canvas.getContext('2d');
ctx.antialias = 'none'

export async function canvasToRGBFrame (canvas) {
    // const imageData = ctx.getImageData(0, 0, virtualScreenW, virtualScreenH);
    // console.log(imageData.data)

    // debug
    // const out = createWriteStream('./test.png')
    // const stream = canvas.createPNGStream()
    // stream.pipe(out)

    const targetBuffer = Buffer.from(Array(pixels*3)) // rgb_frame
    const rawBGRA = canvas.toBuffer("raw")

    for (let window = 0; window < 10; window++) {
        for (let y = 0; y < 8; y++) {
            for (let x = 0; x < 8; x++) {
                // map target to source pixel index
                const targetBufferIndex = 3 * (window * 64 + y * 8 + x)
                const sourceBufferIndex = 4 * (window * (8 + windowMargin) + y * virtualScreenW + x)

                // read r g b from source - source is BGRA
                const b = rawBGRA[sourceBufferIndex]
                const g = rawBGRA[sourceBufferIndex+1]
                const r = rawBGRA[sourceBufferIndex+2]

                // console.log({sourceBufferIndex, targetBufferIndex, r,g,b})
                // write r g b to target
                targetBuffer[targetBufferIndex] = r
                targetBuffer[targetBufferIndex+1] = g
                targetBuffer[targetBufferIndex+2] = b
            }
        }
    }

    // console.log(targetBuffer)
    return targetBuffer
}
