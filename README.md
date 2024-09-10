# devtools
## grafana
### loki
* basic_loki_query.py
  * output
    ```shell
    /Users/sunjoo/program/venv/bin/python /Users/sunjoo/workspace/devtools/grafana/loki/basic_loki_query.py 
    INFO:root:LOKI_URL is not set. Use default value.
    INFO:root:LOKI_URL: https://nphub.nota.ai/loki/
    INFO:root:Print query result
    time,timestamp,username,method,project,branch,file,status
    2024-09-05 10:53:51,1725501231548289664,jeongho.kim,GET,np-application/system-cctv-fight-detection-v1,@main,main.gif,304
    2024-09-04 15:33:24,1725431604790741772,jeongho.kim,GET,np-application/system-cctv-fight-detection-v1,@main,main.gif,304
    2024-09-04 15:26:16,1725431176944436251,jeongho.kim,GET,np-application/system-cctv-fight-detection-v1,@main,main.gif,304
    2024-09-04 13:44:21,1725425061095127901,jeongho.kim,GET,np-application/system-cctv-fight-detection-v1,@main,main.gif,304
    2024-09-04 15:33:24,1725431604889053893,geonmin.kim,GET,np-application/model-vlm-qwenva-0.5b-v2,@main,images/vlm_image.png,200
    2024-09-04 14:54:39,1725429279187292540,geonmin.kim,GET,np-application/model-vlm-qwenva-0.5b-v2,@main,images/vlm_image.png,200
    2024-09-04 15:33:24,1725431604890758761,hancheol.park,GET,np-application/model-vlm-qwenva-0.5b-v1,@main,images/qwenva_image.png,200
    2024-09-04 14:54:47,1725429287208449472,hancheol.park,GET,np-application/model-vlm-qwenva-0.5b-v1,@main,images/qwenva_image.png,200
    2024-09-04 15:33:24,1725431604892552850,geonmin.kim,GET,np-application/model-vlm-qwenva-0.5b-v1,@main,images/qwenva_image.png,200
    2024-09-04 14:55:06,1725429306755955802,geonmin.kim,GET,np-application/model-vlm-qwenva-0.5b-v1,@main,images/qwenva_image.png,200
    2024-09-04 15:33:24,1725431604816771564,jeongho.kim,GET,np-application/model-eye-level-fall-detection-v1,@main,assets/example.png,304
    2024-09-04 15:26:16,1725431176966859727,jeongho.kim,GET,np-application/model-eye-level-fall-detection-v1,@main,assets/example.png,304
    2024-09-04 13:44:21,1725425061119708152,jeongho.kim,GET,np-application/model-eye-level-fall-detection-v1,@main,assets/example.png,304
    2024-09-04 13:36:14,1725424574448630294,jeongho.kim,GET,np-application/system-cctv-fight-detection-v1,@main,main.gif,304
    2024-09-04 13:36:14,1725424574476373485,jeongho.kim,GET,np-application/model-eye-level-fall-detection-v1,@main,assets/example.png,304
    ```