pipeline {
    agent any

    environment {
        REGISTRY = "192.168.10.67"
        PROJECT = "jenkins"
        APP_NAME = "hello-k8s-app"
        K8S_DEPLOY_PATH = "k8s/deployment.yaml"  // 已验证路径正确
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
                        sh '''
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
                        // 生成唯一临时目录（避免并行冲突）
                        def kubeTempDir = sh(script: 'mktemp -d /tmp/jenkins-kubeconfig-XXXXXX', returnStdout: true).trim()
                        echo "使用临时目录存储 kubeconfig：$kubeTempDir"

                        sh """
                        # 复制 kubeconfig 到临时目录
                        cp $KUBECONFIG_FILE $kubeTempDir/config
                        export KUBECONFIG=$kubeTempDir/config

                        # 验证 K8s 连接（确保凭证有效）
                        kubectl cluster-info || {
                            echo "❌ 无法连接 Kubernetes 集群";
                            rm -rf $kubeTempDir;
                            exit 1;
                        }

                        # 校验 deployment.yaml 存在性
                        if [ ! -f "$K8S_DEPLOY_PATH" ]; then
                            echo "❌ 找不到 deployment.yaml 文件：$K8S_DEPLOY_PATH";
                            ls -l $(dirname $K8S_DEPLOY_PATH);
                            rm -rf $kubeTempDir;
                            exit 1;
                        fi

                        # 更新镜像版本
                        echo "Updating deployment.yaml with new image..."
                        sed -i "s|image:.*$APP_NAME[:@].*|image: $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER|" $K8S_DEPLOY_PATH

                        # 应用部署
                        kubectl apply -f $K8S_DEPLOY_PATH
                        echo "等待 Deployment 就绪..."
                        kubectl rollout status deployment/$APP_NAME --timeout=90s || {
                            echo "❌ Deployment 就绪超时";
                            kubectl describe deployment/$APP_NAME;
                            rm -rf $kubeTempDir;
                            exit 1;
                        }

                        # 存储临时目录路径到文件（供测试阶段使用）
                        echo "$kubeTempDir" > $WORKSPACE/kube_temp_dir.txt
                        """
                    }
                }
            }
        }

        stage('Test Deployment') {
            steps {
                script {
                    // 读取部署阶段的临时目录（直接读取文件，避免环境变量传递问题）
                    def kubeTempDir = readFile("$WORKSPACE/kube_temp_dir.txt").trim()
                    echo "测试阶段使用 kubeconfig 目录：$kubeTempDir"

                    withCredentials([file(
                        credentialsId: 'kubeconfig-credentials', 
                        variable: 'KUBECONFIG_FILE'  // 仅占位，实际使用临时目录的 kubeconfig
                    )]) {
                        sh """
                        # 强制设置 KUBECONFIG，确保 kubectl 识别
                        export KUBECONFIG=$kubeTempDir/config

                        # 1. 等待 Pod 就绪（增加重试，兼容网络延迟）
                        echo "等待 Pod 就绪..."
                        kubectl wait --for=condition=ready pod -l app=$APP_NAME --timeout=60s || {
                            echo "❌ Pod 启动超时或未就绪";
                            kubectl describe pod -l app=$APP_NAME;
                            rm -rf $kubeTempDir;
                            exit 1;
                        }

                        # 2. 获取 Pod 名称和所在 NodeIP
                        POD_NAME=\$(kubectl get pods -l app=$APP_NAME -o jsonpath="{.items[0].metadata.name}")
                        NODE_IP=\$(kubectl get pod \$POD_NAME -o jsonpath="{.status.hostIP}")
                        echo "Pod 名称：\$POD_NAME，所在 NodeIP：\$NODE_IP"

                        # 3. 获取 NodePort
                        NODE_PORT=\$(kubectl get svc $APP_NAME-service -o jsonpath="{.spec.ports[0].nodePort}" --ignore-not-found)
                        if [ -z "\$NODE_PORT" ]; then
                            echo "❌ 未找到 $APP_NAME-service 的 NodePort";
                            kubectl get svc;
                            rm -rf $kubeTempDir;
                            exit 1;
                        fi
                        echo "Service NodePort：\$NODE_PORT"

                        # 4. 测试应用访问
                        echo "🔍 测试访问：http://\$NODE_IP:\$NODE_PORT"
                        curl --retry 10 \
                             --retry-delay 5 \
                             --retry-connrefused \
                             --connect-timeout 10 \
                             --max-time 20 \
                             --fail \
                             -v http://\$NODE_IP:\$NODE_PORT || {
                            echo "❌ 应用访问失败";
                            kubectl logs \$POD_NAME;
                            rm -rf $kubeTempDir;
                            exit 1;
                        }

                        # 5. 验证响应内容（根据实际应用调整）
                        RESPONSE=\$(curl -s http://\$NODE_IP:\$NODE_PORT)
                        if [[ ! \$RESPONSE =~ "Hello Kubernetes" ]]; then
                            echo "❌ 响应内容不符合预期：\$RESPONSE";
                            rm -rf $kubeTempDir;
                            exit 1;
                        fi

                        # 6. 清理临时目录（测试成功后）
                        rm -rf $kubeTempDir
                        rm -f $WORKSPACE/kube_temp_dir.txt

                        echo "✅ 部署测试全部成功！";
                        echo "📌 访问地址：http://\$NODE_IP:\$NODE_PORT";
                        echo "📌 镜像版本：$REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER";
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            // 关键修复：彻底删除中文括号！！！确保是英文括号 ()
            echo "📝 流水线执行完毕（构建号：$BUILD_NUMBER）"
            sh '''
            # 兜底清理：防止测试阶段未清理的临时目录
            if [ -f "$WORKSPACE/kube_temp_dir.txt" ]; then
                KUBE_TEMP_DIR=\$(cat $WORKSPACE/kube_temp_dir.txt)
                rm -rf \$KUBE_TEMP_DIR
                rm -f $WORKSPACE/kube_temp_dir.txt
            fi
            rm -rf .env || true

            # 清理 Docker 镜像
            if [ -n "$REGISTRY" ] && [ -n "$PROJECT" ] && [ -n "$APP_NAME" ] && [ -n "$BUILD_NUMBER" ]; then
                docker rmi $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER $REGISTRY/$PROJECT/$APP_NAME:latest || true
            fi
            '''
        }
        success {
            echo "🎉 流水线全流程执行成功！"
        }
        failure {
            echo "❌ 流水线执行失败，请查看日志排查问题！"
        }
    }
}
