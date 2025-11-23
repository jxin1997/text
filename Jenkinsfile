pipeline {
    agent any

    environment {
        REGISTRY = "https://192.168.10.67"       // Harbor 地址
        PROJECT = "jenkins"
        APP_NAME = "hello-k8s-app"
        HARBOR_CREDENTIALS = credentialsId('12345678')  // Harbor 用户名密码
        KUBECONFIG_CREDENTIALS = credentials('kubeconfig-credentials') // Kubeconfig 文件
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'master', url: 'http://github.com/jxin1997/text.git'
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: '12345678', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS')]) {
                        sh """
                        echo "Logging into Harbor..."
                        docker login -u $HARBOR_USER -p $HARBOR_PASS $REGISTRY

                        echo "Building Docker image..."
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

        stage('Test Deployment') {
            steps {
                script {
                    sh """
                    export KUBECONFIG=$WORKSPACE/tmp_kube/config
                    NODE_PORT=\$(kubectl get svc hello-k8s-app-service -o jsonpath='{.spec.ports[0].nodePort}')
                    NODE_IP=\$(kubectl get node -o jsonpath='{.items[0].status.addresses[0].address}')
                    echo "Testing application at http://\$NODE_IP:\$NODE_PORT..."
                    curl --retry 10 --retry-delay 5 --retry-connrefused http://\$NODE_IP:\$NODE_PORT
                    """
                    echo "✅ 部署成功！应用访问地址：http://<NodeIP>:<NodePort>"
                }
            }
        }
    }

    post {
        always {
            echo "流水线执行完毕"
            sh "docker rmi $REGISTRY/$PROJECT/$APP_NAME:BUILD-$BUILD_NUMBER || true"
        }
    }
}
