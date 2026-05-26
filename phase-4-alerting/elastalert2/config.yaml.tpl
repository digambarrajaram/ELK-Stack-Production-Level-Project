es_host: elasticsearch
es_port: 9200
es_username: elastic
es_password: $ELASTIC_PASSWORD

use_ssl: true
verify_certs: false

writeback_index: elastalert_status
writeback_alias: elastalert
run_every:
  minutes: 1
buffer_time:
  minutes: 15
alert_time_limit:
  days: 2
use_local_time: true
timezone: Asia/Kolkata
rules_folder: /opt/elastalert/rules
logging_level: INFO

smtp_host: $SMTP_HOST
smtp_port: $SMTP_PORT
smtp_auth_file: /opt/elastalert/smtp_auth.yaml
from_addr: $ALERT_FROM
email_reply_to: $ALERT_FROM
smtp_starttls: true
smtp_ssl: false
