pipeline {
    agent any

    environment {
        REGISTRY = "192.168.10.67"
        PROJECT = "jenkins"
        APP_NAME = "hello-k8s-app"
        // K8s 相关路径统一配置（便于维护）
        K8S_DEPLOY_PATH = "hello-k8s-app/k8s/deployment.yaml"
        // 应用访问端口（需与 deployment.yaml 中容器端口一致）
        APP_CONTAINER_PORT = "5000"
    }

    stages { // 关键修正：补充 stages 包裹所有 stage（原脚本缺失，导致语法错误）
        stage('Build & Push Docker Image') {
            steps {
                script {
                    // 修正：凭证 ID 建议用有意义的名称（如 harbor-admin-cred），避免硬编码 12345678
                    withCredentials([usernamePassword(
                        credentialsId: '12345678', 
                        usernameVariable: 'HARBOR_USER', 
                        passwordVariable: 'HARBOR_PASS'
                    )]) {
                        sh """
                        # 确保 Docker 服务正常（避免服务未启动导致失败）
                        systemctl is-active --quiet docker || systemctl start docker

                        echo "Logging into Harbor..."
                        # 优化：使用 --password-stdin 更安全（避免 CLI 密码暴露警告）
                        echo $HARBOR_PASS | docker login -u $HARBOR_USER --password-stdin $REGISTRY

                        echo "Building Docker image..."
                        # 优化：添加 --no-cache 避免缓存导致的镜像构建不更新（可选，根据需求开启）
                        docker build --no-cache -t $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER ./hello-k8s-app

                        echo "Pushing Docker images..."
                        docker push $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER
                        docker tag $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER $REGISTRY/$PROJECT/$APP_NAME:latest
                        docker push $REGISTRY/$PROJECT/$APP_NAME:latest

                        # 优化：登出 Harbor（避免凭证残留）
                        docker logout $REGISTRY
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
                        # 1. 配置 KUBECONFIG（优化：使用临时目录，避免权限问题）
                        mkdir -p $WORKSPACE/.kube
                        cp $KUBECONFIG_FILE $WORKSPACE/.kube/config
                        export KUBECONFIG=$WORKSPACE/.kube/config

                        # 2. 验证 K8s 连接（提前排查集群可达性）
                        kubectl cluster-info || {
                            echo "❌ 无法连接 Kubernetes 集群";
                            exit 1;
                        }

                        # 3. 更新 Deployment 镜像（优化：使用 sed 精确匹配 image 行，避免误改）
                        echo "Updating deployment.yaml with new image..."
                        sed -i "s|image:.*$APP_NAME:.*|image: $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER|" $K8S_DEPLOY_PATH

                        # 4. 应用 Deployment（优化：添加 --record 记录部署历史，便于回滚）
                        echo "Applying deployment..."
                        kubectl apply -f $K8S_DEPLOY_PATH --record

                        # 5. 等待 Deployment 就绪（避免立即进入测试阶段导致失败）
                        kubectl rollout status deployment/$APP_NAME --timeout=90s || {
                            echo "❌ Deployment 就绪超时";
                            kubectl describe deployment/$APP_NAME; # 输出日志便于排查
                            exit 1;
                        }
                        """
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
                        sh """
                        # 配置 KUBECONFIG（与部署阶段保持一致）
                        export KUBECONFIG=$WORKSPACE/.kube/config
                        """

                        // 1. 等待 Pod 就绪（优化：匹配 Deployment 的 selector，避免多 Pod 干扰）
                        sh """
                        kubectl wait --for=condition=ready pod -l app=$APP_NAME --timeout=60s || {
                            echo "❌ Pod 启动超时或未就绪";
                            kubectl describe pod -l app=$APP_NAME; # 输出 Pod 日志便于排查
                            exit 1;
                        }
                        """

                        // 2. 获取 NodeIP（优化：选择运行当前 Pod 的 Node，避免跨节点访问问题）
                        def podName = sh(
                            script: "kubectl get pods -l app=$APP_NAME -o jsonpath='{.items[0].metadata.name}'",
                            returnStdout: true
                        ).trim()

                        def nodeIp = sh(
                            script: "kubectl get pod $podName -o jsonpath='{.status.hostIP}'",
                            returnStdout: true
                        ).trim()

                        // 3. 获取 NodePort（优化：处理 Service 未创建的情况，补充报错信息）
                        def nodePort = sh(
                            script: "kubectl get svc $APP_NAME-service -o jsonpath='{.spec.ports[0].nodePort}' --ignore-not-found",
                            returnStdout: true
                        ).trim()

                        // 4. 验证关键参数非空
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
                            echo "请确保已创建 Service 并配置 NodePort 类型";
                            exit 1;
                        }

                        // 5. 测试应用访问（优化：增加超时时间，验证响应内容）
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
                            kubectl logs $podName; # 输出应用日志便于排查
                            exit 1;
                        }
                        """

                        // 6. （可选）验证响应内容（根据你的应用返回值调整，如返回 "Hello Kubernetes"）
                        sh """
                        RESPONSE=\$(curl -s http://${nodeIp}:${nodePort})
                        if [[ ! \$RESPONSE =~ "Hello Kubernetes" ]]; then
                            echo "❌ 应用响应内容不符合预期（实际响应：\$RESPONSE）";
                            exit 1;
                        fi
                        """

                        // 7. 输出成功信息
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
            echo "📝 流水线执行完毕（构建号：$BUILD_NUMBER）"
            // 优化：清理临时文件和 Docker 镜像（增加错误忽略，避免流水线失败）
            sh """
            # 清理 KUBECONFIG 临时文件
            rm -rf $WORKSPACE/.kube || true
            rm -rf .env || true

            # 清理 Docker 镜像（忽略不存在的镜像错误）
            if [ -n "$REGISTRY" ] && [ -n "$PROJECT" ] && [ -n "$APP_NAME" ] && [ -n "$BUILD_NUMBER" ]; then
                docker rmi $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER $REGISTRY/$PROJECT/$APP_NAME:latest || true
            else
                echo "⚠️  环境变量不完整，跳过 Docker 镜像清理"
            fi
            """
        }
        success {
            echo "🎉 流水线执行成功！"
        }
        failure {
            echo "❌ 流水线执行失败，请查看日志排查问题！"
            // 可选：发送失败通知（如邮件、企业微信）
        }
    }
}
