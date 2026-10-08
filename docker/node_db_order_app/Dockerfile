FROM node:20-bookworm-slim

WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev

COPY src ./src
COPY entrypoint.sh ./entrypoint.sh

RUN chmod +x ./entrypoint.sh

EXPOSE 3000

ENV NODE_ENV=production

ENTRYPOINT ["./entrypoint.sh"]
