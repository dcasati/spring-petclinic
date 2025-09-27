## Multi-stage Dockerfile for Spring Petclinic
# Build stage
FROM maven:3.9.4-eclipse-temurin-17 as builder
WORKDIR /workspace
COPY pom.xml ./
COPY src ./src
# Use Maven to build the fat/executable jar produced by spring-boot-maven-plugin
RUN mvn -B -DskipTests package

# Runtime stage
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
ARG JAR_FILE=target/*.jar
COPY --from=builder /workspace/${JAR_FILE} app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]
