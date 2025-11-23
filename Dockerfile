# 使用官方Python轻量级基础镜像
FROM python:3.9-slim
# 设置工作目录
WORKDIR /app
# 复制依赖文件并安装
COPY requirements.txt .
RUN pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
# 复制应用代码
COPY app.py .
# 暴露应用运行的端口
EXPOSE 5000
# 定义容器启动命令
CMD ["python", "app.py"]
