pipeline {
    agent any

    environment {
        REGISTRY = "192.168.10.67"       // Harbor 地址（无 https）
        PROJECT = "jenkins"
        APP_NAME = "hello-k8s-app"
        KUBECONFIG_CREDENTIALS = credentials('kubeconfig-credentials')
    }

    stages {
        stage('Build & Push Docker Image') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: '12345678', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS')]) {
                        sh """
                        echo "Logging into Harbor..."
                        docker login -u \${HARBOR_USER} -p \${HARBOR_PASS} \${REGISTRY}

                        echo "Building Docker image..."
                        docker build -t \${REGISTRY}/\${PROJECT}/\${APP_NAME}:BUILD-\${BUILD_NUMBER} ./hello-k8s-app

                        echo "Pushing Docker images..."
                        docker push \${REGISTRY}/\${PROJECT}/\${APP_NAME}:BUILD-\${BUILD_NUMBER}
                        docker tag \${REGISTRY}/\${PROJECT}/\${APP_NAME}:BUILD-\${BUILD_NUMBER} \${REGISTRY}/\${PROJECT}/\${APP_NAME}:latest
                        docker push \${REGISTRY}/\${PROJECT}/\${APP_NAME}:latest
                        """
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'kubeconfig-credentials', variable: 'KUBECONFIG_FILE')]) {
                        sh """
                        mkdir -p \${WORKSPACE}/tmp_kube
                        cp \${KUBECONFIG_FILE} \${WORKSPACE}/tmp_kube/config
                        # Shell 脚本内可用 # 注释
                        echo "KUBECONFIG=\${WORKSPACE}/tmp_kube/config" > \${WORKSPACE}/tmp_kube/.env
                        """
                        // Groovy 代码用 // 注释
                        load "\${WORKSPACE}/tmp_kube/.env"
                        sh """
                        echo "Updating deployment.yaml..."
                        sed -i'' 's|image:.*|image: \${REGISTRY}/\${PROJECT}/\${APP_NAME}:BUILD-\${BUILD_NUMBER}|' hello-k8s-app/k8s/deployment.yaml
                        kubectl apply -f hello-k8s-app/k8s/deployment.yaml
                        """
                    }
                }
            }
        }

        stage('Test Deployment') {
            steps {
                script {
                    sh """
                    export KUBECONFIG=\${KUBECONFIG}
                    kubectl wait --for=condition=ready pod -l app=hello-k8s-app --timeout=60s || { echo "❌ Pod 启动超时"; exit 1; }
                    NODE_IP=\$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
                    NODE_PORT=\$(kubectl get svc hello-k8s-app-service -o jsonpath='{.spec.ports[0].nodePort}' --ignore-not-found)
                    if [ -z "\${NODE_IP}" ] || [ -z "\${NODE_PORT}" ]; then
                        echo "❌ 无法获取 NodeIP/NodePort"; exit 1;
                    fi
                    curl --retry 10 --retry-delay 5 --retry-connrefused --fail http://\${NODE_IP}:\${NODE_PORT}
                    """
                    def nodeIp = sh(script: 'kubectl get node -o jsonpath="{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}"', returnStdout: true).trim()
                    def nodePort = sh(script: 'kubectl get svc hello-k8s-app-service -o jsonpath="{.spec.ports[0].nodePort}"', returnStdout: true).trim()
                    echo "✅ 部署成功！访问地址：http://\${nodeIp}:\${nodePort}"
                }
            }
        }
    }

    post {
        always {
            echo "流水线执行完毕"
            sh """
            if [ -n "\${REGISTRY:-}" ] && [ -n "\${PROJECT:-}" ] && [ -n "\${APP_NAME:-}" ] && [ -n "\${BUILD_NUMBER:-}" ]; then
                docker rmi \${REGISTRY}/\${PROJECT}/\${APP_NAME}:BUILD-\${BUILD_NUMBER} \${REGISTRY}/\${PROJECT}/\${APP_NAME}:latest || true
            else
                echo "⚠️  环境变量未加载或无 Docker 权限，跳过镜像清理"
            fi
            rm -rf \${WORKSPACE}/tmp_kube \${WORKSPACE}/.env || true
            """
        }
    }
}
