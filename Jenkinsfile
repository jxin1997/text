pipeline {
    agent any

    environment {
        REGISTRY = "192.168.10.67"
        PROJECT = "jenkins"
        APP_NAME = "hello-k8s-app"
        KUBECONFIG_CREDENTIALS = credentials('kubeconfig-credentials')
    }

    stage('Deploy to Kubernetes') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'kubeconfig-credentials', variable: 'KUBECONFIG_FILE')]) {
                        sh """
                        mkdir -p $WORKSPACE/tmp_kube
                        cp $KUBECONFIG_FILE $WORKSPACE/tmp_kube/config
                        export KUBECONFIG=$WORKSPACE/tmp_kube/config

                        echo "Updating deployment.yaml with new image..."
                        sed -i 's|image:.*|image: $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER|' hello-k8s-app/k8s/deployment.yaml

                        echo "Applying deployment..."
                        kubectl apply -f hello-k8s-app/k8s/deployment.yaml
                        """
                    }
                }
            }
        }


        stage('Deploy to Kubernetes') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'kubeconfig-credentials', variable: 'KUBECONFIG_FILE')]) {
                        // 1. 调试：打印根目录所有文件，确认 deployment.yaml 存在（关键）
                        sh 'echo "=== 仓库根目录文件列表 ==="'
                        sh 'ls -l'  // 会显示 deployment.yaml 和 service.yaml，确认存在
                        
                        // 2. 修正 sed 语法（Linux 兼容）和路径（根目录直接写文件名）
                        sh 'echo "Updating deployment.yaml..."'
                        sh 'sed -i "s|image:.*|image: ${REGISTRY}/${PROJECT}/${APP_NAME}:BUILD-${BUILD_NUMBER}|" deployment.yaml'
                        
                        // 3. 同时应用 deployment 和 service（根目录路径）
                        sh 'echo "Applying deployment and service..."'
                        sh 'kubectl --kubeconfig ${KUBECONFIG_FILE} apply -f deployment.yaml'
                        sh 'kubectl --kubeconfig ${KUBECONFIG_FILE} apply -f service.yaml'
                    }
                }
            }
        }

        stage('Test Deployment') {
    steps {
        script {
            withCredentials([file(credentialsId: 'kubeconfig-credentials', variable: 'KUBECONFIG_FILE')]) {
                // 1. 等待 Pod 就绪（超时 60s，失败直接退出）
                sh '''
                    kubectl --kubeconfig ${KUBECONFIG_FILE} wait --for=condition=ready pod -l app=hello-k8s-app --timeout=60s || {
                        echo "❌ Pod 启动超时或未就绪";
                        exit 1;
                    }
                '''

                // 2. 获取 NodeIP 和 NodePort（用单引号包裹 JSONPath，避免双引号转义问题）
                // 关键修正：JSONPath 用单引号，InternalIP 用双引号，且通过 returnStdout 直接获取变量（避免多 sh 步骤变量传递失败）
                def nodeIp = sh(
                    script: 'kubectl --kubeconfig ${KUBECONFIG_FILE} get node -o jsonpath=\'{.items[0].status.addresses[?(@.type=="InternalIP")].address}\'',
                    returnStdout: true
                ).trim()

                def nodePort = sh(
                    script: 'kubectl --kubeconfig ${KUBECONFIG_FILE} get svc hello-k8s-app-service -o jsonpath=\'{.spec.ports[0].nodePort}\' --ignore-not-found',
                    returnStdout: true
                ).trim()

                // 3. 验证 NodeIP 和 NodePort 非空
                if (nodeIp.empty || nodePort.empty) {
                    echo "❌ 无法获取 NodeIP 或 NodePort（NodeIP: ${nodeIp}, NodePort: ${nodePort}）";
                    exit 1;
                }

                // 4. 重试访问应用（兼容启动延迟，增强稳定性）
                sh """
                    echo "🔍 测试访问应用：http://${nodeIp}:${nodePort}";
                    curl --retry 10 \
                         --retry-delay 5 \
                         --retry-connrefused \
                         --fail \
                         -v http://${nodeIp}:${nodePort} || {
                        echo "❌ 应用访问失败";
                        exit 1;
                    }
                """

                // 5. 输出成功信息（带访问地址）
                echo "✅ 部署成功！应用访问地址：http://${nodeIp}:${nodePort}";
            }
        }
    }
}

    post {
        always {
            echo "流水线执行完毕"
            sh 'if [ -n "${REGISTRY:-}" ] && [ -n "${PROJECT:-}" ] && [ -n "${APP_NAME:-}" ] && [ -n "${BUILD_NUMBER:-}" ]; then docker rmi ${REGISTRY}/${PROJECT}/${APP_NAME}:BUILD-${BUILD_NUMBER} ${REGISTRY}/${PROJECT}/${APP_NAME}:latest || true; else echo "⚠️  环境变量未加载或无 Docker 权限，跳过镜像清理"; fi'
            sh 'rm -rf .env || true'
        }
    }
}
