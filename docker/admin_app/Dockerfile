FROM node:18-alpine

WORKDIR /app

COPY package.json .
RUN npm install --only=production

COPY app.js .

ARG SERVICE_NAME=admin_app
RUN addgroup -S ${SERVICE_NAME} && \
    adduser -S ${SERVICE_NAME} -G ${SERVICE_NAME}
USER ${SERVICE_NAME}

EXPOSE 4000

CMD ["node", "app.js"]
