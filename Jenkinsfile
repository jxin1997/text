pipeline {
    agent any

    environment {
        REGISTRY = "192.168.10.67"
        PROJECT = "jenkins"
        APP_NAME = "hello-k8s-app"
        // 关键修正：根据仓库实际路径调整 deployment.yaml 路径（二选一，按你的仓库结构修改）
        // 选项 A：若 deployment.yaml 在根目录 → K8S_DEPLOY_PATH = "deployment.yaml"
        // 选项 B：若 deployment.yaml 在 k8s/ 目录 → K8S_DEPLOY_PATH = "k8s/deployment.yaml"
        // 选项 C：若确实在 hello-k8s-app/k8s/ 目录 → 保持原路径（但需确认文件存在）
        K8S_DEPLOY_PATH = "k8s/deployment.yaml"  // 优先推荐此路径（按之前仓库文件列表）
        APP_CONTAINER_PORT = "5000"
    }

    stages {
        stage('Build & Push Docker Image') {
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: '12345678', 
                        usernameVariable: 'HARBOR_USER', 
                        passwordVariable: 'HARBOR_PASS'
                    )]) {
                        // 关键修正：用单引号字符串避免 Groovy 插值，通过环境变量传递密钥
                        sh '''
                        # 确保 Docker 服务正常
                        systemctl is-active --quiet docker || systemctl start docker

                        echo "Logging into Harbor..."
                        echo $HARBOR_PASS | docker login -u $HARBOR_USER --password-stdin $REGISTRY

                        echo "Building Docker image..."
                        docker build --no-cache -t $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER ./hello-k8s-app

                        echo "Pushing Docker images..."
                        docker push $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER
                        docker tag $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER $REGISTRY/$PROJECT/$APP_NAME:latest
                        docker push $REGISTRY/$PROJECT/$APP_NAME:latest

                        docker logout $REGISTRY
                        '''
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
                        // 关键修正：用单引号字符串 + 环境变量，避免密钥插值警告
                        sh '''
                        # 配置 KUBECONFIG
                        mkdir -p $WORKSPACE/.kube
                        cp $KUBECONFIG_FILE $WORKSPACE/.kube/config
                        export KUBECONFIG=$WORKSPACE/.kube/config

                        # 验证 K8s 连接
                        kubectl cluster-info || {
                            echo "❌ 无法连接 Kubernetes 集群";
                            exit 1;
                        }

                        # 关键修正：先校验 deployment.yaml 文件是否存在
                        if [ ! -f "$K8S_DEPLOY_PATH" ]; then
                            echo "❌ 找不到 deployment.yaml 文件，实际路径：$K8S_DEPLOY_PATH";
                            echo "当前目录文件列表：";
                            ls -l $(dirname $K8S_DEPLOY_PATH);  # 输出上级目录文件，便于排查
                            exit 1;
                        fi

                        echo "Updating deployment.yaml with new image..."
                        # 修正 sed 命令：兼容 image 行的任意格式（避免匹配失败）
                        sed -i "s|image:.*$APP_NAME[:@].*|image: $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER|" $K8S_DEPLOY_PATH

                        echo "Applying deployment..."
                        kubectl apply -f $K8S_DEPLOY_PATH --record

                        # 等待 Deployment 就绪
                        kubectl rollout status deployment/$APP_NAME --timeout=90s || {
                            echo "❌ Deployment 就绪超时";
                            kubectl describe deployment/$APP_NAME;
                            exit 1;
                        }
                        '''
                    }
                }
            }
        }

        stage('Test Deployment') {
            steps {
                script {
                    withCredentials([file(
                        credentialsId: 'kubeconfig-credentials', 
                        variable: 'KUBECONFIG_FILE'
                    )]) {
                        sh '''
                        export KUBECONFIG=$WORKSPACE/.kube/config
                        '''

                        sh '''
                        # 等待 Pod 就绪
                        kubectl wait --for=condition=ready pod -l app=$APP_NAME --timeout=60s || {
                            echo "❌ Pod 启动超时或未就绪";
                            kubectl describe pod -l app=$APP_NAME;
                            exit 1;
                        }
                        '''

                        // 获取 Pod 名称和 NodeIP
                        def podName = sh(
                            script: 'kubectl get pods -l app=$APP_NAME -o jsonpath="{.items[0].metadata.name}"',
                            returnStdout: true
                        ).trim()

                        def nodeIp = sh(
                            script: "kubectl get pod $podName -o jsonpath='{.status.hostIP}'",
                            returnStdout: true
                        ).trim()

                        // 获取 NodePort
                        def nodePort = sh(
                            script: 'kubectl get svc $APP_NAME-service -o jsonpath="{.spec.ports[0].nodePort}" --ignore-not-found',
                            returnStdout: true
                        ).trim()

                        // 验证参数
                        if (podName.empty) {
                            echo "❌ 未找到 $APP_NAME 对应的 Pod";
                            exit 1;
                        }
                        if (nodeIp.empty) {
                            echo "❌ 无法获取 Pod $podName 所在 Node 的 IP";
                            exit 1;
                        }
                        if (nodePort.empty) {
                            echo "❌ 未找到 $APP_NAME-service Service 或未配置 NodePort";
                            exit 1;
                        }

                        // 测试应用访问
                        echo "🔍 测试访问应用：http://${nodeIp}:${nodePort}";
                        sh """
                        curl --retry 10 \
                             --retry-delay 5 \
                             --retry-connrefused \
                             --connect-timeout 10 \
                             --max-time 20 \
                             --fail \
                             -v http://${nodeIp}:${nodePort} || {
                            echo "❌ 应用访问失败";
                            kubectl logs $podName;
                            exit 1;
                        }
                        """

                        // 验证响应内容（根据实际应用调整）
                        sh """
                        RESPONSE=\$(curl -s http://${nodeIp}:${nodePort})
                        if [[ ! \$RESPONSE =~ "Hello Kubernetes" ]]; then
                            echo "❌ 应用响应内容不符合预期（实际响应：\$RESPONSE）";
                            exit 1;
                        fi
                        """

                        echo "✅ 部署成功！";
                        echo "📌 应用访问地址：http://${nodeIp}:${nodePort}";
                        echo "📌 Pod 名称：$podName";
                        echo "📌 镜像版本：$REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER";
                    }
                }
            }
        }
    }

    post {
        always {
            // 关键修正：删除多余的中文括号 `）`，修复语法错误
            echo "📝 流水线执行完毕（构建号：$BUILD_NUMBER）"
            sh '''
            # 清理临时文件
            rm -rf $WORKSPACE/.kube || true
            rm -rf .env || true

            # 清理 Docker 镜像
            if [ -n "$REGISTRY" ] && [ -n "$PROJECT" ] && [ -n "$APP_NAME" ] && [ -n "$BUILD_NUMBER" ]; then
                docker rmi $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER $REGISTRY/$PROJECT/$APP_NAME:latest || true
            else
                echo "⚠️  环境变量不完整，跳过 Docker 镜像清理"
            fi
            '''
        }
        success {
            echo "🎉 流水线执行成功！"
        }
        failure {
            echo "❌ 流水线执行失败，请查看日志排查问题！"
        }
    }
}
