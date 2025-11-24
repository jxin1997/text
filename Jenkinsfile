pipeline {
    agent any

    environment {
        REGISTRY = "192.168.10.67"
        PROJECT = "jenkins"
        APP_NAME = "hello-k8s-app"
        K8S_DEPLOY_PATH = "k8s/deployment.yaml"
        APP_CONTAINER_PORT = "5000"
        // 直接在环境变量中定义 kubeconfig 路径（避免步骤间传递）
        KUBE_TEMP_DIR = sh(script: 'mktemp -d /tmp/jenkins-kube-XXXXXX', returnStdout: true).trim()
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
                        sh """
                        cp $KUBECONFIG_FILE $KUBE_TEMP_DIR/config
                        export KUBECONFIG=$KUBE_TEMP_DIR/config

                        kubectl cluster-info || {
                            echo "❌ K8s 连接失败";
                            rm -rf $KUBE_TEMP_DIR;
                            exit 1;
                        }


                        sed -i "s|image:.*$APP_NAME[:@].*|image: $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER|" $K8S_DEPLOY_PATH


                        kubectl apply -f $K8S_DEPLOY_PATH
                        echo "等待 Deployment 就绪..."
                        kubectl rollout status deployment/$APP_NAME --timeout=90s || {
                            echo "❌ Deployment 就绪超时";
                            kubectl describe deployment/$APP_NAME;
                            rm -rf $KUBE_TEMP_DIR;
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
                        variable: 'KUBECONFIG_FILE'  // 仅占位，实际用全局临时目录的 config
                    )]) {
                        // 关键修复：直接使用全局临时目录的 kubeconfig，不依赖环境变量传递
                        sh """
                        KUBECONFIG=$KUBE_TEMP_DIR/config

                        echo "等待 Pod 就绪..."
                        kubectl --kubeconfig=\$KUBECONFIG wait --for=condition=ready pod -l app=$APP_NAME --timeout=60s || {
                            echo "❌ Pod 就绪超时";
                            kubectl --kubeconfig=\$KUBECONFIG describe pod -l app=$APP_NAME;
                            rm -rf $KUBE_TEMP_DIR;
                            exit 1;
                        }

                        POD_NAME=\$(kubectl --kubeconfig=\$KUBECONFIG get pods -l app=$APP_NAME -o jsonpath="{.items[0].metadata.name}")
                        NODE_IP=\$(kubectl --kubeconfig=\$KUBECONFIG get pod \$POD_NAME -o jsonpath="{.status.hostIP}")
                        NODE_PORT=\$(kubectl --kubeconfig=\$KUBECONFIG get svc $APP_NAME-service -o jsonpath="{.spec.ports[0].nodePort}")

                    
                        if [ -z "\$POD_NAME" ] || [ -z "\$NODE_IP" ] || [ -z "\$NODE_PORT" ]; then
                            echo "❌ 无法获取 Pod/NodeIP/NodePort";
                            kubectl --kubeconfig=\$KUBECONFIG get pods;
                            kubectl --kubeconfig=\$KUBECONFIG get svc;
                            rm -rf $KUBE_TEMP_DIR;
                            exit 1;
                        fi

                  
                        echo "🔍 测试访问：http://\$NODE_IP:\$NODE_PORT"
                        curl --retry 10 \
                             --retry-delay 5 \
                             --retry-connrefused \
                             --connect-timeout 10 \
                             --max-time 20 \
                             --fail \
                             -v http://\$NODE_IP:\$NODE_PORT || {
                            echo "❌ 应用访问失败";
                            kubectl --kubeconfig=\$KUBECONFIG logs \$POD_NAME;
                            rm -rf $KUBE_TEMP_DIR;
                            exit 1;
                        }

                        
                        RESPONSE=\$(curl -s http://\$NODE_IP:\$NODE_PORT)
                        if [[ ! \$RESPONSE =~ "Hello Kubernetes" ]]; then
                            echo "❌ 响应内容不符合预期：\$RESPONSE";
                            rm -rf $KUBE_TEMP_DIR;
                            exit 1;
                        fi

                        echo "✅ 部署测试成功！";
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
            // 终极修复：删除所有中文括号！！！确保是英文 ()
            echo "📝 流水线执行完毕（构建号：$BUILD_NUMBER）"
            sh '''
            // 清理临时目录和垃圾文件
            if [ -d "$KUBE_TEMP_DIR" ]; then
                rm -rf $KUBE_TEMP_DIR
            fi
            rm -f $WORKSPACE/kube_temp_dir.* || true
            rm -rf .env || true

            // 清理 Docker 镜像
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
