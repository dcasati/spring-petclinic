## Multi-stage Dockerfile for Spring Petclinic
# Build stage
FROM maven:3.9.4-eclipse-temurin-17 as builder
WORKDIR /workspace
COPY pom.xml ./
COPY src ./src
# Use Maven to build the fat/executable jar produced by spring-boot-maven-plugin
RUN mvn -B -DskipTests package

# Runtime stage
FROM openjdk:17-jre-slim
WORKDIR /app
# Install curl for container HEALTHCHECK
RUN apt-get update \
	&& apt-get install -y --no-install-recommends curl ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

ARG JAR_FILE=target/*.jar
COPY --from=builder /workspace/${JAR_FILE} app.jar

# Create non-root user to run the application
RUN useradd --create-home --shell /bin/bash appuser \
	&& chown -R appuser:appuser /app

EXPOSE 8080
# Container-level healthcheck (checks Spring Boot actuator health endpoint)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
	CMD curl -f http://localhost:8080/actuator/health || exit 1

USER appuser
ENTRYPOINT ["java","-jar","/app/app.jar"]
