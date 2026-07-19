pipeline {
    agent any

    stages {
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
            archiveArtifacts artifacts: '*.tar.gz', fingerprint: true
        }
        always {
            echo "Pipeline finished with status: ${currentBuild.currentResult}"
        }
    }
}
