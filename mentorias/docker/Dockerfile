FROM nginx:alpine

# Metadatos OCI
LABEL org.opencontainers.image.title="halloween-aws-site" \
      org.opencontainers.image.description="Sitio estático Halloween con enlaces a AWS (Nginx)" \
      org.opencontainers.image.source="educativo" \
      org.opencontainers.image.authors="Tu Nombre"

# Crear usuario no root
RUN adduser -D -u 10001 appuser

# Copiar html y configuración
COPY index.html /usr/share/nginx/html/index.html
COPY nginx.conf /etc/nginx/nginx.conf

# Cambiar propietario para permitir lectura
RUN chown -R appuser:appuser /usr/share/nginx/html

# Puerto expuesto (interno en el contenedor)
EXPOSE 8080

# Usar usuario no root
USER 10001

# Ejecutar Nginx en primer plano (daemon off por defecto en imagen oficial)
CMD ["nginx", "-g", "daemon off;"]
