
from flask import Flask, jsonify
import subprocess
import json
import logging

app = Flask(__name__)

# 设置日志记录
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def get_vnstat_data():
    try:
        logging.info("获取 vnStat 流量数据。")
        # 获取 vnStat 的 JSON 输出
        result = subprocess.run(['vnstat', '--json'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode != 0:
            error_message = result.stderr.strip()
            logging.error(f"vnStat 错误: {error_message}")
            # 检查是否由于 vnStat 版本过低导致的错误
            if 'unrecognized option' in error_message or 'invalid option' in error_message:
                error_message += "。请确保 vnStat 版本为 2.x 及以上，并支持 '--json' 参数。"
            return {"error": error_message}

        data = json.loads(result.stdout)

        # 获取所有接口的数据
        interfaces = data.get('interfaces', [])

        if not interfaces:
            error_msg = "未找到任何被 vnStat 监控的网络接口。"
            logging.error(error_msg)
            return {"error": error_msg}

        # 过滤具有实际流量数据的接口
        interfaces_with_traffic = []

        for iface in interfaces:
            traffic = iface.get('traffic', {})
            has_traffic = False

            # 检查 'total' 流量
            total_rx = traffic.get('total', {}).get('rx', 0)
            total_tx = traffic.get('total', {}).get('tx', 0)
            if total_rx > 0 or total_tx > 0:
                has_traffic = True
            else:
                # 如果 'total' 为零，检查 'day' 数据
                days = traffic.get('day', [])
                for day in days:
                    day_rx = day.get('rx', 0)
                    day_tx = day.get('tx', 0)
                    if day_rx > 0 or day_tx > 0:
                        has_traffic = True
                        break

            if has_traffic:
                interfaces_with_traffic.append(iface)

        if not interfaces_with_traffic:
            error_msg = "未检测到任何具有流量数据的接口。"
            logging.info(error_msg)
            return {"message": error_msg}

        return {"interfaces": interfaces_with_traffic}

    except Exception as e:
        logging.exception("获取 vnStat 数据时发生异常。")
        return {"error": str(e)}

@app.route('/api/traffic', methods=['GET'])
def traffic():
    data = get_vnstat_data()
    return jsonify(data)

if __name__ == '__main__':
    # 从环境变量或默认值获取主机和端口
    import os
    host = os.environ.get('APP_HOST', '::')  # 修改默认值为 '::'
    port = int(os.environ.get('APP_PORT', '5000'))

    # 运行 Flask 应用程序
    app.run(host=host, port=port)
