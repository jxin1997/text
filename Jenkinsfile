pipeline {
    agent any

    environment {
        REGISTRY = "192.168.10.67"       // 去掉 https://，仅保留 Harbor 地址
        PROJECT = "jenkins"
        APP_NAME = "hello-k8s-app"
        KUBECONFIG_CREDENTIALS = credentials('kubeconfig-credentials') // Kubeconfig 凭证声明
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'master', url: 'https://github.com/jxin1997/text.git'
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                script {
                    // 引用 Harbor 用户名密码凭证（credentialsId 确保与 Jenkins 中一致）
                    withCredentials([usernamePassword(
                        credentialsId: '12345678', 
                        usernameVariable: 'HARBOR_USER', 
                        passwordVariable: 'HARBOR_PASS'
                    )]) {
                        sh """
                        echo "Logging into Harbor..."
                        docker login -u $HARBOR_USER -p $HARBOR_PASS $REGISTRY

                        echo "Building Docker image..."
                        // 确保 ./hello-k8s-app 目录下有 Dockerfile（否则需调整路径）
                        docker build -t $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER ./hello-k8s-app

                        echo "Pushing Docker images..."
                        docker push $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER
                        docker tag $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER $REGISTRY/$PROJECT/$APP_NAME:latest
                        docker push $REGISTRY/$PROJECT/$APP_NAME:latest
                        """
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    withCredentials([file(
                        credentialsId: 'kubeconfig-credentials', 
                        variable: 'KUBECONFIG_FILE'
                    )]) {
                        sh """
                        # 创建临时目录存储 kubeconfig（跨阶段复用）
                        mkdir -p $WORKSPACE/tmp_kube
                        cp $KUBECONFIG_FILE $WORKSPACE/tmp_kube/config
                        # 写入环境变量文件，供后续阶段加载
                        echo "KUBECONFIG=$WORKSPACE/tmp_kube/config" > $WORKSPACE/.env
                        """
                        // 加载 kubeconfig 到 Jenkins 全局环境变量
                        load "$WORKSPACE/.env"
                        sh """
                        echo "Updating deployment.yaml with new image..."
                        // sed -i'' 兼容 Linux/macOS
                        sed -i'' 's|image:.*|image: $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER|' hello-k8s-app/k8s/deployment.yaml

                        echo "Applying deployment..."
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
                    # 复用全局 KUBECONFIG 环境变量
                    export KUBECONFIG=$KUBECONFIG
                    # 等待 Pod 就绪（超时 60 秒）
                    kubectl wait --for=condition=ready pod -l app=hello-k8s-app --timeout=60s || { echo "❌ Pod 启动超时"; exit 1; }
                    # 获取 NodeIP（优先取 InternalIP）和 NodePort
                    NODE_IP=\$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
                    NODE_PORT=\$(kubectl get svc hello-k8s-app-service -o jsonpath='{.spec.ports[0].nodePort}' --ignore-not-found)
                    # 校验 NodeIP 和 NodePort 是否有效
                    if [ -z "\$NODE_IP" ]; then
                        echo "❌ 无法获取 Node IP"; exit 1;
                    fi
                    if [ -z "\$NODE_PORT" ]; then
                        echo "❌ 无法获取 Service NodePort"; exit 1;
                    fi
                    # 测试应用访问（--fail 确保非 200 状态码报错）
                    echo "Testing application at http://\$NODE_IP:\$NODE_PORT..."
                    curl --retry 10 --retry-delay 5 --retry-connrefused --fail http://\$NODE_IP:\$NODE_PORT
                    """
                    // 输出最终访问地址（需先在 sh 外获取变量）
                    def nodeIp = sh(script: 'kubectl get node -o jsonpath="{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}"', returnStdout: true).trim()
                    def nodePort = sh(script: 'kubectl get svc hello-k8s-app-service -o jsonpath="{.spec.ports[0].nodePort}"', returnStdout: true).trim()
                    echo "✅ 部署成功！应用访问地址：http://$nodeIp:$nodePort"
                }
            }
        }
    }

    post {
        always {
            echo "流水线执行完毕"
            // 清理本地镜像（失败不影响流水线结果）
            sh "docker rmi $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER $REGISTRY/$PROJECT/$APP_NAME:latest || true"
            // 清理临时 kubeconfig 目录
            sh "rm -rf $WORKSPACE/tmp_kube $WORKSPACE/.env || true"
        }
    }
}
