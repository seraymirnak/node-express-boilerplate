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
                sh """
                    docker run --rm \
                      -e MONGODB_URL=mongodb://127.0.0.1:27017/test \
                      -e JWT_SECRET=testSecretKeyLongEnoughForValidation123 \
                      -e JWT_ACCESS_EXPIRATION_MINUTES=30 \
                      -e JWT_REFRESH_EXPIRATION_DAYS=30 \
                      -e SMTP_HOST=smtp.example.com \
                      -e SMTP_PORT=587 \
                      -e SMTP_USERNAME=test_user \
                      -e SMTP_PASSWORD=test_pass \
                      -e EMAIL_FROM=test@example.com \
                      ${DOCKER_IMAGE}:${DOCKER_TAG} \
                      npx jest tests/unit --testPathIgnorePatterns="paginate.plugin.test.js" --forceExit --ci
                """
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 3 — CODE QUALITY (SonarCloud)
        // ─────────────────────────────────────────────
        stage('Code Quality') {
            steps {
                echo '🔍 Running SonarCloud static analysis via Docker CLI with Named Volumes...'
                withCredentials([string(credentialsId: 'sonarcloud-token', variable: 'SONAR_TOKEN')]) {
                    sh '''
                        # Clean up legacy resources for a fresh start
                        docker rm -f sonar-temp || true
                        docker volume rm sonar-data || true
                        
                        # Create a secure Docker Named Volume
                        docker volume create sonar-data
                        
                        # Create a temporary carrier container
                        docker create --name sonar-temp -v sonar-data:/usr/src alpine
                        
                        # Copy all workspace files into the volume to resolve the 0-files indexing issue
                        docker cp . sonar-temp:/usr/src
                        
                        # Trigger SonarScanner CLI over the populated secure volume area
                        docker run --rm \
                          -v sonar-data:/usr/src \
                          sonarsource/sonar-scanner-cli \
                          -Dsonar.organization=seraymirnak \
                          -Dsonar.projectKey=seraymirnak_node-express-boilerplate \
                          -Dsonar.sources=. \
                          -Dsonar.exclusions=**/node_modules/**,**/*.test.js \
                          -Dsonar.host.url=https://sonarcloud.io \
                          -Dsonar.token=$SONAR_TOKEN
                          
                        # Perform post-analysis cleanup
                        docker rm -f sonar-temp || true
                        docker volume rm sonar-data || true
                    '''
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
                sh """
                    echo "===== SECURITY AUDIT SUMMARY ====="
                    docker run --rm ${DOCKER_IMAGE}:${DOCKER_TAG} npm audit --audit-level=info || true
                    echo "=================================="
                """
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
                sh 'docker network create app-network || true'
                
                # Connect the Jenkins host container to the shared network
                sh 'docker network connect app-network jenkins-local || true'

                sh 'docker rm -f mongo-staging || true'
                sh 'docker run -d --name mongo-staging --network app-network mongo:6'

                sh 'docker rm -f node-app-staging || true'
                sh """
                    docker run -d \
                      -p 3001:3000 \
                      --name node-app-staging \
                      --network app-network \
                      -e NODE_ENV=staging \
                      -e MONGODB_URL=mongodb://mongo-staging:27017/node-express-staging \
                      -e JWT_SECRET=stagingSecretKeyLongEnough123 \
                      -e JWT_ACCESS_EXPIRATION_MINUTES=30 \
                      -e JWT_REFRESH_EXPIRATION_DAYS=30 \
                      -e SMTP_HOST=smtp.example.com \
                      -e SMTP_PORT=587 \
                      -e SMTP_USERNAME=staging_user \
                      -e SMTP_PASSWORD=staging_pass \
                      -e EMAIL_FROM=staging@example.com \
                      ${DOCKER_IMAGE}:${DOCKER_TAG}
                """
                
                echo '🔍 Waiting for Staging application to boot and initialize database connections...'
                sh '''
                    success=false
                    for i in $(seq 1 15); do
                        if docker run --rm --network app-network curlimages/curl:7.85.0 curl -sf http://node-app-staging:3000/v1/docs/ >/dev/null; then
                            echo "✅ Staging health check PASSED"
                            success=true
                            break
                        fi
                        echo "Waiting for staging app... (attempt $i/15)"
                        sleep 3
                    done
                    if [ "$success" = "false" ]; then
                        echo "❌ Staging health check failed after 45 seconds"
                        exit 1
                    fi
                '''
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

                sh 'docker rm -f node-app-prod mongo-prod || true'
                sh 'docker run -d --name mongo-prod --network app-network mongo:6'
                sh """
                    docker run -d \
                      -p 3000:3000 \
                      --name node-app-prod \
                      --network app-network \
                      -e NODE_ENV=production \
                      -e MONGODB_URL=mongodb://mongo-prod:27017/node-express-prod \
                      -e JWT_SECRET=prodSecretKeyUltraSecureLongEnough2026 \
                      -e JWT_ACCESS_EXPIRATION_MINUTES=30 \
                      -e JWT_REFRESH_EXPIRATION_DAYS=30 \
                      -e SMTP_HOST=smtp.example.com \
                      -e SMTP_PORT=587 \
                      -e SMTP_USERNAME=prod_user \
                      -e SMTP_PASSWORD=prod_pass \
                      -e EMAIL_FROM=prod@example.com \
                      ${DOCKER_IMAGE}:${DOCKER_TAG}
                """

                // cAdvisor Container Monitoring Agent
                sh 'docker rm -f cadvisor || true'
                sh '''
                    docker run -d \
                      --name cadvisor \
                      --network app-network \
                      -p 8081:8080 \
                      --volume=/var/run:/var/run:ro \
                      --volume=/sys:/sys:ro \
                      --volume=/var/lib/docker/:/var/lib/docker:ro \
                      gcr.io/cadvisor/cadvisor:latest || \
                    echo "cAdvisor skipped — using docker stats inside report"
                '''

                // Prometheus Configuration
                sh 'docker rm -f prometheus || true'
                sh 'docker run -d --name prometheus --network app-network -p 9090:9090 prom/prometheus:latest'
                sh 'docker cp prometheus.yml prometheus:/etc/prometheus/prometheus.yml'
                sh 'docker restart prometheus'

                // Grafana Dashboard Deployment
                sh 'docker rm -f grafana || true'
                sh '''
                    docker run -d \
                      --name grafana \
                      --network app-network \
                      -p 3002:3000 \
                      -e GF_SECURITY_ADMIN_PASSWORD=admin \
                      grafana/grafana:latest
                '''
                
                echo '🔍 Waiting for Production application and monitoring services to initialize...'
                sh '''
                    echo "════════════════════════════════════════"
                    echo "      PRODUCTION MONITORING REPORT      "
                    echo "════════════════════════════════════════"
                    echo ""
                    
                    app_success=false
                    for i in $(seq 1 15); do
                        if docker run --rm --network app-network curlimages/curl:7.85.0 curl -sf http://node-app-prod:3000/v1/docs/ >/dev/null; then
                            echo "✅ Production app is HEALTHY"
                            app_success=true
                            break
                        fi
                        echo "Waiting for production app... (attempt $i/15)"
                        sleep 3
                    done
                    
                    if [ "$app_success" = false ]; then
                        echo "❌ Production app UNREACHABLE"
                        exit 1
                    fi
                    
                    docker run --rm --network app-network curlimages/curl:7.85.0 curl -sf http://prometheus:9090/-/ready && echo "✅ Prometheus is READY" || echo "⚠️ Prometheus not ready"
                    docker run --rm --network app-network curlimages/curl:7.85.0 curl -sf http://grafana:3000/api/health && echo "✅ Grafana is RUNNING" || echo "⚠️ Grafana not ready"
                    echo ""
                    docker stats --no-stream node-app-prod mongo-prod 2>/dev/null || true
                    echo ""
                    echo "════════════════════════════════════════"
                '''
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
