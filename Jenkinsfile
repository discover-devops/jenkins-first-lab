cat > Jenkinsfile <<'EOF'
pipeline {
    agent any

    options {
        timeout(time: 10, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }

    environment {
        DEPLOY_DIR = '/var/www/lab'
        APP_URL    = 'http://localhost'
    }

    stages {

        stage('Checkout') {
            steps {
                cleanWs()
                checkout scm
            }
        }

        stage('Build') {
            steps {
                echo "Building #${env.BUILD_NUMBER} on ${env.NODE_NAME}"
                sh '''
                    mkdir -p build
                    cp index.html build/index.html

                    SHORT_SHA=$(git rev-parse --short HEAD)
                    BUILD_TIME=$(date -u "+%Y-%m-%d %H:%M UTC")

                    sed -i "s|__BUILD_NUMBER__|${BUILD_NUMBER}|g" build/index.html
                    sed -i "s|__GIT_COMMIT__|${SHORT_SHA}|g"      build/index.html
                    sed -i "s|__BUILD_TIME__|${BUILD_TIME}|g"     build/index.html

                    echo "--- built file ---"
                    grep -E "Build number|Commit|Deployed at" build/index.html
                '''
            }
        }

        stage('Test') {
            steps {
                sh 'chmod +x test.sh && ./test.sh'
            }
        }

        stage('Deploy') {
            steps {
                sh '''
                    cp build/index.html ${DEPLOY_DIR}/index.html
                    ls -l ${DEPLOY_DIR}/
                '''
            }
        }

        stage('Verify') {
            steps {
                sh '''
                    sleep 2
                    STATUS=$(curl -s -o /dev/null -w "%{http_code}" ${APP_URL}/)
                    echo "HTTP status: $STATUS"
                    if [ "$STATUS" != "200" ]; then
                        echo "FAIL: site did not return 200"
                        exit 1
                    fi

                    if curl -s ${APP_URL}/ | grep -q "${BUILD_NUMBER}"; then
                        echo "PASS: live page is serving build ${BUILD_NUMBER}"
                    else
                        echo "FAIL: live page does not show build ${BUILD_NUMBER}"
                        exit 1
                    fi
                '''
            }
        }
    }

    post {
        success {
            archiveArtifacts artifacts: 'build/index.html', fingerprint: true
            echo "Deployed. Open the EC2 public IP on port 80 to see build ${env.BUILD_NUMBER}"
        }
        failure {
            echo "Build ${env.BUILD_NUMBER} failed. The previous version is still live."
        }
        always {
            echo "Result: ${currentBuild.currentResult}"
        }
    }
}
EOF
