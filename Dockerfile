FROM node:alpine

RUN mkdir -p /usr/src/node-app && chown -R node:node /usr/src/node-app

WORKDIR /usr/src/node-app

COPY package.json ./

RUN npm install

COPY --chown=node:node . .

USER node

EXPOSE 3000

CMD ["node", "src/index.js"]
