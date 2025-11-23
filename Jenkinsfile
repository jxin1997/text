pipeline {
    agent any

    environment {
        REGISTRY = "192.168.10.67"
        PROJECT = "jenkins"
        APP_NAME = "hello-k8s-app"
        KUBECONFIG_CREDENTIALS = credentials('kubeconfig-credentials')
    }

    stages {
        stage('Build & Push Docker Image') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: '12345678', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS')]) {
                        sh 'echo "Logging into Harbor..."'
                        sh 'docker login -u ${HARBOR_USER} -p ${HARBOR_PASS} ${REGISTRY}'
                        sh 'echo "Building Docker image..."'
                        sh 'docker build -t ${REGISTRY}/${PROJECT}/${APP_NAME}:BUILD-${BUILD_NUMBER} ./hello-k8s-app'
                        sh 'echo "Pushing Docker images..."'
                        sh 'docker push ${REGISTRY}/${PROJECT}/${APP_NAME}:BUILD-${BUILD_NUMBER}'
                        sh 'docker tag ${REGISTRY}/${PROJECT}/${APP_NAME}:BUILD-${BUILD_NUMBER} ${REGISTRY}/${PROJECT}/${APP_NAME}:latest'
                        sh 'docker push ${REGISTRY}/${PROJECT}/${APP_NAME}:latest'
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'kubeconfig-credentials', variable: 'KUBECONFIG_FILE')]) {
                        // 直接使用 KUBECONFIG_FILE 路径，无需创建 .env 和 load
                        sh 'echo "Updating deployment.yaml..."'
                        sh 'sed -i "" "s|image:.*|image: ${REGISTRY}/${PROJECT}/${APP_NAME}:BUILD-${BUILD_NUMBER}|" hello-k8s-app/k8s/deployment.yaml'
                        // 用 --kubeconfig 指定配置文件，避免环境变量解析
                        sh 'kubectl --kubeconfig ${KUBECONFIG_FILE} apply -f hello-k8s-app/k8s/deployment.yaml'
                    }
                }
            }
        }

        stage('Test Deployment') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'kubeconfig-credentials', variable: 'KUBECONFIG_FILE')]) {
                        // 所有 kubectl 命令都用 --kubeconfig 指定配置文件
                        sh 'kubectl --kubeconfig ${KUBECONFIG_FILE} wait --for=condition=ready pod -l app=hello-k8s-app --timeout=60s || { echo "❌ Pod 启动超时"; exit 1; }'
                        sh 'NODE_IP=$(kubectl --kubeconfig ${KUBECONFIG_FILE} get node -o jsonpath="{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}")'
                        sh 'NODE_PORT=$(kubectl --kubeconfig ${KUBECONFIG_FILE} get svc hello-k8s-app-service -o jsonpath="{.spec.ports[0].nodePort}" --ignore-not-found)'
                        sh 'if [ -z "${NODE_IP}" ] || [ -z "${NODE_PORT}" ]; then echo "❌ 无法获取 NodeIP/NodePort"; exit 1; fi'
                        sh 'curl --retry 10 --retry-delay 5 --retry-connrefused --fail http://${NODE_IP}:${NODE_PORT}'
                        // 获取访问地址并输出
                        def nodeIp = sh(script: 'kubectl --kubeconfig ${KUBECONFIG_FILE} get node -o jsonpath="{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}"', returnStdout: true).trim()
                        def nodePort = sh(script: 'kubectl --kubeconfig ${KUBECONFIG_FILE} get svc hello-k8s-app-service -o jsonpath="{.spec.ports[0].nodePort}"', returnStdout: true).trim()
                        echo "✅ 部署成功！访问地址：http://${nodeIp}:${nodePort}"
                    }
                }
            }
        }
    }

    post {
        always {
            echo "流水线执行完毕"
            sh 'if [ -n "${REGISTRY:-}" ] && [ -n "${PROJECT:-}" ] && [ -n "${APP_NAME:-}" ] && [ -n "${BUILD_NUMBER:-}" ]; then docker rmi ${REGISTRY}/${PROJECT}/${APP_NAME}:BUILD-${BUILD_NUMBER} ${REGISTRY}/${PROJECT}/${APP_NAME}:latest || true; else echo "⚠️  环境变量未加载或无 Docker 权限，跳过镜像清理"; fi'
            // 无需清理 tmp_kube（已删除创建逻辑）
            sh 'rm -rf .env || true'
        }
    }
}
