FROM node:20-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci --legacy-peer-deps

COPY tsconfig*.json nest-cli.json ./
COPY src ./src

RUN npm run build

FROM node:20-alpine AS runtime

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

RUN addgroup -S nodejs && adduser -S nestjs -G nodejs

COPY package*.json ./
RUN npm ci --omit=dev --legacy-peer-deps && npm cache clean --force

COPY --from=build --chown=nestjs:nodejs /app/dist ./dist

USER nestjs

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD node -e "const net=require('net');const socket=net.connect({host:'127.0.0.1',port:process.env.PORT||3000},()=>{socket.end();process.exit(0)});socket.on('error',()=>process.exit(1));setTimeout(()=>{socket.destroy();process.exit(1)},4000)"

CMD ["node", "dist/main.js"]

