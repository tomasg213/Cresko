import sharp from "sharp";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.join(__dirname, "..", "public");
const svg = path.join(publicDir, "icon.svg");

for (const size of [192, 512]) {
  await sharp(svg).resize(size, size).png().toFile(path.join(publicDir, `icon-${size}.png`));
  console.log(`generated icon-${size}.png`);
}

await sharp(svg)
  .resize(180, 180)
  .png()
  .toFile(path.join(publicDir, "apple-touch-icon.png"));
console.log("generated apple-touch-icon.png");

const maskable = path.join(publicDir, "icon-maskable.svg");
await sharp(maskable).resize(512, 512).png().toFile(path.join(publicDir, "icon-maskable-512.png"));
console.log("generated icon-maskable-512.png");