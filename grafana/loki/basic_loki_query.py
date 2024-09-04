import requests
import json
from datetime import datetime
import pytz
import os
import logging
from datetime import timedelta

logging.basicConfig(level=logging.INFO)
loki_url_default = "https://nphub.nota.ai/loki/"
loki_url = os.getenv("LOKI_URL", "")
tz_name = os.getenv("TZ", "Asia/Seoul")
query_date_format = "%Y-%m-%dT%H:%M:%SZ"

if loki_url == "":
    loki_url = loki_url_default
    logging.info("LOKI_URL is not set. Use default value.")
logging.info("LOKI_URL: " + loki_url)
query_url = f"{loki_url}api/v1/query_range"
tz_info = pytz.timezone(tz_name)

if __name__ == "__main__":
    logging.info("Print query result")
    controller_name = "RawController"
    query = "{controller=\"Projects::" + controller_name + "\",action=\"show\", project!=\"\"}"
    end_date = datetime.now(tz_info)
    start_date = end_date - timedelta(days=7)
    end = end_date.strftime(query_date_format)
    start = start_date.strftime(query_date_format)
    response = requests.get(query_url, params={"query": query, "start": start, "end": end})
    result = response.json()
    result_status = result['status']
    result_type = result['data']['resultType']
    result_data = result['data']['result']
    i = 1
    print("time,timestamp,username,method,project,branch,file,status")
    for log in result_data:
        log_labels = log['stream']
        username = log_labels['username']
        path = log_labels['path']
        status = log_labels['status']
        method = log_labels['method']
        project = log_labels['project']
        log_values = log['values']
        path = path.split('/-/')
        branch = path[1].split("/")[1]
        file_path = "/".join(path[1].split("/")[2:])
        for log_value in log_values:
            timestamp = log_value[0]
            log_message = json.loads(log_value[1])
            utc_time = datetime.fromtimestamp(int(timestamp) / 1e9)
            local_time = datetime.fromtimestamp(int(timestamp) / 1e9, tz_info)
            time_string = local_time.strftime("%Y-%m-%d %H:%M:%S")
            print(f"{time_string},{timestamp},{username},{method},{project},@{branch},{file_path},{status}")
