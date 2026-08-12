# Purr relay server — single container for plain Docker deploys.
# NOTE: the live Coolify instance does NOT use this file; it builds with
# Nixpacks (see nixpacks.toml and README "Deploy on Coolify"). Kept in sync
# as the reference for what the deployed container must do.
# Mount a volume at /app/data to persist the SQLite database.
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY site ./site
COPY package.json ./
RUN mkdir -p /app/data && chown node:node /app/data
USER node
VOLUME /app/data
ENV DB_PATH=/app/data/twokeys.sqlite
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s CMD node -e "fetch('http://127.0.0.1:3000/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/main.js"]
