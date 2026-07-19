pipeline {
    agent any

    options {
        timeout(time: 10, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
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
                echo "Build number ${env.BUILD_NUMBER} on ${env.NODE_NAME}"
                sh 'python3 --version'
            }
        }
        stage('Test') {
            steps {
                sh 'python3 -m unittest discover -v'
            }
        }
        stage('Package') {
            steps {
                sh 'tar -czf app-${BUILD_NUMBER}.tar.gz app.py'
            }
        }
    }

    post {
        success {
            archiveArtifacts artifacts: 'app-*.tar.gz', fingerprint: true
        }
        always {
            echo "Pipeline finished with status: ${currentBuild.currentResult}"
        }
    }
}
