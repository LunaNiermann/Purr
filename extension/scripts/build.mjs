import { build, context } from "esbuild";
import { cpSync, mkdirSync } from "node:fs";

const watch = process.argv.includes("--watch");

const options = {
  entryPoints: {
    background: "src/background.ts",
    content: "src/content.ts",
    popup: "src/popup/popup.ts",
    options: "src/options/options.ts",
  },
  bundle: true,
  format: "iife", // MV3 content scripts can't be ES modules; iife works everywhere
  outdir: "dist",
  target: "chrome116",
  sourcemap: false,
  minify: false,
  logLevel: "info",
};

mkdirSync("dist", { recursive: true });
cpSync("public", "dist", { recursive: true });

if (watch) {
  const ctx = await context(options);
  await ctx.watch();
} else {
  await build(options);
}
