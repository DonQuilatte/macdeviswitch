FROM node:16‑alpine
WORKDIR /workspace/src
COPY src/ .
RUN npm ci
CMD ["npm", "start"]
