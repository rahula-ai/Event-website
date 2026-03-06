# ── Frontend: Nginx static server ─────────────────────────────────────────────
FROM nginx:1.27-alpine AS runtime

LABEL maintainer="Dharmasthala Events Team"
LABEL org.opencontainers.image.title="dharmasthala-frontend"

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx config for this container
COPY nginx-local.conf /etc/nginx/conf.d/default.conf

# Copy static files
COPY --chown=nginx:nginx . /usr/share/nginx/html/

# Security: drop all nginx default pages
RUN rm -f /usr/share/nginx/html/50x.html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD wget -qO- http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
