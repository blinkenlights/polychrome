const debounce = (func, delay) => {
  let timer;
  return () => {
    if (timer) {
      clearTimeout(timer);
    }
    timer = setTimeout(func, delay);
  };
};

function resize(canvas, layout) {
  if (!layout) {
    return;
  }

  if (window.innerWidth > window.innerHeight) {
    canvas.style.height = "100%";
    canvas.style.width = "unset";
    canvas.height = canvas.offsetHeight;
    canvas.width =
      canvas.height / (layout.image_size[1] / layout.image_size[0]);
  } else {
    canvas.style.width = "100%";
    canvas.style.height = "unset";
    canvas.width = canvas.offsetWidth;
    canvas.height =
      canvas.width / (layout.image_size[0] / layout.image_size[1]);
  }
}

export function setup(canvas) {
  let pixels = [];
  let layout = {};
  let scale = 1.0;
  const textEncoder = new TextEncoder();
  const pixelImage = new Image();
  pixelImage.src = "/images/mildenberg-pixel.png";

  const ctx = canvas.getContext("2d");

  resize(canvas);

  window.addEventListener(
    "resize",
    debounce(() => resize(canvas), 10)
  );

  this.handleEvent("layout", ({ layout: newLayout }) => {
    layout = newLayout;
    resize(canvas, layout);
  });

  this.handleEvent("pixels", ({ pixels: newPixels }) => {
    pixels = textEncoder.encode(newPixels);
  });

  const draw = () => {
    if (Object.keys(layout).length < 1) {
      window.requestAnimationFrame(draw);
      return;
    }

    scale = canvas.width / layout.image_size[0];

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    console.log(pixels);
    layout.positions.forEach(([x, y], i) => {
      const pixel = pixels[i];

      if (pixel === undefined) {
        ctx.fillStyle = "hsl(40, 80%, 5%";
      } else {
        ctx.fillStyle = `hsl(40, 80%, ${(95 / 8) * pixel + 5}%)`;
      }

      ctx.fillRect(
        x * scale,
        y * scale,
        layout.pixel_size[0] * scale,
        layout.pixel_size[1] * scale
      );

      ctx.drawImage(
        pixelImage,
        x * scale,
        y * scale,
        layout.pixel_size[0] * scale,
        layout.pixel_size[1] * scale
      );
    });

    window.requestAnimationFrame(draw);
  };

  window.requestAnimationFrame(draw);
}
