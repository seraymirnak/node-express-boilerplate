pipeline {
    agent any

    environment {
        DOCKER_IMAGE  = 'seraymirnak/node-express-boilerplate'
        DOCKER_TAG    = "${env.BUILD_NUMBER}"
        SONAR_ORG     = 'seraymirnak'
        SONAR_PROJECT = 'seraymirnak_node-express-boilerplate'
    }

    stages {
        // ─────────────────────────────────────────────
        // STAGE 1 — BUILD
        // ─────────────────────────────────────────────
        stage('Build') {
            steps {
                echo "📦 Building Docker image → ${DOCKER_IMAGE}:${DOCKER_TAG}"
                git branch: 'master', url: 'https://github.com/seraymirnak/node-express-boilerplate.git'
                sh "docker build -t ${DOCKER_IMAGE}:${DOCKER_TAG} -t ${DOCKER_IMAGE}:latest ."
                sh "docker images ${DOCKER_IMAGE} --format 'Tag: {{.Tag}}  Size: {{.Size}}  Created: {{.CreatedAt}}'"
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 2 — TEST
        // ─────────────────────────────────────────────
        stage('Test') {
            steps {
                echo '🧪 Running unit tests inside Docker container...'
                sh "docker run --rm -e MONGODB_URL=mongodb://127.0.0.1:27017/test -e JWT_SECRET=testSecretKeyLongEnoughForValidation123 -e JWT_ACCESS_EXPIRATION_MINUTES=30 -e JWT_REFRESH_EXPIRATION_DAYS=30 -e SMTP_HOST=smtp.example.com -e SMTP_PORT=587 -e SMTP_USERNAME=test_user -e SMTP_PASSWORD=test_pass -e EMAIL_FROM=test@example.com ${DOCKER_IMAGE}:${DOCKER_TAG} npx jest tests/unit --testPathIgnorePatterns=paginate.plugin.test.js --forceExit --ci"
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 3 — CODE QUALITY (SonarCloud)
        // ─────────────────────────────────────────────
        stage('Code Quality') {
            steps {
                echo '🔍 Running SonarCloud static analysis via Docker CLI with Named Volumes...'
                withCredentials([string(credentialsId: 'sonarcloud-token', variable: 'SONAR_TOKEN')]) {
                    sh "docker rm -f sonar-temp || true"
                    sh "docker volume rm sonar-data || true"
                    sh "docker volume create sonar-data"
                    sh "docker create --name sonar-temp -v sonar-data:/usr/src alpine"
                    sh "docker cp . sonar-temp:/usr/src"
                    sh "docker run --rm -v sonar-data:/usr/src sonarsource/sonar-scanner-cli -Dsonar.organization=${SONAR_ORG} -Dsonar.projectKey=${SONAR_PROJECT} -Dsonar.sources=. -Dsonar.exclusions=**/node_modules/**,**/*.test.js -Dsonar.host.url=https://sonarcloud.io -Dsonar.token=${SONAR_TOKEN}"
                    sh "docker rm -f sonar-temp || true"
                    sh "docker volume rm sonar-data || true"
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 4 — SECURITY SCAN
        // ─────────────────────────────────────────────
        stage('Security Scan') {
            steps {
                echo '🔐 Running npm audit security vulnerability scan inside the container...'
                sh "docker run --rm ${DOCKER_IMAGE}:${DOCKER_TAG} npm audit --json > npm-audit-report.json || true"
                sh "docker run --rm ${DOCKER_IMAGE}:${DOCKER_TAG} npm audit --audit-level=info || true"
            }
            post {
                always {
                    archiveArtifacts artifacts: 'npm-audit-report.json', allowEmptyArchive: true
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 5 — DEPLOY TO STAGING
        // ─────────────────────────────────────────────
        stage('Deploy to Staging') {
            steps {
                echo '🚀 Deploying to Staging environment (port 3001)...'
                sh "docker network create app-network || true"
                sh "docker network connect app-network jenkins-local || true"
                sh "docker rm -f mongo-staging || true"
                sh "docker run -d --name mongo-staging --network app-network mongo:6"
                sh "docker rm -f node-app-staging || true"
                sh "docker run -d -p 3001:3000 --name node-app-staging --network app-network -e NODE_ENV=development -e MONGODB_URL=mongodb://mongo-staging:27017/node-express-staging -e JWT_SECRET=stagingSecretKeyLongEnough123 -e JWT_ACCESS_EXPIRATION_MINUTES=30 -e JWT_REFRESH_EXPIRATION_DAYS=30 -e SMTP_HOST=smtp.example.com -e SMTP_PORT=587 -e SMTP_USERNAME=staging_user -e SMTP_PASSWORD=staging_pass -e EMAIL_FROM=staging@example.com ${DOCKER_IMAGE}:${DOCKER_TAG}"
                echo '🔍 Waiting for Staging application to boot safely...'
                sh "sleep 15"
                sh "docker run --rm --network app-network curlimages/curl:7.85.0 curl -sf http://node-app-staging:3000/v1/docs/"
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 6 — RELEASE
        // ─────────────────────────────────────────────
        stage('Release') {
            steps {
                echo "🏷️ Releasing version ${DOCKER_TAG} to Docker Hub..."
                withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin'
                    sh "docker push ${DOCKER_IMAGE}:${DOCKER_TAG}"
                    sh "docker push ${DOCKER_IMAGE}:latest"
                    sh 'docker logout'
                }
                echo "✅ Released → docker pull ${DOCKER_IMAGE}:${DOCKER_TAG}"
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 7 — MONITORING & ALERTING
        // ─────────────────────────────────────────────
        stage('Monitoring & Alerting') {
            steps {
                echo '📊 Starting production environment + monitoring stack...'
                sh "docker rm -f node-app-prod mongo-prod || true"
                sh "docker run -d --name mongo-prod --network app-network mongo:6"
                sh "docker run -d -p 3000:3000 --name node-app-prod --network app-network -e NODE_ENV=development -e MONGODB_URL=mongodb://mongo-prod:27017/node-express-prod -e JWT_SECRET=prodSecretKeyUltraSecureLongEnough2026 -e JWT_ACCESS_EXPIRATION_MINUTES=30 -e JWT_REFRESH_EXPIRATION_DAYS=30 -e SMTP_HOST=smtp.example.com -e SMTP_PORT=587 -e SMTP_USERNAME=prod_user -e SMTP_PASSWORD=prod_pass -e EMAIL_FROM=prod@example.com ${DOCKER_IMAGE}:${DOCKER_TAG}"
                
                sh "docker rm -f cadvisor || true"
                sh "docker run -d --name cadvisor --network app-network -p 8081:8080 --volume=/var/run:/var/run:ro --volume=/sys:/sys:ro --volume=/var/lib/docker/:/var/lib/docker:ro gcr.io/cadvisor/cadvisor:latest || true"
                
                sh "docker rm -f prometheus || true"
                sh "docker run -d --name prometheus --network app-network -p 9090:9090 prom/prometheus:latest"
                sh "docker cp prometheus.yml prometheus:/etc/prometheus/prometheus.yml"
                sh "docker restart prometheus"
                
                sh "docker rm -f grafana || true"
                // Fixed: Added '-v grafana-storage:/var/lib/grafana' to inject a persistent database volume
                sh "docker run -d --name grafana --network app-network -p 3002:3000 -v grafana-storage:/var/lib/grafana -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:latest"
                
                echo '🔍 Verifying health reports for production stack...'
                sh "sleep 15"
                sh "docker run --rm --network app-network curlimages/curl:7.85.0 curl -sf http://node-app-prod:3000/v1/docs/"
                sh "docker run --rm --network app-network curlimages/curl:7.85.0 curl -sf http://prometheus:9090/-/ready"
                sh "docker run --rm --network app-network curlimages/curl:7.85.0 curl -sf http://grafana:3000/api/health"
                sh "docker stats --no-stream node-app-prod mongo-prod || true"
            }
        }
    }

    post {
        success {
            echo "SUCCESS: Pipeline completed flawlessly!"
        }
        failure {
            echo 'ERROR: Pipeline failed — check stage logs above for details.'
        }
    }
}
